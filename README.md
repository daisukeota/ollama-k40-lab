# Ollama K40 Lab (CC 3.5 / sm_35)

NVIDIA **Tesla K40** (Compute Capability **3.5**) 向けに、[dogkeeper886/ollama37](https://github.com/dogkeeper886/ollama37)（K80 / sm_37 向け Kepler フォーク）を **`sm_35` CUBIN** でビルドし、Dokploy 上で動かす実験リポジトリです。

上流 Ollama も公開 `dogkeeper886/ollama37` イメージも、K40 ではそのまま使えません。

- 上流: Kepler（CC 3.5/3.7）非サポート
- Hub の ollama37: **sm_37 起点**（`sm_35` なし）→ K40 不可
- 本リポジトリ: ollama37 **v2.2.3** ソース + `CMAKE_CUDA_ARCHITECTURES=35-real`

## ゴール

| 項目 | 内容 |
|------|------|
| GPU | Tesla K40 (`sm_35`) |
| ホストドライバ | **470 系**（Kepler 最終） |
| CUDA（ビルド） | **11.4**（`dogkeeper886/ollama37-builder`） |
| Ollama 系 | **ollama37 v2.2.3** ベース（`ollama -v` → `2.2.3-k40`） |
| デプロイ | Dokploy Compose |

Qwen3 系（`deepseek-r1:latest` = DeepSeek-R1-0528-Qwen3-8B）や Structured Outputs など、ollama37 が追従している世代の機能を K40 で使うことが目的です。

## クイックスタート（Dokploy）

1. 本リポジトリを Dokploy の Compose サービスとして追加
2. **Compose Path:** `./docker-compose.yml`
3. Build を有効化して Deploy（**初回は長い** — builder イメージ取得 + CUDA コンパイルで数十分〜）
4. 確認:

```bash
docker exec ollama-k40c ollama -v
docker exec ollama-k40c nvidia-smi
docker exec ollama-k40c ollama pull deepseek-r1
curl -s http://127.0.0.1:11434/api/tags | head -c 300
```

ビルド待ちの一時回避（旧蒸留・Qwen2.5 系。現行イメージでは不要なはず）:

```bash
docker exec ollama-k40c ollama pull deepseek-r1:7b
```

Structured Outputs の簡単な確認（モデルは pull 済みのものに合わせて変更）:

```bash
curl -s http://127.0.0.1:11434/api/chat -d '{
  "model": "deepseek-r1",
  "stream": false,
  "format": {
    "type": "object",
    "properties": {
      "name": { "type": "string" },
      "ok": { "type": "boolean" }
    },
    "required": ["name", "ok"]
  },
  "messages": [
    { "role": "user", "content": "Say hello as JSON with name and ok=true" }
  ]
}'
```

## ローカル / サーバでのビルド

```bash
git clone https://github.com/daisukeota/ollama-k40-lab.git
cd ollama-k40-lab
docker compose build
docker compose up -d
```

ollama37 のタグを上げる場合:

```bash
docker compose build --build-arg OLLAMA37_REF=v2.2.3 --build-arg OLLAMA_VERSION=2.2.3-k40
```

> Hub の `dogkeeper886/ollama37` を pull して K40 で動かさないでください。必ず本 Dockerfile で `35-real` をビルドします。

## ビルドでやっていること

1. `dogkeeper886/ollama37-builder`（Rocky 8 / CUDA 11.4 / GCC 10 / CMake 4 / Go）を利用
2. `dogkeeper886/ollama37` を `OLLAMA37_REF`（既定 `v2.2.3`）で shallow clone
3. CMake preset `CUDA 11 K80` のツールチェーンを使い、**`-DCMAKE_CUDA_ARCHITECTURES=35-real`** で上書き
4. `cmake --build` / `--install` で `dist/lib/ollama` を生成
5. `go build` して `2.2.3-k40` をバージョン文字列に焼き込み
6. slim な Rocky 8 minimal ランタイムへバイナリ・GGML/CUDA・libstdc++ をコピー

詳細は [docs/build-notes.md](docs/build-notes.md)。

## OpenFoodFlow との接続

OpenFoodFlow staging はホスト公開の `11434` を `host.docker.internal:11434` 経由で呼びます。

- 本 Compose を **既存の `ollama-k40c-v0314` の置き換え**として使う場合、ポート `11434` の衝突に注意
- モデルボリュームを引き継ぐ場合は `docker-compose.yml` の volume 名を合わせてください
- **GPU 0（K40）を本サービスが専有**する想定。PaddleOCR などには GPU 1 か CPU を割り当てる（[docs/troubleshooting.md](docs/troubleshooting.md)）

## トラブルシュート

詳細は [docs/troubleshooting.md](docs/troubleshooting.md)（`nvidia-uvm`、VRAM が増えない、デュアル GPU、412）。

```bash
# ホスト（CUDA に必須）
nvidia-modprobe -u -c=0

docker exec ollama-k40c nvidia-smi
docker exec ollama-k40c ollama ps
```

## 制限・リスク

- 上流非サポート構成です。モデルや ollama37 タグによってビルド／実行が壊れることがあります
- K40 12GB では 7–8B 級（Q4）が現実的な上限に近いです（`deepseek-r1:latest` ~5.2GB は狙える）
- Kepler 向けドライバ 470 と新しいカーネルの相性に注意してください
- [ollama37](https://github.com/dogkeeper886/ollama37) の Docker Hub イメージは **K80 (sm_37) 向け**であり、K40 では使えません

## ライセンス

Ollama / ollama37 本体は MIT。本リポジトリの Dockerfile / ドキュメントも MIT とします。

## 関連リンク

- [ollama/ollama](https://github.com/ollama/ollama)
- [dogkeeper886/ollama37](https://github.com/dogkeeper886/ollama37)
- [dogkeeper886/ollama-k80-lab](https://github.com/dogkeeper886/ollama-k80-lab)
- [daisukeota/ollama-v0.3.14-cc35-dokploy](https://github.com/daisukeota/ollama-v0.3.14-cc35-dokploy)
- [OpenFoodFlow ollama-structured-outputs](https://github.com/daisukeota/openfoodflow/blob/main/docs/operations/ollama-structured-outputs.md)（プライベートの場合はローカル docs を参照）
