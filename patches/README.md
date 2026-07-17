# Patches / deltas vs ollama37 (K80)

This lab does **not** vendor a static git patch against upstream Ollama.
It builds [dogkeeper886/ollama37](https://github.com/dogkeeper886/ollama37) and changes only what K40 needs.

## CUDA architecture (required)

ollama37’s `CUDA 11 K80` preset compiles:

```text
37-real;50-real;52-real;60-real;61-real;70-real;75-real;80-real;86-real
```

The Dockerfile keeps that preset’s toolchain but overrides:

```text
-DCMAKE_CUDA_ARCHITECTURES=35-real
```

so the image contains native CUBIN for Tesla K40 (`sm_35`) only.

**Do not** run `dogkeeper886/ollama37` from Docker Hub on a K40 — those binaries have no `sm_35` CUBIN.

## Go CC floor (optional / legacy)

Older Ollama trees exposed:

```go
var (
	CudaComputeMajorMin = "5"
	CudaComputeMinorMin = "0"
)
```

The Dockerfile greps for `CudaComputeMajorMin` and, if present, rewrites major/minor toward **3.5**.
On ollama37 v2.x this symbol is typically absent; CUBIN match is what matters.
