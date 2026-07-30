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
- Package／Task runner: pnpm

## コマンド

```powershell
pnpm dev
pnpm test
pnpm check
pnpm build
pnpm e2e
pnpm release
```

Repositoryルートのpnpmから、同梱のGradle Wrapperを呼び出します。

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
  コンテナモードで`pnpm e2e`を明示実行する。
- Secretやローカル絶対パスを記録しない。

## AIと人間の引き継ぎ

- 人間は観測結果と期待結果を伝え、受け入れ確認を行います。
- GitHub Issueを使用する場合、AI Agentは実装前に、対象範囲、対象外、受け入れ条件、
  制約と停止条件、検証計画をIssueへ追記し、実装可能な作業契約にします。
- AI Agentは実装、検証、Review、Pull Requestの証跡を担当します。
- `develop`では受け入れ状態を`Pending`にできますが、`main`へ進めるには
  `Accepted`の確認結果または証跡が必要です。

## 完了条件

- `pnpm check`と`pnpm build`が成功する。
- E2Eが存在する場合、Dockerを利用できる環境で`pnpm e2e`が成功する。
- 未定義のパスがRFC 7807 Problem Detailsを返す。
- 文書が変更後のCommandとContractに一致する。
