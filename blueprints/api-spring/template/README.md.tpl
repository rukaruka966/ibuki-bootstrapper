# __PROJECT_DISPLAY_NAME__

KotlinとSpring Boot 4.1.0で構成された、JDK 17向けの最小Web APIです。

## 必要な環境

- Windows 11
- PowerShell 7
- 最新のpatchを適用したJDK 17

復元初版の`17.0.1+12`は互換確認値であり、その古いpatchへの固定ではありません。

Gradleは同梱のWrapperを使用するため、別途インストールする必要はありません。

## コマンド

```powershell
Set-Location ./systems/api-server
.\gradlew.bat bootRun
.\gradlew.bat check
.\gradlew.bat bootJar
pwsh -NoProfile -File ./scripts/smoke.ps1
```

## API

- `GET /internal/health`: `{"status":"ok"}`を返します。
- 未定義のパス: RFC 7807 Problem Details形式の404を返します。

## 構成

アプリケーションコードは
`systems/api-server/src/main/kotlin/com/example/application`にあります。
生成されるpackage名は、ハイフンを含むProject IDでも壊れない固定の中立名です。

`AGENTS.md`をAI Agent向け指示の正本とし、日本語参考版を
`docs/ja-JP/AGENTS-ja.md`に置きます。
