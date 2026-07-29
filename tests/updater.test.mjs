import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { createServer } from "node:http";
import { mkdtemp, mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const updaterPath = path.join(repositoryRoot, "update.ps1");
const baseCommit = "1".repeat(40);
const targetCommit = "2".repeat(40);

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function runUpdater(args, options = {}) {
  return execFileAsync(
    "pwsh",
    ["-NoProfile", "-File", updaterPath, ...args],
    {
      cwd: options.cwd ?? repositoryRoot,
      encoding: "utf8",
      maxBuffer: 10 * 1024 * 1024,
    },
  );
}

async function runGit(root, args) {
  return execFileAsync("git", ["-C", root, ...args], {
    encoding: "utf8",
  });
}

function configTemplate(blueprint, version, schemaVersion) {
  const definitions = {
    "web-hono": {
      basePackage: "",
      systems:
        "  - id: web-frontend\n" +
        "    type: react-vite\n" +
        "    port: 5173\n" +
        "  - id: api-bff\n" +
        "    type: hono\n" +
        "    port: 3000\n",
    },
    "api-spring": {
      basePackage: "  basePackage: __BASE_PACKAGE__\n",
      systems:
        "  - id: api-server\n" +
        "    type: spring-boot\n" +
        "    port: 8080\n",
    },
    "api-spring-postgres": {
      basePackage: "  basePackage: __BASE_PACKAGE__\n",
      systems:
        "  - id: api-server\n" +
        "    type: spring-boot-postgresql\n" +
        "    port: 8080\n",
    },
  };
  const definition = definitions[blueprint];
  const bootstrapper =
    schemaVersion === 1
      ? `  version: ${version}\n`
      : "  source: rukaruka966/ibuki-bootstrapper\n" +
        `  blueprint: ${blueprint}\n` +
        `  version: ${version}\n` +
        "  commit: __BOOTSTRAPPER_COMMIT__\n";

  return (
    `schemaVersion: ${schemaVersion}\n` +
    "project:\n" +
    "  id: __PROJECT_ID__\n" +
    '  displayName: "__PROJECT_DISPLAY_NAME_YAML__"\n' +
    definition.basePackage +
    "branchStrategy:\n" +
    "  default: main\n" +
    "  integration: develop\n" +
    "systems:\n" +
    definition.systems +
    "bootstrapper:\n" +
    bootstrapper
  );
}

function render(content, { version, commit }) {
  return content
    .replaceAll("__PROJECT_ID__", "sample-app")
    .replaceAll("__PROJECT_DISPLAY_NAME_YAML__", "Sample App")
    .replaceAll("__BASE_PACKAGE__", "net.rukaruka966.sampleapp")
    .replaceAll("__BASE_PACKAGE_PATH__", "net/rukaruka966/sampleapp")
    .replaceAll("__BOOTSTRAPPER_VERSION__", version)
    .replaceAll("__BOOTSTRAPPER_COMMIT__", commit);
}

async function writeBlueprint(root, blueprint, files) {
  const blueprintRoot = path.join(root, "blueprints", blueprint);
  const templateRoot = path.join(blueprintRoot, "template");
  await mkdir(templateRoot, { recursive: true });
  const manifestFiles = [];

  for (const file of files) {
    const source = `${file.target.replaceAll("/", "-")}.tpl`;
    const bytes = Buffer.isBuffer(file.content)
      ? file.content
      : Buffer.from(file.content, "utf8");
    await writeFile(path.join(templateRoot, source), bytes);
    manifestFiles.push({
      source: `template/${source}`,
      target: file.target,
      kind: file.kind ?? "text",
      template: file.template ?? false,
      ...(file.kind === "binary" ? { sha256: sha256(bytes) } : {}),
    });
  }

  await writeFile(
    path.join(blueprintRoot, "manifest.json"),
    `${JSON.stringify(
      {
        schemaVersion: 5,
        id: blueprint,
        version: "test",
        displayName: `Test ${blueprint}`,
        files: manifestFiles,
        fileSets: [],
        projectRequirements: [],
        recommendedCommands: [],
      },
      null,
      2,
    )}\n`,
    "utf8",
  );
}

async function makeComprehensiveFixture() {
  const root = await mkdtemp(path.join(os.tmpdir(), "ibuki-updater-test-"));
  const baseRoot = path.join(root, "base");
  const targetRoot = path.join(root, "target");
  const projectRoot = path.join(root, "project");
  const blueprint = "api-spring-postgres";
  const baseConfig = configTemplate(blueprint, "0.8.0", 1);
  const targetConfig = configTemplate(blueprint, "0.9.0", 2);
  const baseFiles = [
    { target: "project.config.yaml", content: baseConfig, template: true },
    { target: "safe.txt", content: "base-safe\n" },
    { target: "keep.txt", content: "shared-keep\n" },
    { target: "current.txt", content: "base-current\n" },
    { target: "conflict.txt", content: "base-conflict\n" },
    { target: "delete.txt", content: "base-delete\n" },
    { target: "binary.bin", content: Buffer.from([0, 1, 2]), kind: "binary" },
  ];
  const targetFiles = [
    { target: "project.config.yaml", content: targetConfig, template: true },
    { target: "safe.txt", content: "target-safe\n" },
    { target: "keep.txt", content: "shared-keep\n" },
    { target: "current.txt", content: "target-current\n" },
    { target: "conflict.txt", content: "target-conflict\n" },
    { target: "add.txt", content: "target-add\n" },
    { target: "binary.bin", content: Buffer.from([3, 4, 5]), kind: "binary" },
  ];
  await writeBlueprint(baseRoot, blueprint, baseFiles);
  await writeBlueprint(targetRoot, blueprint, targetFiles);
  await mkdir(projectRoot, { recursive: true });

  for (const file of baseFiles) {
    const destination = path.join(projectRoot, file.target);
    await mkdir(path.dirname(destination), { recursive: true });
    const content = file.template
      ? render(file.content, { version: "0.8.0", commit: baseCommit })
      : file.content;
    await writeFile(destination, content);
  }

  await writeFile(path.join(projectRoot, "keep.txt"), "project-keep\n");
  await writeFile(path.join(projectRoot, "current.txt"), "target-current\n");
  await writeFile(path.join(projectRoot, "conflict.txt"), "project-conflict\n");
  await writeFile(path.join(projectRoot, "binary.bin"), Buffer.from([9, 9, 9]));

  return { root, baseRoot, targetRoot, projectRoot };
}

function sourceArguments(fixture, outputDirectory) {
  return [
    "-Mode",
    "Plan",
    "-ProjectRoot",
    fixture.projectRoot,
    "-OutputDirectory",
    outputDirectory,
    "-NonInteractive",
    "-BaseSourceRoot",
    fixture.baseRoot,
    "-TargetSourceRoot",
    fixture.targetRoot,
    "-BaseSourceVersion",
    "0.8.0",
    "-TargetSourceVersion",
    "0.9.0",
    "-BaseSourceCommit",
    baseCommit,
    "-TargetSourceCommit",
    targetCommit,
  ];
}

async function readPlan(bundleRoot) {
  return JSON.parse(await readFile(path.join(bundleRoot, "plan.json"), "utf8"));
}

function stablePlan(plan) {
  return {
    source: plan.source,
    target: plan.target,
    counts: plan.counts,
    operations: plan.operations,
  };
}

test("Plan classifies every three-way state without changing the project", async () => {
  const fixture = await makeComprehensiveFixture();
  const bundleRoot = path.join(fixture.root, "bundle-local");
  const before = await readFile(
    path.join(fixture.projectRoot, "project.config.yaml"),
    "utf8",
  );
  await runUpdater(sourceArguments(fixture, bundleRoot));
  const plan = await readPlan(bundleRoot);

  assert.deepEqual(plan.counts, {
    add: 1,
    "safe-update": 2,
    "keep-local": 1,
    "already-current": 1,
    conflict: 2,
    "delete-candidate": 1,
  });
  assert.equal(
    await readFile(path.join(fixture.projectRoot, "project.config.yaml"), "utf8"),
    before,
  );
  assert.match(await readFile(path.join(bundleRoot, "prompt.md"), "utf8"), /untrusted project data/);
  assert.match(await readFile(path.join(bundleRoot, "summary.md"), "utf8"), /No project files were changed/);
  assert.equal(
    plan.operations.find(({ path: file }) => file === "binary.bin").diffs
      .project,
    undefined,
  );
});

test("local and HTTP immutable sources produce the same Plan", async (t) => {
  const fixture = await makeComprehensiveFixture();
  const localBundle = path.join(fixture.root, "bundle-local");
  const httpBundle = path.join(fixture.root, "bundle-http");
  await runUpdater(sourceArguments(fixture, localBundle));

  const server = createServer(async (request, response) => {
    try {
      const segments = decodeURIComponent(request.url ?? "").split("/").filter(Boolean);
      const sourceRoot = segments.shift() === "base" ? fixture.baseRoot : fixture.targetRoot;
      const file = path.join(sourceRoot, ...segments);
      response.end(await readFile(file));
    } catch {
      response.statusCode = 404;
      response.end("not found");
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => server.close());
  const { port } = server.address();

  await runUpdater([
    "-Mode", "Plan",
    "-ProjectRoot", fixture.projectRoot,
    "-OutputDirectory", httpBundle,
    "-NonInteractive",
    "-BaseRawRoot", `http://127.0.0.1:${port}/base`,
    "-TargetRawRoot", `http://127.0.0.1:${port}/target`,
    "-BaseSourceVersion", "0.8.0",
    "-TargetSourceVersion", "0.9.0",
    "-BaseSourceCommit", baseCommit,
    "-TargetSourceCommit", targetCommit,
  ]);

  assert.deepEqual(
    stablePlan(await readPlan(httpBundle)),
    stablePlan(await readPlan(localBundle)),
  );
});

test("schema 1 inference supports every available Blueprint", async () => {
  for (const blueprint of ["web-hono", "api-spring", "api-spring-postgres"]) {
    const root = await mkdtemp(path.join(os.tmpdir(), "ibuki-updater-schema1-"));
    const baseRoot = path.join(root, "base");
    const targetRoot = path.join(root, "target");
    const projectRoot = path.join(root, "project");
    const bundleRoot = path.join(root, "bundle");
    const baseConfig = configTemplate(blueprint, "0.8.0", 1);
    const targetConfig = configTemplate(blueprint, "0.9.0", 2);
    await writeBlueprint(baseRoot, blueprint, [
      { target: "project.config.yaml", content: baseConfig, template: true },
    ]);
    await writeBlueprint(targetRoot, blueprint, [
      { target: "project.config.yaml", content: targetConfig, template: true },
    ]);
    await mkdir(projectRoot, { recursive: true });
    await writeFile(
      path.join(projectRoot, "project.config.yaml"),
      render(baseConfig, { version: "0.8.0", commit: baseCommit }),
    );
    await runUpdater(
      sourceArguments({ baseRoot, targetRoot, projectRoot }, bundleRoot),
    );
    assert.equal((await readPlan(bundleRoot)).project.blueprint, blueprint);
  }
});

async function makeApplyFixture(branch = "feat/updater-test") {
  const fixture = await makeComprehensiveFixture();
  await writeFile(path.join(fixture.projectRoot, "conflict.txt"), "base-conflict\n");
  await writeFile(path.join(fixture.projectRoot, "binary.bin"), Buffer.from([0, 1, 2]));
  await writeFile(path.join(fixture.projectRoot, "delete.txt"), "project-owned\n");
  await runGit(fixture.projectRoot, ["init", "-b", "develop"]);
  await runGit(fixture.projectRoot, ["config", "user.email", "ibuki@example.invalid"]);
  await runGit(fixture.projectRoot, ["config", "user.name", "Ibuki Test"]);
  await runGit(fixture.projectRoot, ["add", "."]);
  await runGit(fixture.projectRoot, ["commit", "-m", "test: create fixture"]);
  if (branch !== "develop") {
    await runGit(fixture.projectRoot, ["switch", "-c", branch]);
  }
  return fixture;
}

test("Apply writes only a conflict-free, unchanged Plan on a feature branch", async () => {
  const fixture = await makeApplyFixture();
  const bundleRoot = path.join(fixture.root, "bundle-apply");
  await runUpdater(sourceArguments(fixture, bundleRoot));
  const planPath = path.join(bundleRoot, "plan.json");
  const plan = await readPlan(bundleRoot);
  plan.operations = plan.operations.filter(
    ({ status }) => !["delete-candidate", "conflict"].includes(status),
  );
  await writeFile(planPath, `${JSON.stringify(plan, null, 2)}\n`);

  await runUpdater(["-Mode", "Apply", "-PlanPath", planPath, "-NonInteractive", "-Yes"]);
  assert.equal(await readFile(path.join(fixture.projectRoot, "safe.txt"), "utf8"), "target-safe\n");
  assert.equal(await readFile(path.join(fixture.projectRoot, "add.txt"), "utf8"), "target-add\n");
  const config = await readFile(path.join(fixture.projectRoot, "project.config.yaml"), "utf8");
  assert.match(config, /^schemaVersion: 2/m);
  assert.match(config, new RegExp(`commit: ${targetCommit}`));
  assert.equal(await readFile(path.join(fixture.projectRoot, "keep.txt"), "utf8"), "project-keep\n");
  assert.equal(
    (await readdir(bundleRoot)).some((entry) => entry.startsWith("rollback-")),
    false,
  );
});

test("Apply rejects protected branches and post-Plan project changes", async () => {
  const protectedFixture = await makeApplyFixture("develop");
  const protectedBundle = path.join(protectedFixture.root, "bundle-protected");
  await runUpdater(sourceArguments(protectedFixture, protectedBundle));
  await assert.rejects(
    runUpdater(["-Mode", "Apply", "-PlanPath", path.join(protectedBundle, "plan.json"), "-NonInteractive", "-Yes"]),
    /branch other than 'develop'/,
  );

  const changedFixture = await makeApplyFixture();
  const changedBundle = path.join(changedFixture.root, "bundle-changed");
  await runUpdater(sourceArguments(changedFixture, changedBundle));
  const changedPlanPath = path.join(changedBundle, "plan.json");
  const changedPlan = await readPlan(changedBundle);
  changedPlan.operations = changedPlan.operations.filter(
    ({ status }) => !["delete-candidate", "conflict"].includes(status),
  );
  await writeFile(changedPlanPath, `${JSON.stringify(changedPlan, null, 2)}\n`);
  await writeFile(path.join(changedFixture.projectRoot, "safe.txt"), "changed-after-plan\n");
  await runGit(changedFixture.projectRoot, ["add", "safe.txt"]);
  await runGit(changedFixture.projectRoot, ["commit", "-m", "test: mutate after plan"]);
  await assert.rejects(
    runUpdater(["-Mode", "Apply", "-PlanPath", changedPlanPath, "-NonInteractive", "-Yes"]),
    /Project changed after Plan creation/,
  );
});


test("Plan rejects malformed Manifest flags before writing a Bundle", async () => {
  const fixture = await makeComprehensiveFixture();
  const manifestPath = path.join(
    fixture.targetRoot,
    "blueprints",
    "api-spring-postgres",
    "manifest.json",
  );
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  manifest.files[0].template = "true";
  await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

  const bundleRoot = path.join(fixture.root, "bad-bundle");
  await assert.rejects(
    runUpdater(sourceArguments(fixture, bundleRoot)),
    /invalid file entry types/,
  );
  await assert.rejects(stat(bundleRoot), { code: "ENOENT" });
});

test("Apply rejects a tampered operation contract", async () => {
  const fixture = await makeApplyFixture();
  const bundleRoot = path.join(fixture.root, "bundle-tampered");
  await runUpdater(sourceArguments(fixture, bundleRoot));
  const planPath = path.join(bundleRoot, "plan.json");
  const plan = await readPlan(bundleRoot);
  plan.operations[0].status = "run-command";
  await writeFile(planPath, `${JSON.stringify(plan, null, 2)}\n`);

  await assert.rejects(
    runUpdater(["-Mode", "Apply", "-PlanPath", planPath, "-NonInteractive", "-Yes"]),
    /invalid status/,
  );
});
test("IEX defaults to read-only Plan and preserves caller state on failure", async () => {
  const cwd = await mkdtemp(path.join(os.tmpdir(), "ibuki-updater-iex-"));
  const escapedUpdater = updaterPath.replaceAll("'", "''");
  const command = [
    '$global:LASTEXITCODE = 37',
    '$sentinel = "caller-state"',
    '$before = (Get-Location).Path',
    `try { Get-Content -Raw -LiteralPath '${escapedUpdater}' | Invoke-Expression } catch {}`,
    '[PSCustomObject]@{ location = (Get-Location).Path; before = $before; sentinel = $sentinel; lastExitCode = $global:LASTEXITCODE } | ConvertTo-Json -Compress',
  ].join("; ");
  const { stdout } = await execFileAsync("pwsh", ["-NoProfile", "-Command", command], {
    cwd,
    encoding: "utf8",
  });
  const result = JSON.parse(stdout.trim().split(/\r?\n/).at(-1));

  assert.equal(result.location, result.before);
  assert.equal(result.sentinel, "caller-state");
  assert.equal(result.lastExitCode, 37);
  assert.match(stdout, /\[Plan\]/);
});
