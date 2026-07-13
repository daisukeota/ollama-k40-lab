# Build notes — Ollama K40 Lab (sm_35)

## Why CUDA 11.4

Tesla K40 (CC 3.5) needs an older nvcc that still emits `sm_35`. CUDA 12+ drops `compute_35`.  
Host driver should stay on the **470** branch (last Kepler support).

## Detection path (Makefile)

Ollama v0.4.3 `llama/Makefile` enables `cuda_v11` when `/usr/local/cuda-11` exists.  
The Dockerfile creates:

```text
/usr/local/cuda-11 -> /usr/local/cuda
```

## Architecture

`llama/make/Makefile.cuda_v11` defaults to:

```make
CUDA_ARCHITECTURES?=50;52;53;60;61;62;70;72;75;80;86
```

We override:

```bash
make runners CUDA_ARCHITECTURES=35
```

so only **sm_35** CUBIN is built (faster build, matches K40).

## GPU minimum gate

Upstream rejects GPUs older than CC 5.0 via:

```go
var CudaComputeMin = [2]C.int{5, 0}
```

We rewrite to `{3, 5}` so K40 is accepted.

## Relationship to ollama37

[dogkeeper886/ollama37](https://github.com/dogkeeper886/ollama37) targets **K80 / sm_37** with a polished builder/runtime split and follows newer Ollama.  
This repo keeps the **Dokploy-friendly single Dockerfile** style from `ollama-v0.3.14-cc35-dokploy`, but lifts the Ollama tag to **0.4.3+** and forces **sm_35**.

To chase newer tags (0.5.x / 0.6.x), expect to rework patches when `discover/gpu.go` or the Make/CMake layout changes.

## Structured Outputs check

After deploy:

```bash
docker exec ollama-k40c ollama -v
```

Version must be ≥ 0.4.3, then test `/api/chat` with a JSON Schema in `format` (see README).

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Build cannot find CUDA 11 | `/usr/local/cuda-11` symlink |
| `CUDA GPU is too old` | `CudaComputeMin` patch applied? |
| `nvcc fatal: Unsupported gpu architecture 'compute_35'` | Using CUDA 12 by mistake |
| Container sees 0 GPUs | Host `nvidia-modprobe -u -c=0`, driver 470, NVIDIA Container Toolkit |
| Port already in use | Stop previous `ollama-k40c-v0314` on 11434 |
