# __PROJECT_DISPLAY_NAME__

Kotlin、Spring Boot 4.1.0、PostgreSQL、MyBatis、Flywayで構成された
JDK 17向けWeb API scaffoldです。
Base Packageは`__BASE_PACKAGE__`です。

## 必要な環境

- Windows 11
- PowerShell 7
- 最新のpatchを適用したJDK 17

復元初版の`17.0.1+12`は互換確認値であり、その古いpatchへの固定ではありません。

Gradleは同梱のWrapperを使用するため、別途インストールする必要はありません。

## コマンド

Ibukiはファイル生成だけを行い、以下のコマンドは実行していません。

```powershell
Set-Location ./systems/api-server
.\gradlew.bat bootRun
.\gradlew.bat check
.\gradlew.bat bootJar
.\gradlew.bat e2eTest
```

## API

- `GET /internal/health`: `{"status":"ok"}`を返します。
- 未定義のパス: RFC 7807 Problem Details形式の404を返します。

## Database

接続情報は`DB_URL`、`DB_USERNAME`、`DB_PASSWORD`で指定します。Secretや実環境の
値はRepositoryへ保存しません。Migrationは`src/main/resources/db/migration`へ、
業務Model、Mapper、Serviceは要件が確定してから追加してください。

`check`はDatabaseやDockerを使わないUnit Testだけを実行します。`e2eTest`は
Docker DesktopのLinuxコンテナモードを用意したWindows 11環境で明示実行します。
初期状態の`e2eTest`はテスト未配置のため`NO-SOURCE`となり、PostgreSQL接続を
実証したことにはなりません。

## 構成

アプリケーションコードは
`systems/api-server/src/main/kotlin/__BASE_PACKAGE_PATH__`にあります。

`AGENTS.md`をAI Agent向け指示の正本とし、日本語参考版を
`docs/ja-JP/AGENTS-ja.md`に置きます。
