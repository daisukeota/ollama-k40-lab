# Build notes — Ollama K40 Lab (sm_35)

## Why CUDA 11.4

Tesla K40 (CC 3.5) needs an older nvcc that still emits `sm_35`. CUDA 12+ drops `compute_35`.  
Host driver should stay on the **470** branch (last Kepler support).

## Relationship to ollama37 / k80-lab

| | ollama37 (K80) | this lab (K40) |
|--|----------------|----------------|
| Source | dogkeeper886/ollama37 | same, pinned tag |
| Builder image | `dogkeeper886/ollama37-builder` | same |
| CMake preset base | `CUDA 11 K80` | same preset + **arch override** |
| CUBIN | `37-real` … `86-real` | **`35-real` only** |
| Hub runtime image | `dogkeeper886/ollama37` | **do not use on K40** |
| Default pin | Hub `v2.2.3` / `latest` | `OLLAMA37_REF=v2.2.3` |

k80-lab は公開イメージを pull するラボ。こちらは **同じフォークを sm_35 向けに再ビルド**する。

## Version strings

- Git tag of the fork: `OLLAMA37_REF` (default `v2.2.3`)
- Baked `ollama -v`: `OLLAMA_VERSION` (default `2.2.3-k40`)

These are **not** upstream `ollama/ollama` `v0.x` tags. ollama37 uses its own `v2.x` lineage while selectively porting modern model support (Qwen3, Gemma 4, deepseek-r1, …).

## CMake architecture override

ollama37 runtime Dockerfile runs:

```bash
cmake --preset "CUDA 11 K80"
```

This lab runs:

```bash
cmake --preset "CUDA 11 K80" \
  -DCMAKE_CUDA_ARCHITECTURES=35-real
```

Command-line `-D` overrides the preset’s `CMAKE_CUDA_ARCHITECTURES`, so only K40 CUBIN is built (faster than the full 37–86 sweep, and matches the only GPU this compose should see).

## Artifact layout

Same as ollama37:

- Binary: `/usr/bin/ollama` → resolves libs via `../lib/ollama` → `/usr/lib/ollama`
- Runtime base: `rockylinux/rockylinux:8-minimal`
- GCC 10 `libstdc++` / `libgcc_s` copied from the builder into `/usr/lib64`

## Optional Go CC floor

If `CudaComputeMajorMin` appears in the tree, the Dockerfile rewrites it toward CC **3.5**.  
On ollama37 v2.x this is usually absent; missing CUBIN for `sm_35` is the hard failure mode when using Hub images.

## Structured Outputs

ollama37 v2.x is far past Ollama 0.5.0; JSON Schema in `/api/chat` `format` is expected to work. Verify after deploy with a small schema request (see README).

## Troubleshooting (build)

| Symptom | Check |
|---------|--------|
| `Unsupported gpu architecture 'compute_35'` | Builder somehow on CUDA 12 — must stay on ollama37-builder / CUDA 11.4 |
| Hub image on K40: load fails / wrong arch | Rebuild with this Dockerfile (`35-real`); never run `dogkeeper886/ollama37` on K40 |
| `GLIBCXX_*` not found | Runtime must copy GCC 10 libs from builder (Dockerfile already does) |
| Port already in use | Stop previous `ollama-k40c-v0314` on 11434 |
| Container sees 0 GPUs | Host `nvidia-modprobe -u -c=0`; pin `NVIDIA_VISIBLE_DEVICES=0` |
| `pull ... 412` on deepseek-r1 | Still on old v0.5.4 image — redeploy this ollama37-based build |
| PaddleOCR also on this host | Do **not** give Paddle the K40; use GPU 1 or CPU |
