# __PROJECT_DISPLAY_NAME__

KotlinとSpring Boot 4.1.0で構成された、JDK 17向けの最小Web APIです。
Base Packageは`__BASE_PACKAGE__`です。

## 必要な環境

- Windows 11
- PowerShell 7
- Node.js 24.10以降
- pnpm 11以降
- 最新のpatchを適用したJDK 17

復元初版の`17.0.1+12`は互換確認値であり、その古いpatchへの固定ではありません。

Gradleは同梱のWrapperを使用するため、別途インストールする必要はありません。

## コマンド

Ibukiはファイル生成だけを行い、以下のコマンドは実行していません。

```powershell
pnpm install --frozen-lockfile
pnpm dev
pnpm check
pnpm build
```

pnpmをRepository共通のタスクランナーとして使用し、内部で同梱のGradle Wrapperを
呼び出します。

## API

- `GET /internal/health`: `{"status":"ok"}`を返します。
- 未定義のパス: RFC 7807 Problem Details形式の404を返します。

## 構成

アプリケーションコードは
`systems/api-server/src/main/kotlin/__BASE_PACKAGE_PATH__`にあります。

`AGENTS.md`をAI Agent向け指示の正本とし、日本語参考版を
`docs/ja-JP/AGENTS-ja.md`に置きます。

Repository共通の運用方法は
[`docs/ja-JP/REPOSITORY_OPERATIONS-ja.md`](docs/ja-JP/REPOSITORY_OPERATIONS-ja.md)
を参照してください。
