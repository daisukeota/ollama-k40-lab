# syntax=docker/dockerfile:1.6

# =============================================================================
# Ollama for NVIDIA Tesla K40 (Compute Capability 3.5 / sm_35)
#
# Builds dogkeeper886/ollama37 (Kepler-era fork that tracks modern Ollama) with
# native CUBIN for sm_35. Do NOT run dogkeeper886/ollama37 Hub images on K40 —
# those ship sm_37+ only.
#
# Toolchain: dogkeeper886/ollama37-builder (Rocky 8, CUDA 11.4, GCC 10, CMake 4, Go)
# Source pin: OLLAMA37_REF (default v2.2.3)
# =============================================================================

ARG OLLAMA37_REF=v2.2.3
ARG OLLAMA_VERSION=2.2.3-k40
ARG CMAKE_CUDA_ARCHITECTURES=35-real

# -----------------------------------------------------------------------------
# Builder (reuse ollama37 toolchain; compile sm_35 CUBIN)
# -----------------------------------------------------------------------------
FROM dogkeeper886/ollama37-builder AS builder

ARG OLLAMA37_REF
ARG OLLAMA_VERSION
ARG CMAKE_CUDA_ARCHITECTURES

ENV PATH="/usr/local/go/bin:/usr/local/cuda-11.4/bin:${PATH}" \
    LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64:/usr/lib64:${LD_LIBRARY_PATH}"

WORKDIR /usr/local/src

# Shallow clone of the pinned ollama37 release tag
RUN git clone --depth 1 --branch "${OLLAMA37_REF}" https://github.com/dogkeeper886/ollama37.git

WORKDIR /usr/local/src/ollama37

# If a Go-side CC floor still exists (older layouts), lower it to 3.5.
RUN set -eux; \
    if grep -R --include='*.go' -l 'CudaComputeMajorMin' . >/dev/null 2>&1; then \
      grep -R --include='*.go' -l 'CudaComputeMajorMin' . | while read -r f; do \
        sed -i \
          -e 's/CudaComputeMajorMin = "5"/CudaComputeMajorMin = "3"/' \
          -e 's/CudaComputeMinorMin = "0"/CudaComputeMinorMin = "5"/' \
          -e 's/CudaComputeMinorMin = "7"/CudaComputeMinorMin = "5"/' \
          "$f"; \
      done; \
    else \
      echo "INFO: no CudaComputeMajorMin in tree (expected on ollama37 v2.x)"; \
    fi

# Reuse ollama37 "CUDA 11 K80" preset toolchain, but override CUBIN to sm_35 only.
# (-D wins over preset cacheVariables; do not ship Hub ollama37 images on K40.)
RUN CC=/usr/local/bin/gcc CXX=/usr/local/bin/g++ \
      cmake --preset "CUDA 11 K80" \
        -DCMAKE_CUDA_ARCHITECTURES="${CMAKE_CUDA_ARCHITECTURES}"

RUN CC=/usr/local/bin/gcc CXX=/usr/local/bin/g++ \
      cmake --build build -j"$(nproc)"

RUN cmake --install build --component CPU --strip \
    && cmake --install build --component CUDA --strip \
    && test -d dist/lib/ollama \
    && find dist/lib/ollama -type f | head -n 40

# Main binary; path layout expects /usr/bin/ollama -> ../lib/ollama
RUN mkdir -p dist/bin \
    && go build -trimpath \
         -ldflags "-s -w -X=github.com/ollama/ollama/version.Version=${OLLAMA_VERSION}" \
         -o dist/bin/ollama .

# -----------------------------------------------------------------------------
# Runtime (Dokploy / compose)
# -----------------------------------------------------------------------------
FROM rockylinux/rockylinux:8-minimal

ENV OLLAMA_HOST=0.0.0.0:11434 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    LD_LIBRARY_PATH=/usr/lib/ollama:/usr/local/nvidia/lib:/usr/local/nvidia/lib64

RUN microdnf install -y ca-certificates \
    && microdnf clean all \
    && mkdir -p /root/.ollama

COPY --from=builder /usr/local/src/ollama37/dist/bin/ollama /usr/bin/ollama
COPY --from=builder /usr/local/src/ollama37/dist/lib/ollama/ /usr/lib/ollama/
# GCC 10 runtime from ollama37-builder (Rocky 8 minimal ships older libstdc++)
COPY --from=builder /usr/local/lib64/libstdc++.so* /usr/lib64/
COPY --from=builder /usr/local/lib64/libgcc_s.so* /usr/lib64/

EXPOSE 11434
VOLUME ["/root/.ollama"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
  CMD /usr/bin/ollama list || exit 1

ENTRYPOINT ["/usr/bin/ollama"]
CMD ["serve"]
