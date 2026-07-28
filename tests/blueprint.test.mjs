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

async function readResolvedFiles(blueprintId) {
  const root = path.join(repositoryRoot, "blueprints", blueprintId);
  const manifest = JSON.parse(
    await readFile(path.join(root, "manifest.json"), "utf8"),
  );
  const resolved = manifest.files.map((file) => ({ file, root }));

  for (const fileSetId of manifest.fileSets) {
    const fileSetRoot = path.join(
      repositoryRoot,
      "blueprints",
      "_common",
      fileSetId,
    );
    const fileSetManifest = JSON.parse(
      await readFile(path.join(fileSetRoot, "manifest.json"), "utf8"),
    );
    resolved.push(
      ...fileSetManifest.files.map((file) => ({ file, root: fileSetRoot })),
    );
  }

  return { manifest, resolved };
}

test("manifest targets are unique and safe", async () => {
  const { resolved } = await readResolvedFiles("web-hono");
  const targets = new Set();

  for (const { file } of resolved) {
    assert.equal(path.isAbsolute(file.target), false);
    assert.equal(file.target.includes(".."), false);
    assert.equal(targets.has(file.target), false, `duplicate: ${file.target}`);
    targets.add(file.target);
  }
});

test("every manifest source exists and uses LF", async () => {
  const { resolved } = await readResolvedFiles("web-hono");

  for (const { file, root } of resolved) {
    const sourcePath = path.join(root, file.source);
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
      repositoryRoot,
      "blueprints",
      "_common",
      "repository",
      "template",
      "scripts",
      "check-pr-branch-policy.mjs.tpl",
    ),
    "utf8",
  );

  assert.equal(generatedPolicy, rootPolicy);
});

