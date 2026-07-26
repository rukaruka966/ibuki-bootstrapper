# Ibuki Bootstrapper

Ibukiは、ReactフロントエンドとHono BFFで構成される最小プロジェクトを生成する
Bootstrapperです。

生成後にローカルでlint・テスト・型検査・ビルド・疎通確認を実行します。
必要に応じて、保護された`main`・`develop`ブランチを持つPrivate GitHub
リポジトリまで自動作成できます。

Ibuki自身の変更履歴は
[GitHub Releases](https://github.com/rukaruka966/ibuki-bootstrapper/releases)
で公開します。

## 必要な環境

- Windows 11
- PowerShell 7.6以降
- Node.js 24以降
- pnpm 11以降
- Git for Windows
- `gh auth login`で認証済みのGitHub CLI

## 実行方法

`main`ブランチの最新版を実行します。標準では対話ウィザードが起動し、
構成、プロジェクト情報、生成先、GitHub Repositoryの作成有無を順番に確認します。

```powershell
irm https://raw.githubusercontent.com/rukaruka966/ibuki-bootstrapper/main/bootstrap.ps1 | iex
```

現時点で生成できる構成は`web-hono`（React + Hono）です。
React + Hono + Spring Boot、Spring Boot単独のWeb API、Android、
Windows Desktopは選択肢に表示されますが、`Coming soon`として生成せず
構成選択へ戻ります。

公開スクリプトには認証情報を含みません。Privateリポジトリを作成する場合だけ、
GitHub CLIに保存されている認証情報をGitHub CLI自身が使用します。
入力内容をsetup設定ファイルとして保存することはありません。

## ローカル開発

```powershell
pnpm install
pnpm run verify
```

GitHubを変更せず、ローカルにだけプロジェクトを生成する場合:

```powershell
pwsh ./bootstrap.ps1 `
  -Blueprint web-hono `
  -ProjectId sample-project `
  -DisplayName "Sample Project" `
  -Destination ./sample-project `
  -SkipGitHub `
  -NonInteractive `
  -Yes
```

非対話実行でも、引数は対話ウィザードと同じ共通設定へ変換・検証されます。
既存のコマンドとの互換性のため、`-Blueprint`を省略した場合は`web-hono`です。

Windows上のpnpm依存解決を安定させるため、正規化後の生成先絶対パスは
96文字以内にしてください。上限を超える場合は、ファイルを作成する前に停止し、
`C:\workspace\<project-id>`のような短い生成先を案内します。

## 生成される構成

- React・TypeScript・Viteフロントエンド
- Hono・TypeScript BFF
- 最小限のニュートラルなUI
- `AGENTS.md`と`DESIGN.md`の日本語参考版
- `/internal/health`ヘルスチェック
- RFC 7807形式の404レスポンス
- 単体テスト・型検査・ビルド・実行時スモークテスト
- Private GitHubリポジトリの作成
- `main`・`develop`ブランチの作成とRuleset設定

Rulesetでは、Pull Request、未解決スレッドの解消、`Quality`ステータスチェックを
必須とし、ブランチ削除とforce-pushを禁止します。

## IbukiのRelease

`main`の`Quality`が成功すると、semantic-releaseがConventional Commitから
次のバージョンを判定し、Git TagとGitHub Releaseを作成します。
npm packageの公開やRelease用のソースCommitは行いません。

Bootstrapperの開始時には、実行しているCommitとGitHub Releaseの対応を表示します。
`main`が最新Releaseより先に進んでいる場合は`Unreleased`、GitHub APIから情報を
取得できない場合は`unavailable`と表示し、プロジェクト生成は継続します。

Repository内の[CHANGELOG.md](CHANGELOG.md)は、変更履歴の正本である
GitHub Releasesへの案内板です。

## Coming soon・対象外

次の構成・機能は現時点では生成しません。

- PostgreSQL・Redis
- Docker
- Web: React + Hono + Spring Boot
- Web API: Spring Boot
- Android: Jetpack Compose
- Windows Desktop: Compose Multiplatform
- 認証・認可
- OpenAPI
