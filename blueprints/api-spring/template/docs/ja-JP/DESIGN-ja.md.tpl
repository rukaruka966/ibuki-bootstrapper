# DESIGN.md 日本語版

この文書は、ルートの[`DESIGN.md`](../../DESIGN.md)の日本語参考版です。
正式な設計ルールは英語版を正本とします。

## API設計

- Starter APIは最小かつProductに依存しない構成にする。
- Application内部のEndpointには`/internal/**`を使用する。
- 将来外部公開するAPIには`/api/v1/**`を使用する。
- ErrorはRFC 7807 Problem Detailsで返す。
- Starterでは永続化方式と認証方式を決めない。

## 運用

- `/internal/health`を高速かつ任意のInfrastructureに依存させない。
- 実行可能なSpring Boot JARを1つ生成する。
- Package済みApplicationを実HTTP Smoke testで検証する。
