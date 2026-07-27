# Repository運用

すべての生成Blueprintで、pnpmをRepository全体のタスクランナーとして使用します。
アプリケーション固有のBuild Systemは維持し、Node.js workspaceは各scriptを、
SpringプロジェクトはRepository内のGradle Wrapperを呼び出します。

## 共通コマンド

- `pnpm dev`
- `pnpm test`
- `pnpm check`
- `pnpm build`
- `pnpm release`

PostgreSQLを使用するSpringプロジェクトでは、`pnpm e2e`も使用できます。

Node.jsとpnpmはRepository運用要件です。Springでは、アプリケーション固有要件として
JDK 17も必要です。問題調査ではGradle Wrapperを直接実行できますが、CIとAI Agentは
ルートのpnpmコマンドを使用します。

`main`のQuality成功後、semantic-releaseがConventional CommitからRelease Notes、
Git Tag、GitHub Releaseを作成します。CHANGELOGファイルを更新するCommitは作りません。
