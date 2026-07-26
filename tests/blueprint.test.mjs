import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const blueprintRoot = path.join(repositoryRoot, "blueprints", "web-hono");
const manifestPath = path.join(blueprintRoot, "manifest.json");

async function readManifest() {
  return JSON.parse(await readFile(manifestPath, "utf8"));
}

test("manifest targets are unique and safe", async () => {
  const manifest = await readManifest();
  const targets = new Set();

  for (const file of manifest.files) {
    assert.equal(path.isAbsolute(file.target), false);
    assert.equal(file.target.includes(".."), false);
    assert.equal(targets.has(file.target), false, `duplicate: ${file.target}`);
    targets.add(file.target);
  }
});

test("every manifest source exists and uses LF", async () => {
  const manifest = await readManifest();

  for (const file of manifest.files) {
    const sourcePath = path.join(blueprintRoot, file.source);
    assert.equal((await stat(sourcePath)).isFile(), true);

    const content = await readFile(sourcePath, "utf8");
    assert.equal(content.includes("\r\n"), false, `CRLF: ${file.source}`);
  }
});

test("root and generated pull request policies stay identical", async () => {
  const rootPolicy = await readFile(
    path.join(repositoryRoot, "scripts", "check-pr-branch-policy.mjs"),
    "utf8",
  );
  const generatedPolicy = await readFile(
    path.join(
      blueprintRoot,
      "template",
      "scripts",
      "check-pr-branch-policy.mjs.tpl",
    ),
    "utf8",
  );

  assert.equal(generatedPolicy, rootPolicy);
});

test("template files use only supported tokens", async () => {
  const manifest = await readManifest();
  const supportedTokens = new Set([
    "__BOOTSTRAPPER_VERSION__",
    "__PROJECT_ID__",
    "__PROJECT_DISPLAY_NAME__",
    "__PROJECT_DISPLAY_NAME_HTML__",
    "__PROJECT_DISPLAY_NAME_JSON__",
    "__PROJECT_DISPLAY_NAME_YAML__",
  ]);

  for (const file of manifest.files) {
    const sourcePath = path.join(blueprintRoot, file.source);
    const content = await readFile(sourcePath, "utf8");
    const tokens = content.match(/__[A-Z0-9_]+__/g) ?? [];

    for (const token of tokens) {
      assert.equal(
        supportedTokens.has(token),
        true,
        `unsupported token ${token} in ${file.source}`,
      );
    }

    if (!file.template) {
      assert.equal(tokens.length, 0, `tokens in static file: ${file.source}`);
    }
  }
});

test("blueprint dependencies are pinned", async () => {
  const packageFiles = [
    "template/package.json.tpl",
    "template/systems/web-frontend/package.json.tpl",
    "template/systems/api-bff/package.json.tpl",
  ];

  for (const packageFile of packageFiles) {
    const packageJson = JSON.parse(
      await readFile(path.join(blueprintRoot, packageFile), "utf8"),
    );
    const dependencies = {
      ...packageJson.dependencies,
      ...packageJson.devDependencies,
    };

    for (const [name, version] of Object.entries(dependencies)) {
      assert.match(
        version,
        /^\d+\.\d+\.\d+$/,
        `${name} is not exactly pinned in ${packageFile}`,
      );
    }
  }
});

test("Bootstrapper and package versions stay synchronized", async () => {
  const packageJson = JSON.parse(
    await readFile(path.join(repositoryRoot, "package.json"), "utf8"),
  );
  const bootstrap = await readFile(
    path.join(repositoryRoot, "bootstrap.ps1"),
    "utf8",
  );
  const versionMatch = bootstrap.match(
    /BootstrapperVersion = "([^"]+)"/,
  );

  assert.notEqual(versionMatch, null);
  assert.equal(versionMatch[1], packageJson.version);

  const manifest = await readManifest();
  assert.equal(manifest.version, packageJson.version);
});

test("generated TypeScript build metadata is ignored", async () => {
  const gitignore = await readFile(
    path.join(blueprintRoot, "template", ".gitignore.tpl"),
    "utf8",
  );

  assert.match(gitignore, /^\*\.tsbuildinfo$/m);
});

