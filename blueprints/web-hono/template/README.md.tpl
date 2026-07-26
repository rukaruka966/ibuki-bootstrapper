# __PROJECT_DISPLAY_NAME__

`__PROJECT_ID__`は、ReactフロントエンドとHono BFFで構成されるpnpm
ワークスペースです。

## 必要な環境

- Node.js 24以降
- pnpm 11以降
- PowerShell 7

## 開発環境の起動

```powershell
pnpm install
pnpm run dev
```

フロントエンドは`http://127.0.0.1:5173`、BFFは
`http://127.0.0.1:3000`で起動します。

## 検証

```powershell
pnpm run lint
pnpm run test
pnpm run typecheck
pnpm run build
pnpm run smoke
pnpm run doctor
```

## リポジトリ運用

機能開発のPull Requestは`develop`を対象にし、squash mergeで取り込みます。
`main`を対象にできるPull Requestは`develop`からのものだけで、リリース時に
merge commitで取り込みます。`main`へ直接入れる緊急経路は設けません。
`Quality`は、同一Repositoryの`develop`からのPull Requestであることも検証します。
ただし、これは個人開発での誤操作防止であり、悪意ある変更に対するsecurity
boundaryではありません。
`main`ではrequired checkのstrictを無効にしてrelease merge commit後の逆同期を
不要にし、`develop`では有効にして機能Pull Requestを最新状態で検証します。

## 開発ガイド

- AI Agent向け開発ルール: [`AGENTS.md`](AGENTS.md)
- 開発ルールの日本語版: [`docs/ja-JP/AGENTS-ja.md`](docs/ja-JP/AGENTS-ja.md)
- UI・UX設計ルール: [`DESIGN.md`](DESIGN.md)
- UI・UX設計ルールの日本語版:
  [`docs/ja-JP/DESIGN-ja.md`](docs/ja-JP/DESIGN-ja.md)
