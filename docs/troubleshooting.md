# Host / runtime troubleshooting — Ollama K40 Lab

Patterns adapted from [dogkeeper886/ollama37 docker README](https://github.com/dogkeeper886/ollama37/blob/main/docker/README.md)
and the k80-lab workflow, specialized for **Tesla K40 (sm_35)** on driver **470**.

## sapphire デュアル GPU（推奨割り当て）

| GPU | 例 | 用途 |
|-----|-----|------|
| **0** | Tesla K40c 12GB | **本リポジトリの Ollama**（`NVIDIA_VISIBLE_DEVICES=0`） |
| **1** | GeForce ~2GB | OpenFoodFlow `paddle-ocr` など（別 Compose） |

`NVIDIA_VISIBLE_DEVICES=all` のままだと、Ollama が GeForce を選んだり、Paddle が K40 を掴んで **CUDA 非対応で CPU フォールバック**したりします。

## GPU が見えない / モデルが VRAM を使わない

### 1. コンテナから nvidia-smi

```bash
docker exec ollama-k40c nvidia-smi
```

K40 だけ見えること（GeForce が混ざらないこと）を確認。

### 2. nvidia-uvm デバイス欠落（k80-lab と同症状）

**症状:** コンテナ内で `nvidia-smi` は動くが、Ollama が **0 GPUs** / 推論が CPU。

**原因:** ホストで `/dev/nvidia-uvm` が無い。`nvidia-smi` は不要だが CUDA アプリは必要。

**ホストで:**

```bash
nvidia-modprobe -u -c=0
ls -l /dev/nvidia-uvm*
docker restart ollama-k40c
```

ログ例:

```text
Nvidia GPU detected ... Tesla K40c ... vram=11441 MiB
```

### 3. ドライバと CUDA

| 項目 | 値 |
|------|-----|
| ホストドライバ | **470.x**（Kepler 最終） |
| ビルド CUDA | **11.4** |
| CUBIN | **sm_35 のみ** |

ドライバを 525+ に上げると **K40 が消えます**。上げないでください。

### 4. 推論中に VRAM が増えない

```bash
# 別ターミナルで監視
watch -n1 nvidia-smi

docker exec ollama-k40c ollama run deepseek-r1 "hello"
docker exec ollama-k40c ollama ps
docker logs ollama-k40c 2>&1 | grep -iE 'gpu|cuda|vram|layer'
```

CPU フォールバック時は GPU Memory がほぼ増えません。

### 5. ポート衝突

```bash
sudo ss -lptn 'sport = :11434'
# 旧 ollama-k40c-v0314 を止めてから本 Compose を上げる
```

### 6. `pull model manifest: 412`（newer version of Ollama）

**症状:**

```text
Error: pull model manifest: 412:
The model you are attempting to pull requires a newer version of Ollama.
```

**原因:** コンテナが古いバイナリ（例: 上流 Ollama v0.5.4）のまま。`deepseek-r1`（latest）は Qwen3 系で、ollama37 世代のサーバが必要。

**対処:**

```bash
docker exec ollama-k40c ollama -v
# 期待例: 2.2.3-k40
# まだ 0.5.x なら本リポジトリの Dockerfile で再ビルド / 再デプロイ
```

ビルド待ちの一時回避（Qwen2.5 蒸留）:

```bash
docker exec ollama-k40c ollama pull deepseek-r1:7b
```

### 7. Hub の `dogkeeper886/ollama37` を K40 に載せた

**症状:** モデルロード失敗、CUBIN / arch 不一致、GPU フォールバック。

**原因:** 公開イメージは `sm_37` 起点で **`sm_35` を含まない**。

**対処:** 必ず本リポジトリの Compose で `35-real` ビルドした `ollama-k40-lab:local` を使う。

## デプロイ後の確認コマンド

```bash
docker exec ollama-k40c ollama -v
docker exec ollama-k40c nvidia-smi
docker exec ollama-k40c ollama pull deepseek-r1
docker exec ollama-k40c ollama run deepseek-r1 "1+1は？"
curl -s http://127.0.0.1:11434/api/tags | head -c 300
```

## OpenFoodFlow との共存

- OpenFoodFlow は `OLLAMA_BASE_URL=http://host.docker.internal:11434`
- PaddleOCR は **K40 では動かない**（現行 wheel が sm_35 / ドライバ 470×cu118 非対応）
- Paddle は **CPU** か、対応するなら **GPU 1 + CUDA 11.2 系 wheel**（openfoodflow 側 docs 参照）

## デバッグ環境変数

`docker-compose.yml` で一時的に:

```yaml
- OLLAMA_DEBUG=1
- GGML_CUDA_DEBUG=1
```
