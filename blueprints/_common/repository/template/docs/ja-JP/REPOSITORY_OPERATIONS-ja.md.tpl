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

## ignore fileの所有境界

ルート`.gitignore`は、pnpm依存物、ローカル環境変数、ログ、IDE状態、OS metadata
というRepository共通規則だけを所有します。独立してBuildできる各systemは、
Build成果物の規則をnested `.gitignore`で所有します。たとえば
`systems/api-server/.gitignore`はGradle、Kotlin、JVMの成果物を、Node.js systemは
`dist`、coverage、TypeScript build metadataを管理します。

ルートで`build`、`bin`、`dist`などを広く無視しないでください。別systemの正規資産を
隠す可能性があります。`.gitignore`は誤Commitを減らすものであり、
security boundaryではありません。SecretはRepository外で管理し、Commit前に
staging内容を確認してください。

`main`のQuality成功後、semantic-releaseがConventional CommitからRelease Notes、
Git Tag、GitHub Releaseを作成します。CHANGELOGファイルを更新するCommitは作りません。
