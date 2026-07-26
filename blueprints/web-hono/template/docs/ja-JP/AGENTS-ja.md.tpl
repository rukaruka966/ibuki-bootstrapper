# AGENTS.md 日本語版

この文書は、ルートの[`AGENTS.md`](../../AGENTS.md)を日本語で確認するための
参考資料です。AI Agentへの正式な指示は、ルートの英語版を正本とします。

## プロジェクト

- ID: `__PROJECT_ID__`
- 表示名: `__PROJECT_DISPLAY_NAME__`
- ホスト環境: Windows 11、PowerShell 7
- パッケージマネージャー: pnpm

## システム構成

- `systems/web-frontend`: React、TypeScript、Vite
- `systems/api-bff`: Hono、TypeScript

単独で起動・ビルド・配布できる単位は、`systems/`直下へ配置します。

## コマンド

品質確認と開発用コマンドは、リポジトリルートからpnpm経由で実行します。

```powershell
pnpm run dev
pnpm run lint
pnpm run test
pnpm run typecheck
pnpm run build
pnpm run smoke
pnpm run doctor
```

## API規約

- ブラウザからBFFへのエンドポイントには`/internal/**`を使用します。
- 将来外部へ公開するAPIには`/api/v1/**`を使用します。
- APIエラーはRFC 7807 Problem Detailsに準拠します。

## Git運用

- デフォルトブランチは`main`です。
- 通常の機能開発は`develop`から分岐し、`develop`へマージします。
- 機能Pull Requestはsquash mergeで`develop`へ取り込みます。
- `main`を対象にできるPull Requestは`develop`からのものだけです。
- リリースPull Requestはmerge commitで`develop`から`main`へ取り込みます。
- `main`へ直接入れる緊急経路は設けません。
- Bootstrap完了後、`main`と`develop`への直接pushは禁止します。
- Pull RequestにはCI成功と未解決レビュー会話の解消が必要です。
- 両方の保護ブランチで`Quality`を必須とします。リリース元の検証は誤操作を
  防ぎますが、Pull RequestがWorkflowを変更できるためsecurity boundaryでは
  ありません。
- `main`ではrequired checkのstrictを無効にし、release merge commit後の
  `develop`への逆同期を不要にします。`develop`ではstrictを有効にし、機能Pull
  Requestを常に最新の`develop`を基準として検証します。

Conventional Commitはスコープなしで記述します。

```text
feat: add user search

変更理由と変更内容を説明する。
```

## 安全性

破壊的なファイル操作、データ移行、互換性変更、Secretの公開、Repository保護の
弱体化を行う前には、明示的な確認を求めます。

## 完了条件

該当する以下の条件をすべて満たしたとき、変更は完了です。

- 依頼された動作を、無関係な変更を含めず実装している。
- 変更した動作と重要な失敗経路をテストしている。
- リポジトリルートで`pnpm run lint`、`pnpm run test`、
  `pnpm run typecheck`、`pnpm run build`が成功する。
- 実行時統合またはAPI動作を変更した場合、`pnpm run smoke`が成功する。
- 依存関係、コマンド、環境要件を変更した場合、`pnpm run doctor`が成功する。
- コマンド、契約、ワークフローを変更した場合、文書と例を更新している。
- Secret、ローカル認証情報、ビルド成果物、一時ファイルを追跡していない。
- 破壊的操作、永続データ変更、互換性破壊、Repository保護の弱体化について、
  人間の明示的な承認を得ている。
- マージ前にPull RequestのCIが成功し、すべてのレビュー会話が解決している。
