# Intended change for Ollama discover/gpu.go

## v0.5.x+ (default: v0.5.4)

Upstream rejects GPUs below CUDA Compute Capability 5.0:

```go
var (
	CudaComputeMajorMin = "5"
	CudaComputeMinorMin = "0"
)
```

For Tesla K40 (3.5) change to `"3"` / `"5"`. The Dockerfile applies this with
`sed` and also passes Go ldflags:

```text
-X=github.com/ollama/ollama/discover.CudaComputeMajorMin=3
-X=github.com/ollama/ollama/discover.CudaComputeMinorMin=5
```

## v0.4.x lineage (fallback)

```go
var CudaComputeMin = [2]C.int{5, 0}
```

→ `{3, 5}`. Dockerfile still has a sed branch for this form.

A static git patch against upstream main is intentionally avoided because tags move.
