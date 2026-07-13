# Intended change for Ollama discover/gpu.go (v0.4.3 lineage)

Upstream rejects GPUs below CUDA Compute Capability 5.0:

```go
var CudaComputeMin = [2]C.int{5, 0}
```

For Tesla K40 (3.5) change to:

```go
var CudaComputeMin = [2]C.int{3, 5}
```

The Dockerfile applies this with `sed` at build time (same approach as
`ollama-v0.3.14-cc35-dokploy`). If a future Ollama tag renames the symbol,
update the Dockerfile accordingly — a static git patch against upstream
main is intentionally avoided because tags move.
