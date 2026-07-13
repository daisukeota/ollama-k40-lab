# Build notes — Ollama K40 Lab (sm_35)

## Why CUDA 11.4

Tesla K40 (CC 3.5) needs an older nvcc that still emits `sm_35`. CUDA 12+ drops `compute_35`.  
Host driver should stay on the **470** branch (last Kepler support).

## Structured Outputs version gate

| Ollama | `ChatRequest.format` | JSON Schema object |
|--------|----------------------|--------------------|
| ≤ 0.4.x | `string` | **No** (`"json"` only) |
| ≥ 0.5.0 | `json.RawMessage` | **Yes** |

Error on 0.4.3 with a schema object:

```text
json: cannot unmarshal object into Go struct field ChatRequest.format of type string
```

Default build tag for this repo: **v0.5.4**.

## Detection path (Makefile)

Ollama v0.5.x top-level `Makefile` includes `make/cuda-v11-defs.make`, which enables `cuda_v11` when `/usr/local/cuda-11` exists.  
The Dockerfile creates:

```text
/usr/local/cuda-11 -> /usr/local/cuda
```

With only the `-11` symlink present, `cuda_v12` is not selected (no `/usr/local/cuda-12`).

## Architecture

`make/Makefile.cuda_v11` defaults to:

```make
CUDA_ARCHITECTURES?=50;52;53;60;61;62;70;72;75;80;86
```

We override:

```bash
make dist CUDA_ARCHITECTURES=35
```

so only **sm_35** CUBIN is built (faster build, matches K40).  
Use **`make dist`** (not only `make runners`) so artifacts land in `dist/linux-amd64/lib/ollama/` for the runtime image COPY.

## GPU minimum gate

Upstream rejects GPUs older than CC 5.0. In **0.5.x**:

```go
var (
	CudaComputeMajorMin = "5"
	CudaComputeMinorMin = "0"
)
```

We rewrite to `"3"` / `"5"` and also pass ldflags:

```text
-X=github.com/ollama/ollama/discover.CudaComputeMajorMin=3
-X=github.com/ollama/ollama/discover.CudaComputeMinorMin=5
```

Older **0.4.x** used `var CudaComputeMin = [2]C.int{5, 0}`; the Dockerfile still has a fallback sed for that form.

## Relationship to ollama37

[dogkeeper886/ollama37](https://github.com/dogkeeper886/ollama37) targets **K80 / sm_37** with a polished builder/runtime split and follows newer Ollama.  
This repo keeps the **Dokploy-friendly single Dockerfile** style from `ollama-v0.3.14-cc35-dokploy`, but lifts the Ollama tag to **0.5.4+** and forces **sm_35**.

To chase newer tags (0.6.x+), expect to rework patches when `discover/gpu.go` or the Make/CMake layout changes.

## Structured Outputs check

After deploy:

```bash
docker exec ollama-k40c ollama -v
```

Version must be **≥ 0.5.0**, then test `/api/chat` with a JSON Schema in `format` (see README).

## CUDA host compiler (GCC 10 vs 11)

Ollama 0.5.x CUDA runners compile with `-std=c++17`.  
**CUDA 11.4 nvcc + GCC 11** hits a known libstdc++ bug:

```text
/usr/include/c++/11/bits/std_function.h: error: parameter packs not expanded with '...'
```

Dockerfile sets:

```text
CUDAHOSTCXX=/usr/bin/g++-10
NVCC_PREPEND_FLAGS="-ccbin /usr/bin/g++-10"
```

Default `gcc`/`g++` remain **11** (Go/CGO + runtime `libstdc++`). Only nvcc host code uses **g++-10**.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `cannot unmarshal object into ... format of type string` | Still on ≤0.4.x — rebuild with `OLLAMA_VERSION=v0.5.4+` |
| `std_function.h` / `parameter packs not expanded` | nvcc still on GCC 11 — ensure `NVCC_PREPEND_FLAGS=-ccbin /usr/bin/g++-10` |
| `dist/linux-amd64/lib: not found` | Used `make runners` only — need `make dist` so libs are installed under `dist/` |
| Build cannot find CUDA 11 | `/usr/local/cuda-11` symlink |
| `CUDA GPU is too old` | `CudaComputeMajorMin` / `MinorMin` patch + ldflags |
| `nvcc fatal: Unsupported gpu architecture 'compute_35'` | Using CUDA 12 by mistake |
| Container sees 0 GPUs / VRAM never grows | Host `nvidia-modprobe -u -c=0`; pin `NVIDIA_VISIBLE_DEVICES=0`; see [troubleshooting.md](troubleshooting.md) |
| Port already in use | Stop previous `ollama-k40c-v0314` on 11434 |
| `GLIBCXX_3.4.29` / `CXXABI_1.3.13` not found | Runtime must ship gcc-11 `libstdc++` (Dockerfile copies `/opt/gcc11-libs`). Rebuild image after pulling latest. |
| Go version too old | v0.5.4 needs Go **1.23.4** (Dockerfile ARG) |
| PaddleOCR also on this host | Do **not** give Paddle the K40; use GPU 1 or CPU (driver 470 ≠ cu118) |
