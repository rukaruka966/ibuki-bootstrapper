# AGENTS.md 日本語版

この文書は、ルートの[`AGENTS.md`](../../AGENTS.md)を日本語で確認するための
参考資料です。AI Agentへの正式な指示は英語版を正本とします。

## プロジェクト

- ID: `__PROJECT_ID__`
- 表示名: `__PROJECT_DISPLAY_NAME__`
- Base Package: `__BASE_PACKAGE__`
- Runtime: JDK 17
- Framework: Kotlin、Spring Boot 4.1.0
- 永続化: PostgreSQL、MyBatis Dynamic SQL、Flyway
- Build tool: Gradle Wrapper

## コマンド

```powershell
Set-Location ./systems/api-server
.\gradlew.bat check
.\gradlew.bat bootJar
.\gradlew.bat e2eTest
```

## API規約

- 内部Endpointには`/internal/**`を使用します。
- 将来の公開APIには`/api/v1/**`を使用します。
- APIエラーはRFC 7807 Problem Detailsに準拠します。

## 開発ルール

- JDK 17との互換性を維持する。
- テキストをUTF-8 BOMなし、改行をLFで保存する。
- Endpointの動作と重要な失敗経路をテストする。
- 明示的な要件なしに業務Model、Mapper、Service、Migration、fixtureを追加しない。
- Unit TestはDatabaseとDockerへ依存させず、E2EはDocker DesktopのLinux
  コンテナモードで`e2eTest`を明示実行する。
- Secretやローカル絶対パスを記録しない。

## 完了条件

- `gradlew.bat check`と`gradlew.bat bootJar`が成功する。
- E2Eが存在する場合、Dockerを利用できる環境で`gradlew.bat e2eTest`が成功する。
- 未定義のパスがRFC 7807 Problem Detailsを返す。
- 文書が変更後のCommandとContractに一致する。
