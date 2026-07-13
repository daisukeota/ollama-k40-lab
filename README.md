# Ollama K40 Lab (CC 3.5 / sm_35)

NVIDIA **Tesla K40** (Compute Capability **3.5**) 向けに、Ollama **0.4.3+** を CUDA 11.4 でビルドし、Dokploy 上で動かす実験リポジトリです。

上流 Ollama は Kepler（CC 3.5/3.7）を公式サポートしていません。本リポジトリは次をベースにしています。

- [daisukeota/ollama-v0.3.14-cc35-dokploy](https://github.com/daisukeota/ollama-v0.3.14-cc35-dokploy)（実績のある K40 / CUDA 11.4 ビルド）
- [dogkeeper886/ollama37](https://github.com/dogkeeper886/ollama37)（K80=CC3.7 向けに新しい Ollama を追従する手法）

**公開イメージをそのまま K40 に載せるのではなく、`sm_35` 向けに自分でビルドする**前提です。

## ゴール

| 項目 | 内容 |
|------|------|
| GPU | Tesla K40 (`sm_35`) |
| ホストドライバ | **470 系**（Kepler 最終） |
| CUDA（ビルド） | **11.4** |
| Ollama | 既定 **v0.4.3**（Structured Outputs 利用のため 0.4.3+） |
| デプロイ | Dokploy Compose |

OpenFoodFlow などから `/api/chat` の **`format` に JSON Schema** を渡す Structured Outputs を使うには、Ollama **≥ 0.4.3** が必要です。

## クイックスタート（Dokploy）

1. 本リポジトリを Dokploy の Compose サービスとして追加
2. **Compose Path:** `./docker-compose.yml`
3. Build を有効化して Deploy（**初回ビルドは長時間** — 30〜90 分程度を見込む）
4. 確認:

```bash
docker exec ollama-k40c ollama -v
docker exec ollama-k40c ollama pull qwen2.5:7b
curl -s http://127.0.0.1:11434/api/tags | head -c 300
```

Structured Outputs の簡単な確認:

```bash
curl -s http://127.0.0.1:11434/api/chat -d '{
  "model": "qwen2.5:7b",
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

バージョンを上げる場合:

```bash
docker compose build --build-arg OLLAMA_VERSION=v0.5.4
```

> 新しいタグほど llama.cpp / CMake 周りが変わり、パッチが効かなくなることがあります。まずは **v0.4.3** で通すことを推奨します。

## ビルドでやっていること

1. `nvidia/cuda:11.4.3-devel-ubuntu20.04` 上で Go / CMake / gcc-11 を用意
2. 上流 `ollama/ollama` を `OLLAMA_VERSION`（既定 `v0.4.3`）で checkout
3. `discover/gpu.go` の `CudaComputeMin` を **`{3, 5}`** に変更（CC 3.5 未満のみ除外）
4. `/usr/local/cuda-11` シンボリックリンクを作成（Makefile が CUDA 11 を検出するため）
5. `CUDA_ARCHITECTURES=35` で `make`（CUDA 12 / ROCm はスキップ）
6. `go build` して slim runtime イメージへ成果物をコピー

詳細は [docs/build-notes.md](docs/build-notes.md)。

## OpenFoodFlow との接続

OpenFoodFlow staging はホスト公開の `11434` を `host.docker.internal:11434` 経由で呼びます。

- 本 Compose を **既存の `ollama-k40c-v0314` の置き換え**として使う場合、ポート `11434` の衝突に注意
- モデルボリュームを引き継ぐ場合は `docker-compose.yml` の volume 名を合わせてください

## 制限・リスク

- 上流非サポート構成です。モデルやバージョンによってビルド／実行が壊れることがあります
- K40 12GB では 7B 級（Q4）が現実的な上限に近いです
- Kepler 向けドライバ 470 と新しいカーネルの相性に注意してください
- [ollama37](https://github.com/dogkeeper886/ollama37) の Docker Hub イメージは **K80 (sm_37) 向け**であり、K40 では使えません

## ライセンス

Ollama 本体は MIT。本リポジトリの Dockerfile / ドキュメントも MIT とします。

## 関連リンク

- [ollama/ollama](https://github.com/ollama/ollama)
- [daisukeota/ollama-v0.3.14-cc35-dokploy](https://github.com/daisukeota/ollama-v0.3.14-cc35-dokploy)
- [dogkeeper886/ollama37](https://github.com/dogkeeper886/ollama37)
- [OpenFoodFlow ollama-structured-outputs](https://github.com/daisukeota/openfoodflow/blob/main/docs/operations/ollama-structured-outputs.md)（プライベートの場合はローカル docs を参照）
