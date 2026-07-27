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
    "__BASE_PACKAGE__",
    "__BASE_PACKAGE_PATH__",
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
  const cleanGateIndex = bootstrap.indexOf(
    "Generated repository is not clean before GitHub creation.",
  );
  const createRepositoryIndex = bootstrap.indexOf(
    "Invoke-CheckedCommand -FilePath gh -Arguments $createArguments",
  );
  assert.ok(cleanGateIndex > 0);
  assert.ok(createRepositoryIndex > cleanGateIndex);
  assert.doesNotMatch(bootstrap, /function Wait-ForQualityWorkflow/);
  assert.match(
    bootstrap,
    /GitHub Actions Quality runs independently after the push\./,
  );
});

test("catalog contains three schema v4 Blueprint manifests", async () => {
  const blueprintIds = ["web-hono", "api-spring", "api-spring-postgres"];

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

    assert.equal(manifest.schemaVersion, 4);
    assert.equal(manifest.id, blueprintId);
    assert.ok(manifest.displayName.length > 0);
    assert.ok(Array.isArray(manifest.projectRequirements));
    assert.ok(Array.isArray(manifest.recommendedCommands));
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

test("api-spring-postgres provides MyBatis and explicit E2E infrastructure only", async () => {
  const postgresRoot = path.join(
    repositoryRoot,
    "blueprints",
    "api-spring-postgres",
  );
  const manifest = JSON.parse(
    await readFile(path.join(postgresRoot, "manifest.json"), "utf8"),
  );
  const build = await readFile(
    path.join(postgresRoot, "template", "build.gradle.kts.tpl"),
    "utf8",
  );
  const unitTest = await readFile(
    path.join(
      postgresRoot,
      "template",
      "src",
      "test",
      "kotlin",
      "com",
      "example",
      "application",
      "ApiApplicationTests.kt.tpl",
    ),
    "utf8",
  );
  const applicationConfig = await readFile(
    path.join(
      postgresRoot,
      "template",
      "src",
      "main",
      "resources",
      "application.yml.tpl",
    ),
    "utf8",
  );

  assert.equal(manifest.version, "0.7.0");
  assert.match(
    build,
    /mybatis-spring-boot-starter:4\.0\.1/,
  );
  assert.match(build, /mybatis-dynamic-sql:2\.0\.0/);
  assert.match(build, /org\.flywaydb:flyway-core/);
  assert.match(build, /org\.flywaydb:flyway-database-postgresql/);
  assert.match(build, /runtimeOnly\("org\.postgresql:postgresql"\)/);
  assert.match(build, /testcontainers-bom:2\.0\.5/);
  assert.match(build, /testcontainers-postgresql/);
  assert.match(build, /testcontainers-junit-jupiter/);
  assert.match(build, /sourceSets\.create\("e2eTest"\)/);
  assert.match(build, /tasks\.register<Test>\("e2eTest"\)/);
  assert.doesNotMatch(build, /spring-boot-starter-data-jpa/);
  assert.doesNotMatch(build, /dependsOn.*e2eTest|e2eTest.*dependsOn/s);
  assert.doesNotMatch(unitTest, /SpringBootTest|Testcontainers|PostgreSQL/);
  assert.match(
    applicationConfig,
    /url: \$\{DB_URL:jdbc:postgresql:\/\/localhost:5432\/app\}/,
  );
  assert.match(applicationConfig, /username: \$\{DB_USERNAME:postgres\}/);
  assert.match(applicationConfig, /password: \$\{DB_PASSWORD:\}/);
  assert.match(applicationConfig, /locations: classpath:db\/migration/);
  assert.match(applicationConfig, /map-underscore-to-camel-case: true/);

  const targets = manifest.files.map((file) => file.target);
  assert.equal(
    targets.some((target) => target.includes("/src/test/") && target.endsWith("/.gitkeep")),
    false,
    "src/test contains a real unit test and must not include .gitkeep",
  );

  for (const expectedTarget of [
    "systems/api-server/src/main/kotlin/__BASE_PACKAGE_PATH__/controller/.gitkeep",
    "systems/api-server/src/main/kotlin/__BASE_PACKAGE_PATH__/service/.gitkeep",
    "systems/api-server/src/main/kotlin/__BASE_PACKAGE_PATH__/model/.gitkeep",
    "systems/api-server/src/main/kotlin/__BASE_PACKAGE_PATH__/mapper/.gitkeep",
    "systems/api-server/src/main/resources/db/migration/.gitkeep",
    "systems/api-server/src/e2eTest/kotlin/__BASE_PACKAGE_PATH__/.gitkeep",
    "systems/api-server/src/e2eTest/resources/db/migration/.gitkeep",
  ]) {
    assert.ok(targets.includes(expectedTarget), expectedTarget);
  }
});

test("Spring Blueprint common infrastructure stays byte-identical", async () => {
  const plainRoot = path.join(repositoryRoot, "blueprints", "api-spring", "template");
  const postgresRoot = path.join(
    repositoryRoot,
    "blueprints",
    "api-spring-postgres",
    "template",
  );

  for (const relativePath of [
    ".gitattributes.tpl",
    ".gitignore.tpl",
    ".github/workflows/ci.yml.tpl",
    "gradlew",
    "gradlew.bat",
    "gradle/wrapper/gradle-wrapper.jar",
    "gradle/wrapper/gradle-wrapper.properties.tpl",
    "settings.gradle.kts.tpl",
    "src/main/kotlin/com/example/application/Application.kt.tpl",
    "src/main/kotlin/com/example/application/HealthController.kt.tpl",
    "src/main/kotlin/com/example/application/ApiExceptionHandler.kt.tpl",
  ]) {
    assert.deepEqual(
      await readFile(path.join(postgresRoot, relativePath)),
      await readFile(path.join(plainRoot, relativePath)),
      relativePath,
    );
  }
});

test("binary source pipeline validates all assets before destination creation", async () => {
  const bootstrap = await readFile(
    path.join(repositoryRoot, "bootstrap.ps1"),
    "utf8",
  );
  const sourceReadIndex = bootstrap.indexOf(
    "$blueprintSources = Read-BlueprintSources",
  );
  const confirmationIndex = bootstrap.indexOf(
    'Confirm-Action -Prompt "Generate this project?"',
  );
  const firstWriteIndex = bootstrap.indexOf(
    "New-Item -ItemType Directory -Path $Destination",
  );

  assert.doesNotMatch(bootstrap, /Assert-BlueprintToolchains/);
  assert.ok(sourceReadIndex > 0);
  assert.ok(confirmationIndex > sourceReadIndex);
  assert.ok(firstWriteIndex > confirmationIndex);
  assert.match(bootstrap, /Blueprint binary checksum mismatch/);
  assert.match(bootstrap, /Write-GeneratedBinaryFile/);
  assert.match(bootstrap, /GetByteArrayAsync/);
  assert.match(bootstrap, /BlueprintRevision/);
});

test("root Quality checks the generated file contract without provisioning Java", async () => {
  const workflow = await readFile(
    path.join(repositoryRoot, ".github", "workflows", "ci.yml"),
    "utf8",
  );
  assert.doesNotMatch(workflow, /actions\/setup-java/);
  assert.match(workflow, /pnpm run test:generated/);
});