test("Japanese references do not create nested AGENTS.md instruction files", async () => {
  const manifest = await readManifest();
  const targets = manifest.files.map((file) =>
    file.target.replaceAll("\\", "/"),
  );

  assert.equal(targets.includes("docs/ja-JP/AGENTS-ja.md"), true);
  assert.equal(targets.includes("docs/ja-JP/DESIGN-ja.md"), true);
  assert.equal(
    targets.some((target) => target !== "AGENTS.md" && target.endsWith("/AGENTS.md")),
    false,
  );
});

test("GitHub ruleset JSON uses a UTF-8 file instead of a pipeline", async () => {
  const bootstrap = await readFile(
    path.join(repositoryRoot, "bootstrap.ps1"),
    "utf8",
  );

  assert.equal(bootstrap.includes("$json | & gh api"), false);
  assert.match(
    bootstrap,
    /\[System\.IO\.File\]::WriteAllText\(\$payloadPath, \$json, \$utf8WithoutBom\)/,
  );
  assert.match(bootstrap, /--input \$payloadPath/);
  assert.match(bootstrap, /X-GitHub-Api-Version: 2026-03-10/);
});

test("incomplete repository protection is reported in the completion output", async () => {
  const bootstrap = await readFile(
    path.join(repositoryRoot, "bootstrap.ps1"),
    "utf8",
  );

  assert.match(bootstrap, /ProtectionComplete = \$protectionComplete/);
  assert.match(bootstrap, /Project created with warnings\./);
  assert.match(bootstrap, /Protection : INCOMPLETE/);
});

test("repository provisioning verifies ruleset details and final branch", async () => {
  const bootstrap = await readFile(
    path.join(repositoryRoot, "bootstrap.ps1"),
    "utf8",
  );

  assert.match(bootstrap, /function Assert-ProtectionRuleset/);
  assert.match(bootstrap, /required_review_thread_resolution/);
  assert.match(bootstrap, /required_approving_review_count -ne 0/);
  assert.match(bootstrap, /allowedMergeMethods -notcontains \$ExpectedMergeMethod/);
  assert.match(bootstrap, /-RequiredContexts @\("Quality"\)/);
  assert.match(bootstrap, /allow_merge_commit=true/);
  assert.match(bootstrap, /Repository merge settings verification failed/);
  assert.match(bootstrap, /includedRefs\.Count -ne 1/);
  assert.match(bootstrap, /excludedRefs\.Count -ne 0/);
  assert.match(bootstrap, /default_branch -ne "main"/);
  assert.match(bootstrap, /delete_branch_on_merge/);
  assert.match(bootstrap, /Compare-Object/);
  assert.match(bootstrap, /unexpected required status checks/);
  assert.match(bootstrap, /ruleTypes\.Count -ne \$expectedRuleTypes\.Count/);
  assert.match(bootstrap, /unexpected or duplicate rule types/);
  assert.match(bootstrap, /strict_required_status_checks_policy/);
  assert.match(bootstrap, /-StrictRequiredChecks \$false/);
  assert.match(bootstrap, /-StrictRequiredChecks \$true/);
  assert.match(bootstrap, /-ExpectedStrictRequiredChecks \$false/);
  assert.match(bootstrap, /-ExpectedStrictRequiredChecks \$true/);
  assert.match(bootstrap, /unexpected strict status check policy/);
  assert.match(bootstrap, /currentBranch -ne "develop"/);
});

test("catalog contains two schema v2 Blueprint manifests", async () => {
  const blueprintIds = ["web-hono", "api-spring"];

  for (const blueprintId of blueprintIds) {
    const manifest = JSON.parse(
      await readFile(
        path.join(
          repositoryRoot,
          "blueprints",
          blueprintId,
          "manifest.json",
        ),
        "utf8",
      ),
    );

    assert.equal(manifest.schemaVersion, 2);
    assert.equal(manifest.id, blueprintId);
    assert.ok(manifest.displayName.length > 0);
    assert.ok(manifest.toolchains.length > 0);
    assert.ok(manifest.verification.length > 0);
  }
});

