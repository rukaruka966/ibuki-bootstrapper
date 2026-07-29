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

## 生成ファイルの更新

プロジェクトルートからIbuki Updaterを実行すると、ファイルを変更せずに3-way比較した
Update Bundleを作成できます。

```powershell
irm https://raw.githubusercontent.com/rukaruka966/ibuki-bootstrapper/main/update.ps1 | iex
```

Bundleには`plan.json`、Codexへ渡せる`prompt.md`、baseとtargetのartifact、text
diffが含まれます。意味判断が必要な競合は、接続中のAI開発Agentへpromptを渡して
解消します。ローカルdiffにはSecretが含まれる可能性があるため、共有前に確認して
ください。

`delete-candidate`は人間の明示承認なしに削除しません。Apply Modeは任意であり、
cleanな機能ブランチ上の競合がないPlanだけを受け付けます。依存関係の導入、
プロジェクトコマンド、Commit、push、Pull Request作成は自動実行しません。

## Issueの受け付け

人間は観測結果と期待結果を伝えます。GitHub Issueを使用する場合、AI Agentは
実装前に、対象範囲、対象外、観測可能な受け入れ条件、依頼固有の制約と停止条件、
検証計画をIssueへ追記し、実装可能な作業契約にします。

## Pull Requestの引き継ぎ

Pull Request templateは、AIによる実装と人間による受け入れ確認の引き継ぎ契約として
使用します。AIの実装、検証、Reviewが完了していれば、`develop`向けPull Requestの
人間による受け入れ状態は`Pending`のままでも構いません。ただし、人間が確認する操作と
期待結果を明記します。`develop`から`main`へのPull Requestでは、受け入れ状態を
`Accepted`とし、確認結果または証跡を記録します。

採用した判断、依頼との差異、検証証跡、Review結果、発生した停止条件を記録してください。
次の判断に使われない形式的なChecklistは増やしません。

`main`のQuality成功後、semantic-releaseがConventional CommitからRelease Notes、
Git Tag、GitHub Releaseを作成します。CHANGELOGファイルを更新するCommitは作りません。
