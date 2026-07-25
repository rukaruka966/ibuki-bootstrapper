# Ibuki Bootstrapper

Ibukiは、ReactフロントエンドとHono BFFで構成される最小プロジェクトを生成する
Bootstrapperです。

生成後にローカルでlint・テスト・型検査・ビルド・疎通確認を実行します。
必要に応じて、保護された`main`・`develop`ブランチを持つPrivate GitHub
リポジトリまで自動作成できます。

## 必要な環境

- Windows 11
- PowerShell 7.6以降
- Node.js 24以降
- pnpm 11以降
- Git for Windows
- `gh auth login`で認証済みのGitHub CLI

## 実行方法

`main`ブランチの最新版を実行します。

```powershell
irm https://raw.githubusercontent.com/rukaruka966/ibuki-bootstrapper/main/bootstrap.ps1 | iex
```

公開スクリプトには認証情報を含みません。Privateリポジトリを作成する場合だけ、
GitHub CLIに保存されている認証情報をGitHub CLI自身が使用します。

## ローカル開発

```powershell
pnpm install
pnpm run verify
```

GitHubを変更せず、ローカルにだけプロジェクトを生成する場合:

```powershell
pwsh ./bootstrap.ps1 `
  -ProjectId sample-project `
  -DisplayName "Sample Project" `
  -Destination ./sample-project `
  -SkipGitHub `
  -NonInteractive `
  -Yes
```

## 生成される構成

- React・TypeScript・Viteフロントエンド
- Hono・TypeScript BFF
- 最小限のニュートラルなUI
- `/internal/health`ヘルスチェック
- RFC 7807形式の404レスポンス
- 単体テスト・型検査・ビルド・実行時スモークテスト
- Private GitHubリポジトリの作成
- `main`・`develop`ブランチの作成とRuleset設定

Rulesetでは、Pull Request、未解決スレッドの解消、`Quality`ステータスチェックを
必須とし、ブランチ削除とforce-pushを禁止します。

## v0.1の対象外

次の構成は、v0.1では意図的に対象外としています。

- PostgreSQL・Redis
- Docker
- Spring Boot
- Android・Desktop
- 認証・認可
- OpenAPI
- semantic-release