test("template files use only supported tokens", async () => {
  const { resolved } = await readResolvedFiles("web-hono");
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

  for (const { file, root } of resolved) {
    const sourcePath = path.join(root, file.source);
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

test("all Blueprints use one root pnpm release contract", async () => {
  const releaseDependencies = {
    "@semantic-release/commit-analyzer": "13.0.1",
    "@semantic-release/github": "12.0.9",
    "@semantic-release/release-notes-generator": "14.1.1",
    "conventional-changelog-conventionalcommits": "9.3.1",
    "semantic-release": "25.0.8",
  };

  for (const blueprintId of [
    "web-hono",
    "api-spring",
    "api-spring-postgres",
  ]) {
    const root = path.join(repositoryRoot, "blueprints", blueprintId);
    const packageJson = JSON.parse(
      await readFile(path.join(root, "template", "package.json.tpl"), "utf8"),
    );
    const { resolved } = await readResolvedFiles(blueprintId);
    const lockTargets = resolved.filter(
      ({ file }) => file.target === "pnpm-lock.yaml",
    );

    assert.equal(packageJson.packageManager, "pnpm@11.12.0");
    assert.equal(packageJson.scripts.release, "semantic-release");
    assert.equal(
      packageJson.scripts["test:release"],
      "node --test tests/release-notes.test.mjs",
    );
    assert.deepEqual(
      Object.fromEntries(
        Object.keys(releaseDependencies).map((name) => [
          name,
          packageJson.devDependencies[name],
        ]),
      ),
      releaseDependencies,
    );
    assert.equal(lockTargets.length, 1, `${blueprintId} root lockfile`);
  }
});

test("common file sets are non-recursive and shared by every Blueprint", async () => {
  for (const fileSetId of ["repository", "spring-gradle"]) {
    const manifest = JSON.parse(
      await readFile(
        path.join(
          repositoryRoot,
          "blueprints",
          "_common",
          fileSetId,
          "manifest.json",
        ),
        "utf8",
      ),
    );

    assert.equal(manifest.schemaVersion, 5);
    assert.deepEqual(manifest.fileSets, []);
    assert.deepEqual(manifest.projectRequirements, []);
    assert.deepEqual(manifest.recommendedCommands, []);
    assert.ok(manifest.files.length > 0);
  }

  for (const blueprintId of [
    "web-hono",
    "api-spring",
    "api-spring-postgres",
  ]) {
    const manifest = JSON.parse(
      await readFile(
        path.join(repositoryRoot, "blueprints", blueprintId, "manifest.json"),
        "utf8",
      ),
    );
    assert.ok(manifest.fileSets.includes("repository"));
  }
});

test("common Release workflow is reusable and waits behind Quality callers", async () => {
  const commonWorkflow = await readFile(
    path.join(
      repositoryRoot,
      "blueprints",
      "_common",
      "repository",
      "template",
      ".github",
      "workflows",
      "release.yml.tpl",
    ),
    "utf8",
  );

  assert.match(commonWorkflow, /workflow_call:/);
  assert.match(commonWorkflow, /contents: write/);
  assert.match(commonWorkflow, /fetch-depth: 0/);
  assert.match(commonWorkflow, /pnpm install --frozen-lockfile/);
  assert.match(commonWorkflow, /run: pnpm release/);

  for (const blueprintId of [
    "web-hono",
    "api-spring",
    "api-spring-postgres",
  ]) {
    const workflow = await readFile(
      path.join(
        repositoryRoot,
        "blueprints",
        blueprintId,
        "template",
        ".github",
        "workflows",
        "ci.yml.tpl",
      ),
      "utf8",
    );
    assert.match(workflow, /release:\n\s+name: Release/);
    assert.match(workflow, /needs:\n\s+- quality/);
    assert.match(workflow, /uses: \.\/\.github\/workflows\/release\.yml/);
  }
});

test("Spring pnpm scripts delegate to a cross-platform Gradle runner", async () => {
  const runner = await readFile(
    path.join(
      repositoryRoot,
      "blueprints",
      "_common",
      "spring-gradle",
      "template",
      "scripts",
      "run-gradle.mjs.tpl",
    ),
    "utf8",
  );

  assert.match(runner, /process\.platform === "win32"/);
  assert.match(runner, /gradlew\.bat/);
  assert.match(runner, /\.\/gradlew/);
  assert.match(runner, /systems", "api-server"/);
  assert.match(runner, /Provide safe Gradle task names or options/);

  for (const blueprintId of ["api-spring", "api-spring-postgres"]) {
    const packageJson = JSON.parse(
      await readFile(
        path.join(
          repositoryRoot,
          "blueprints",
          blueprintId,
          "template",
          "package.json.tpl",
        ),
        "utf8",
      ),
    );
    assert.match(packageJson.scripts.dev, /run-gradle\.mjs bootRun/);
    assert.match(packageJson.scripts.test, /run-gradle\.mjs test/);
    assert.match(packageJson.scripts.check, /run-gradle\.mjs check/);
    assert.match(packageJson.scripts.build, /run-gradle\.mjs bootJar/);
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

test("gitignore ownership is common at root and scoped to each system", async () => {
  const expectedByBlueprint = {
    "web-hono": [
      {
        target: ".gitignore",
        owner: "blueprints/_common/repository",
        source: "template/.gitignore.tpl",
      },
      {
        target: "systems/api-bff/.gitignore",
        owner: "blueprints/web-hono",
        source: "template/node-typescript.gitignore.tpl",
      },
      {
        target: "systems/web-frontend/.gitignore",
        owner: "blueprints/web-hono",
        source: "template/node-typescript.gitignore.tpl",
      },
    ],
    "api-spring": [
      {
        target: ".gitignore",
        owner: "blueprints/_common/repository",
        source: "template/.gitignore.tpl",
      },
      {
        target: "systems/api-server/.gitignore",
        owner: "blueprints/_common/spring-gradle",
        source: "template/systems/api-server/.gitignore.tpl",
      },
    ],
    "api-spring-postgres": [
      {
        target: ".gitignore",
        owner: "blueprints/_common/repository",
        source: "template/.gitignore.tpl",
      },
      {
        target: "systems/api-server/.gitignore",
        owner: "blueprints/_common/spring-gradle",
        source: "template/systems/api-server/.gitignore.tpl",
      },
    ],
  };

  for (const [blueprintId, expected] of Object.entries(expectedByBlueprint)) {
    const { resolved } = await readResolvedFiles(blueprintId);
    const actual = resolved
      .filter(({ file }) => file.target.endsWith(".gitignore"))
      .map(({ file, root }) => ({
        target: file.target.replaceAll("\\", "/"),
        owner: path
          .relative(repositoryRoot, root)
          .replaceAll("\\", "/"),
        source: file.source.replaceAll("\\", "/"),
      }))
      .sort((left, right) => left.target.localeCompare(right.target));

    assert.deepEqual(
      actual,
      [...expected].sort((left, right) =>
        left.target.localeCompare(right.target)),
      blueprintId,
    );
    assert.equal(
      actual.filter(({ target }) => target === ".gitignore").length,
      1,
      `${blueprintId} root owner`,
    );
  }
});

test("Japanese references do not create nested AGENTS.md instruction files", async () => {
  const { resolved } = await readResolvedFiles("web-hono");
  const targets = resolved.map(({ file }) =>
    file.target.replaceAll("\\", "/"),
  );

  assert.equal(targets.includes("docs/ja-JP/AGENTS-ja.md"), true);
  assert.equal(targets.includes("docs/ja-JP/DESIGN-ja.md"), true);
  assert.equal(
    targets.includes("docs/ja-JP/REPOSITORY_OPERATIONS-ja.md"),
    true,
  );
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

test("catalog contains three schema v5 Blueprint manifests", async () => {
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

    assert.equal(manifest.schemaVersion, 5);
    assert.equal(manifest.id, blueprintId);
    assert.ok(manifest.displayName.length > 0);
    assert.ok(Array.isArray(manifest.projectRequirements));
    assert.ok(Array.isArray(manifest.recommendedCommands));
    assert.ok(Array.isArray(manifest.fileSets));
    assert.ok(manifest.fileSets.includes("repository"));
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

test("api-spring Quality uses pnpm to delegate to JDK 17 and Gradle", async () => {
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
  assert.match(workflow, /actions\/setup-node@v6/);
  assert.match(workflow, /pnpm\/action-setup@v4\.4\.0/);
  assert.match(workflow, /run: pnpm check/);
  assert.match(workflow, /run: pnpm build/);
  assert.match(workflow, /BASE_REPOSITORY: \$\{\{ github\.repository \}\}/);
  assert.match(
    workflow,
    /HEAD_REPOSITORY: \$\{\{ github\.event\.pull_request\.head\.repo\.full_name \}\}/,
  );
  assert.match(workflow, /uses: \.\/\.github\/workflows\/release\.yml/);
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
    ".github/workflows/ci.yml.tpl",
    "pnpm-lock.yaml.tpl",
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
