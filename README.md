# Ibuki Bootstrapper

Ibukiは、React + HonoまたはKotlin + Spring Bootで構成される最小プロジェクトを
安全に生成するBootstrapperです。

Ibukiの完了条件は、Blueprintで宣言されたファイルを欠落・上書き・文字化けなく
生成することです。生成先の依存関係導入、lint、テスト、ビルド、起動は行いません。
必要な環境と推奨コマンドは確認画面に表示し、生成後のプロジェクトとそのCIが
実行責任を持ちます。
必要に応じて、保護された`main`・`develop`ブランチを持つPrivate GitHub
リポジトリまで自動作成できます。

Ibuki自身の変更履歴は
[GitHub Releases](https://github.com/rukaruka966/ibuki-bootstrapper/releases)
で公開します。

## 必要な環境

Ibukiでローカルファイルだけを生成する場合:

- Windows 11
- PowerShell 7.6以降

GitHub Repositoryも作成する場合だけ、次を追加で使用します。

- Git for Windows
- `gh auth login`で認証済みのGitHub CLI
- `git config user.name`と`git config user.email`の設定

生成後のプロジェクトを開発する場合は、選択したBlueprintに応じて次を使用します。
これらはIbukiによるファイル生成の前提ではありません。

| Blueprint | 生成後の開発環境 |
| --- | --- |
| `web-hono` | Node.js 24.10.0以降、pnpm 11以降 |
| `api-spring` | `java`と`javac`を含むJDK 17 |
| `api-spring-postgres` | JDK 17。E2Eを明示実行する場合だけDocker Desktop |

`api-spring`ではNode.jsとpnpmを生成要件にしません。JDK 17.0.1+12でも互換確認を
行いますが、通常は最新のセキュリティ更新が適用されたJDK 17を使用してください。

## 実行方法

`main`ブランチの最新版を実行します。標準では対話ウィザードが起動し、
構成、プロジェクト情報、生成先、GitHub Repositoryの作成有無を順番に確認します。

```powershell
irm https://raw.githubusercontent.com/rukaruka966/ibuki-bootstrapper/main/bootstrap.ps1 | iex
```

現時点で生成できる構成は、`web-hono`、`api-spring`、
`api-spring-postgres`です。React + Hono + Spring Boot、Android、
Windows Desktopは選択肢に表示されますが、
`Coming soon`として生成せず構成選択へ戻ります。

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

Spring Boot Web APIを生成する場合:

```powershell
pwsh ./bootstrap.ps1 `
  -Blueprint api-spring `
  -ProjectId sample-api `
  -DisplayName "Sample API" `
  -BasePackage net.rukaruka966.sampleapi `
  -Destination ./sample-api `
  -SkipGitHub `
  -NonInteractive `
  -Yes
```

`-BasePackage`を省略した場合はProject IDからハイフンを除去し、
`net.rukaruka966.<project-id>`へ正規化します。たとえば`media-node`は
`net.rukaruka966.medianode`になります。正規化後の末尾segmentがJava／Kotlinの
予約語になる場合は`app`を付加します。たとえば`class`は
`net.rukaruka966.classapp`になります。
Project IDと明示入力するBase Packageの各segmentには、`con`、`com1`、
`lpt1`などのWindows device名を使用できません。

PostgreSQL・MyBatis・Flyway構成では`-Blueprint api-spring-postgres`を指定します。

非対話実行でも、引数は対話ウィザードと同じ共通設定へ変換・検証されます。
既存のコマンドとの互換性のため、`-Blueprint`を省略した場合は`web-hono`です。

Windows上の各種開発ツールとの互換性を保つため、正規化後の生成先絶対パスは
96文字以内にしてください。上限を超える場合は、ファイルを作成する前に停止し、
`C:\workspace\<project-id>`のような短い生成先を案内します。

## 生成される構成

`web-hono`:

- React・TypeScript・Viteフロントエンド
- Hono・TypeScript BFF
- 最小限のニュートラルなUI
- `AGENTS.md`と`DESIGN.md`の日本語参考版
- `/internal/health`ヘルスチェック
- RFC 7807形式の404レスポンス
- 単体テスト・型検査・ビルドを実行するプロジェクト側のコマンドとCI
- Private GitHubリポジトリの作成
- `main`・`develop`ブランチの作成とRuleset設定

`api-spring`:

- Kotlin・Spring Boot 4.1.0 Web API
- Gradle Kotlin DSL・Gradle Wrapper・Java Toolchain 17
- `systems/api-server`単独でのtest・executable jar生成
- `/internal/health`ヘルスチェック
- `application/problem+json`形式の404レスポンス
- 単体テスト・executable jar生成を実行するプロジェクト側のコマンドとCI
- JDK 17を使用するGitHub Actions `Quality`
- `AGENTS.md`・`DESIGN.md`と日本語参考版
- `project.config.yaml`への構成・port・Bootstrapper version記録

`api-spring-postgres`:

- `api-spring`と同じ中立的なWeb API基盤
- PostgreSQL JDBC Driver、MyBatis Spring Boot Starter、MyBatis Dynamic SQL
- Flyway CoreとPostgreSQL対応module
- DatabaseやDockerへ依存しないUnit Test
- `check`へ接続しない明示実行の`e2eTest` SourceSetとTestcontainers依存関係
- 業務Model、Mapper、Service、Migration、fixtureを含まない空Scaffold
- `DB_URL`、`DB_USERNAME`、`DB_PASSWORD`による接続設定

Node.js、pnpm、JDKは生成されたプロジェクトを開発するための要件であり、Ibukiが
ローカルファイルだけを生成する際の前提ではありません。GitHub Repositoryも作成する
場合に限り、GitとGitHub CLIの利用可否・認証状態を事前確認します。

Rulesetでは、Pull Request、未解決スレッドの解消、`Quality`ステータスチェックを
必須とし、ブランチ削除とforce-pushを禁止します。

機能ブランチから`develop`へはsquash merge、`develop`から`main`へはmerge
commitを使用します。`main`を対象にできるPull Requestは`develop`からのものだけ
です。Repository全体では両方式を有効にし、各Rulesetで使用方式を限定します。
`main`へ直接入れる緊急経路は設けません。

`main`と`develop`では`Quality`を必須とします。`Quality`は`main`向けPull
Requestが同一Repositoryの`develop`から来たことも検証します。ただしPull Requestは
Workflow自体を変更できるため、この検証は個人開発での誤操作防止であり、悪意ある
変更に対するsecurity boundaryではありません。

`main`のstatus checkはstrictを無効にし、release merge commit後に`main`を
`develop`へ逆同期する作業を不要にします。`develop`ではstrictを有効にし、機能Pull
Requestを常に最新の`develop`を基準として検証します。

## 生成後の不具合報告

生成直後かつ未変更のプロジェクトで、依存関係の導入、lint、テスト、ビルド、起動、
または生成先CIに問題がある場合は、使用したIbukiのRelease／Tag、Commit ID、
Blueprint ID、実行コマンドとエラー内容を添えてIbukiへIssueを作成してください。
テンプレートを変更した後の問題や、追加した業務機能に起因する問題は、生成先
プロジェクト側で扱います。

## IbukiのRelease

`main`の`Quality`が成功すると、semantic-releaseがConventional Commitから
次のバージョンを判定し、Git TagとGitHub Releaseを作成します。
npm packageの公開やRelease用のソースCommitは行いません。

Bootstrapperの開始時には、実行しているCommitとGitHub Releaseの対応を表示します。
`main`が最新Releaseより先に進んでいる場合は`Unreleased`と表示します。Release情報
だけを取得できない場合は`unavailable`と表示して生成を継続します。ただしremote実行
で`main`のCommit自体を解決できない場合は、Manifestとassetを同一Commitから取得する
保証ができないため、ファイル生成前に停止します。

Repository内の[CHANGELOG.md](CHANGELOG.md)は、変更履歴の正本である
GitHub Releasesへの案内板です。

## Coming soon・対象外

次の構成・機能は現時点では生成しません。

- Redis
- Docker／Composeによるアプリ実行環境
- Web: React + Hono + Spring Boot
- Android: Jetpack Compose
- Windows Desktop: Compose Multiplatform
- 認証・認可
- OpenAPI
