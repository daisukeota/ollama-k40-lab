# syntax=docker/dockerfile:1.6

# =============================================================================
# Ollama for NVIDIA Tesla K40 (Compute Capability 3.5 / sm_35)
# Base: daisukeota/ollama-v0.3.14-cc35-dokploy (CUDA 11.4 + Ubuntu 20.04)
# Target: Ollama >= v0.5.0 (Structured Outputs: format=<JSON Schema object>)
# Method inspiration: dogkeeper886/ollama37 (legacy Kepler + modern Ollama)
# =============================================================================
#
# Note: v0.4.3 accepts format as string ("json") only.
#       JSON Schema objects require api.ChatRequest.Format = json.RawMessage (0.5.0+).

ARG OLLAMA_VERSION=v0.5.4
ARG GOLANG_VERSION=1.23.4
ARG CMAKE_VERSION=3.26.4

# -----------------------------------------------------------------------------
# Builder
# -----------------------------------------------------------------------------
FROM nvidia/cuda:11.4.3-devel-ubuntu20.04 AS builder

ARG OLLAMA_VERSION
ARG GOLANG_VERSION
ARG CMAKE_VERSION
ARG CUDA_ARCHITECTURES=35

ENV DEBIAN_FRONTEND=noninteractive \
    CGO_ENABLED=1 \
    CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
    OLLAMA_SKIP_CUDA_GENERATE= \
    OLLAMA_SKIP_ROCM_GENERATE=1 \
    PATH=/usr/local/go/bin:/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    LIBRARY_PATH=/usr/local/cuda/lib64/stubs \
    # CUDA 11.4 nvcc + GCC 11 + -std=c++17 breaks on std_function.h ("parameter packs not expanded").
    # Keep gcc-11 for Go/CGO; force nvcc host compiler to g++-10 (officially supported by CUDA 11.4).
    CUDAHOSTCXX=/usr/bin/g++-10 \
    NVCC_PREPEND_FLAGS="-ccbin /usr/bin/g++-10"

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      build-essential \
      software-properties-common \
      ccache \
      pigz \
      gcc-10 \
      g++-10 \
    && add-apt-repository -y ppa:ubuntu-toolchain-r/test \
    && apt-get update && apt-get install -y --no-install-recommends \
      gcc-11 \
      g++-11 \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 110 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 110 \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 100 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz" \
      | tar -C /usr/local -xz

RUN curl -fsSL "https://cmake.org/files/v${CMAKE_VERSION%.*}/cmake-${CMAKE_VERSION}-linux-x86_64.sh" \
      -o /tmp/cmake.sh \
    && chmod +x /tmp/cmake.sh \
    && /tmp/cmake.sh --prefix=/usr/local --skip-license \
    && rm /tmp/cmake.sh

# make/cuda-v11-defs.make looks for ${CUDA_PATH}-11 (default /usr/local/cuda-11)
RUN ln -sfn /usr/local/cuda /usr/local/cuda-11

WORKDIR /src
RUN git clone --depth 1 --branch "${OLLAMA_VERSION}" https://github.com/ollama/ollama.git .

# Lower GPU gate from CC 5.0 -> CC 3.5
# - 0.5.x+: CudaComputeMajorMin / CudaComputeMinorMin (strings, ldflags-friendly)
# - 0.4.x:  var CudaComputeMin = [2]C.int{5, 0}
RUN if grep -q 'CudaComputeMajorMin' discover/gpu.go; then \
      sed -i \
        -e 's/CudaComputeMajorMin = "5"/CudaComputeMajorMin = "3"/' \
        -e 's/CudaComputeMinorMin = "0"/CudaComputeMinorMin = "5"/' \
        discover/gpu.go; \
    elif grep -q 'var CudaComputeMin = \[2\]C.int{5, 0}' discover/gpu.go; then \
      sed -i 's/var CudaComputeMin = \[2\]C.int{5, 0}/var CudaComputeMin = [2]C.int{3, 5}/' discover/gpu.go; \
    else \
      echo "WARN: unknown CudaCompute* form; applying comparison-site rewrite"; \
      sed -i 's/CudaComputeMin\[0\]/3/g; s/CudaComputeMin\[1\]/5/g' discover/gpu.go; \
    fi \
    && grep -nE 'CudaCompute(Major|Minor)?Min' discover/gpu.go | head -n 20

# Build CUDA 11 runners for sm_35 only (no cuda-12 path present), then the Go server
RUN make -j"$(nproc)" runners \
      CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES}" \
      OLLAMA_SKIP_ROCM_GENERATE=1

RUN mkdir -p dist/linux-amd64/bin \
    && go build -trimpath \
         -ldflags "-s -w \
           -X=github.com/ollama/ollama/version.Version=${OLLAMA_VERSION} \
           -X=github.com/ollama/ollama/discover.CudaComputeMajorMin=3 \
           -X=github.com/ollama/ollama/discover.CudaComputeMinorMin=5" \
         -o dist/linux-amd64/bin/ollama .

# gcc-11 libstdc++ (GLIBCXX_3.4.29+) — runtime CUDA 20.04 image is too old for these symbols
RUN mkdir -p /opt/gcc11-libs \
    && cp -a /usr/lib/x86_64-linux-gnu/libstdc++.so.6* /opt/gcc11-libs/ \
    && cp -a /usr/lib/x86_64-linux-gnu/libgcc_s.so.1 /opt/gcc11-libs/ \
    && strings /opt/gcc11-libs/libstdc++.so.6 | grep -E 'GLIBCXX_3\.4\.29|CXXABI_1\.3\.13' | sort -u

# -----------------------------------------------------------------------------
# Runtime (Dokploy / compose)
# -----------------------------------------------------------------------------
FROM nvidia/cuda:11.4.3-runtime-ubuntu20.04

ENV DEBIAN_FRONTEND=noninteractive \
    OLLAMA_HOST=0.0.0.0:11434 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    # Prefer bundled gcc-11 libs over distro libstdc++ (fixes GLIBCXX_3.4.29 / CXXABI_1.3.13)
    LD_LIBRARY_PATH=/opt/gcc11-libs:/usr/lib/ollama:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /root/.ollama /opt/gcc11-libs

COPY --from=builder /src/dist/linux-amd64/bin/ollama /bin/ollama
COPY --from=builder /src/dist/linux-amd64/lib/ /lib/
COPY --from=builder /opt/gcc11-libs/ /opt/gcc11-libs/

EXPOSE 11434
VOLUME ["/root/.ollama"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
  CMD /bin/ollama list || exit 1

ENTRYPOINT ["/bin/ollama"]
CMD ["serve"]
