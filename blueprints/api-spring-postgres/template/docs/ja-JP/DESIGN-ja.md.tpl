# DESIGN.md 日本語版

この文書は、ルートの[`DESIGN.md`](../../DESIGN.md)の日本語参考版です。
正式な設計ルールは英語版を正本とします。

## API設計

- Starter APIは最小かつProductに依存しない構成にする。
- Application内部のEndpointには`/internal/**`を使用する。
- 将来外部公開するAPIには`/api/v1/**`を使用する。
- ErrorはRFC 7807 Problem Detailsで返す。
- PostgreSQLをMyBatisから利用し、Schema migrationをFlywayで管理する。
- 架空の業務Model、Mapper、Service、Migration、fixtureを追加しない。

## 運用

- `/internal/health`を高速かつ任意のInfrastructureに依存させない。
- 実行可能なSpring Boot JARを1つ生成する。
- Unit TestはDatabaseとDockerへ依存させない。
- `e2eTest`は明示実行し、`check`へ接続しない。
- Repositoryの操作窓口にはルートpnpmを使用し、SpringのBuild Systemには
  Gradle Wrapperを維持する。