test("api-spring sources are typed, safe, and checksum verified", async () => {
  const springRoot = path.join(repositoryRoot, "blueprints", "api-spring");
  const manifest = JSON.parse(
    await readFile(path.join(springRoot, "manifest.json"), "utf8"),
  );
  const targets = new Set();

  for (const file of manifest.files) {
    assert.equal(["text", "binary"].includes(file.kind), true);
    assert.equal(path.isAbsolute(file.source), false);
    assert.equal(path.isAbsolute(file.target), false);
    assert.equal(file.source.includes(".."), false);
    assert.equal(file.target.includes(".."), false);
    assert.equal(targets.has(file.target.toLowerCase()), false);
    targets.add(file.target.toLowerCase());

    const bytes = await readFile(path.join(springRoot, file.source));

    if (file.kind === "binary") {
      assert.equal(file.template, false);
      assert.match(file.sha256, /^[0-9a-f]{64}$/);
      assert.equal(
        createHash("sha256").update(bytes).digest("hex"),
        file.sha256,
      );
    } else {
      assert.equal(
        bytes.subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf])),
        false,
      );
      assert.equal(bytes.toString("utf8").includes("\r"), false);
    }
  }
});

test("api-spring pins the supported build and wrapper security metadata", async () => {
  const springRoot = path.join(repositoryRoot, "blueprints", "api-spring");
  const build = await readFile(
    path.join(springRoot, "template", "build.gradle.kts.tpl"),
    "utf8",
  );
  const wrapper = await readFile(
    path.join(
      springRoot,
      "template",
      "gradle",
      "wrapper",
      "gradle-wrapper.properties.tpl",
    ),
    "utf8",
  );

  assert.match(build, /org\.springframework\.boot"\) version "4\.1\.0"/);
  assert.match(build, /kotlin\("jvm"\) version "2\.2\.\d+"/);
  assert.match(build, /spring-boot-starter-webmvc/);
  assert.doesNotMatch(build, /spring-boot-starter-web"\)/);
  assert.match(build, /JavaLanguageVersion\.of\(17\)/);
  assert.match(wrapper, /gradle-9\.5\.1-bin\.zip/);
  assert.match(wrapper, /^distributionSha256Sum=[0-9a-f]{64}$/m);
  assert.match(wrapper, /^validateDistributionUrl=true$/m);
});

test("api-spring Quality uses JDK 17 without Node or pnpm", async () => {
  const workflow = await readFile(
    path.join(
      repositoryRoot,
      "blueprints",
      "api-spring",
      "template",
      ".github",
      "workflows",
      "ci.yml.tpl",
    ),
    "utf8",
  );

  assert.match(workflow, /name: Quality/);
  assert.match(workflow, /java-version: "17"/);
  assert.match(workflow, /BASE_REPOSITORY: \$\{\{ github\.repository \}\}/);
  assert.match(
    workflow,
    /HEAD_REPOSITORY: \$\{\{ github\.event\.pull_request\.head\.repo\.full_name \}\}/,
  );
  assert.doesNotMatch(workflow, /setup-node|pnpm/);
});

test("binary source pipeline validates all assets before destination creation", async () => {
  const bootstrap = await readFile(
    path.join(repositoryRoot, "bootstrap.ps1"),
    "utf8",
  );
  const sourceReadIndex = bootstrap.indexOf(
    "$blueprintSources = Read-BlueprintSources",
  );
  const toolchainIndex = bootstrap.lastIndexOf(
    "Assert-BlueprintToolchains",
    sourceReadIndex,
  );
  const confirmationIndex = bootstrap.indexOf(
    'Confirm-Action -Prompt "Generate this project?"',
  );
  const firstWriteIndex = bootstrap.indexOf(
    "New-Item -ItemType Directory -Path $Destination",
  );

  assert.ok(toolchainIndex > 0);
  assert.ok(sourceReadIndex > toolchainIndex);
  assert.ok(confirmationIndex > sourceReadIndex);
  assert.ok(firstWriteIndex > confirmationIndex);
  assert.match(bootstrap, /Blueprint binary checksum mismatch/);
  assert.match(bootstrap, /Write-GeneratedBinaryFile/);
  assert.match(bootstrap, /GetByteArrayAsync/);
  assert.match(bootstrap, /BlueprintRevision/);
});

test("root Quality provisions JDK 17 for Spring generation", async () => {
  const workflow = await readFile(
    path.join(repositoryRoot, ".github", "workflows", "ci.yml"),
    "utf8",
  );
  const setupJavaIndex = workflow.indexOf("uses: actions/setup-java@v5");
  const generatedTestIndex = workflow.indexOf("pnpm run test:generated");

  assert.ok(setupJavaIndex > 0);
  assert.ok(generatedTestIndex > setupJavaIndex);
  assert.match(workflow, /java-version: "17"/);
});
