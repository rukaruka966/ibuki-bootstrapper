import assert from "node:assert/strict";
import {
  access,
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);

function createManifest(file) {
  return {
    schemaVersion: 3,
    id: "web-hono",
    version: "test",
    displayName: "Manifest test",
    projectRequirements: [
      {
        id: "node",
        command: "node",
        versionArguments: ["--version"],
        minimumVersion: "0.0.0",
        versionPattern: "v?(\\d+\\.\\d+\\.\\d+)",
      },
    ],
    recommendedCommands: [
      {
        command: "node",
        arguments: ["--version"],
        workingDirectory: ".",
      },
    ],
    files: [file],
  };
}

async function runInvalidManifest(manifest, source = Buffer.from("source\n")) {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), "ibuki-manifest-v3-"));
  const blueprintRoot = path.join(fixtureRoot, "blueprints", "web-hono");
  const sourcePath = path.join(blueprintRoot, "template", "source.bin");
  const destination = path.join(fixtureRoot, "destination");
  const bootstrapPath = path.join(fixtureRoot, "bootstrap.ps1");

  try {
    await mkdir(path.dirname(sourcePath), { recursive: true });
    await copyFile(
      path.join(repositoryRoot, "bootstrap.ps1"),
      bootstrapPath,
    );
    await writeFile(
      path.join(blueprintRoot, "manifest.json"),
      `${JSON.stringify(manifest, null, 2)}\n`,
      "utf8",
    );
    await writeFile(sourcePath, source);

    const result = spawnSync(
      "pwsh",
      [
        "-NoProfile",
        "-File",
        bootstrapPath,
        "-Blueprint",
        "web-hono",
        "-ProjectId",
        "manifest-test",
        "-Destination",
        destination,
        "-SkipGitHub",
        "-NonInteractive",
        "-Yes",
      ],
      {
        cwd: fixtureRoot,
        encoding: "utf8",
        timeout: 30_000,
      },
    );

    await assert.rejects(access(destination));
    return `${result.stdout}\n${result.stderr}`;
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
  }
}

async function runValidManifest(
  manifest,
  source = Buffer.from("source\n"),
  displayName = "Manifest test",
) {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), "ibuki-manifest-v3-ok-"));
  const blueprintRoot = path.join(fixtureRoot, "blueprints", "web-hono");
  const sourcePath = path.join(blueprintRoot, "template", "source.bin");
  const destination = path.join(fixtureRoot, "destination");
  const bootstrapPath = path.join(fixtureRoot, "bootstrap.ps1");

  try {
    await mkdir(path.dirname(sourcePath), { recursive: true });
    await copyFile(
      path.join(repositoryRoot, "bootstrap.ps1"),
      bootstrapPath,
    );
    await writeFile(
      path.join(blueprintRoot, "manifest.json"),
      `${JSON.stringify(manifest, null, 2)}\n`,
      "utf8",
    );
    await writeFile(sourcePath, source);

    const result = spawnSync(
      "pwsh",
      [
        "-NoProfile",
        "-File",
        bootstrapPath,
        "-Blueprint",
        "web-hono",
        "-ProjectId",
        "manifest-test",
        "-DisplayName",
        displayName,
        "-Destination",
        destination,
        "-SkipGitHub",
        "-NonInteractive",
        "-Yes",
      ],
      {
        cwd: fixtureRoot,
        encoding: "utf8",
        timeout: 30_000,
      },
    );
    const output = `${result.stdout}\n${result.stderr}`;

    assert.equal(result.status, 0, output);
    const generatedContent = await readFile(
      path.join(destination, "source.txt"),
      "utf8",
    );
    return { output, generatedContent };
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
  }
}

test("empty project requirements and recommended commands are valid", async () => {
  const manifest = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });
  manifest.projectRequirements = [];
  manifest.recommendedCommands = [];

  const { output } = await runValidManifest(manifest);
  assert.match(output, /Project created successfully\./);
  assert.match(output, /Project-owned checks below were not run by Ibuki:/);
  assert.match(output, /\(none\)/);
});

test("project requirements and recommended commands are informational only", async () => {
  const manifest = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });
  manifest.projectRequirements[0].command = "ibuki-command-must-not-exist";
  manifest.recommendedCommands[0].command = "ibuki-command-must-not-run";

  const { output } = await runValidManifest(manifest);
  assert.match(output, /ibuki-command-must-not-run --version/);
  assert.doesNotMatch(output, /not recognized|not found/i);
});

test("token-like display names are inserted once without being reinterpreted", async () => {
  const manifest = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: true,
  });

  const { generatedContent } = await runValidManifest(
    manifest,
    Buffer.from("name=__PROJECT_DISPLAY_NAME__\nid=__PROJECT_ID__\n"),
    "Literal __PROJECT_ID__ and __HELLO__",
  );

  assert.equal(
    generatedContent,
    "name=Literal __PROJECT_ID__ and __HELLO__\nid=manifest-test\n",
  );
});

test("a later template failure leaves the destination without generated files", async () => {
  const manifest = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "first.txt",
    template: false,
  });
  manifest.files.push({
    kind: "text",
    source: "template/source.bin",
    target: "second.txt",
    template: true,
  });

  assert.match(
    await runInvalidManifest(manifest, Buffer.from("__UNSUPPORTED__\n")),
    /unsupported token: __UNSUPPORTED__/,
  );
});

test("duplicate and file-directory target collisions fail before generation", async () => {
  const duplicate = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "same.txt",
    template: false,
  });
  duplicate.files.push({ ...duplicate.files[0] });
  assert.match(await runInvalidManifest(duplicate), /duplicate target/);

  const collision = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "parent",
    template: false,
  });
  collision.files.push({
    kind: "text",
    source: "template/source.bin",
    target: "parent/child.txt",
    template: false,
  });
  assert.match(
    await runInvalidManifest(collision),
    /file\/directory target collision/,
  );
});

test("legacy schema is rejected before the destination is created", async () => {
  const manifest = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });
  manifest.schemaVersion = 2;

  assert.match(
    await runInvalidManifest(manifest),
    /must use schemaVersion 3/,
  );
});

test("unknown schema properties are rejected before generation", async () => {
  const manifest = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });
  manifest.unexpected = true;

  assert.match(
    await runInvalidManifest(manifest),
    /unknown top-level properties/,
  );
});

test("schema and argument types are validated without coercion", async () => {
  const stringSchema = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });
  stringSchema.schemaVersion = "3";
  assert.match(
    await runInvalidManifest(stringSchema),
    /must use schemaVersion 3/,
  );

  const scalarArguments = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });
  scalarArguments.recommendedCommands[0].arguments = "--version";
  assert.match(
    await runInvalidManifest(scalarArguments),
    /invalid recommended command/,
  );
});

test("backslashes and Windows-invalid characters are rejected in paths", async () => {
  const backslashSource = createManifest({
    kind: "text",
    source: "template\\source.bin",
    target: "source.txt",
    template: false,
  });
  assert.match(
    await runInvalidManifest(backslashSource),
    /unsafe source path/,
  );

  const invalidTarget = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "bad*name.txt",
    template: false,
  });
  assert.match(
    await runInvalidManifest(invalidTarget),
    /unsafe target path/,
  );
});

test("Windows device target is rejected before generation", async () => {
  const manifest = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "CON.txt",
    template: false,
  });

  assert.match(
    await runInvalidManifest(manifest),
    /unsafe target path/,
  );
});

test("binary templates are rejected before generation", async () => {
  const manifest = createManifest({
    kind: "binary",
    source: "template/source.bin",
    target: "source.bin",
    template: true,
    sha256: "c".repeat(64),
  });

  assert.match(
    await runInvalidManifest(manifest),
    /binary source cannot be a template/,
  );
});

test("binary checksum mismatch leaves the destination absent", async () => {
  const manifest = createManifest({
    kind: "binary",
    source: "template/source.bin",
    target: "source.bin",
    template: false,
    sha256: "0".repeat(64),
  });

  assert.match(
    await runInvalidManifest(manifest),
    /binary checksum mismatch/,
  );
});

test("a reparse-point Blueprint root is rejected before manifest execution", async () => {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), "ibuki-reparse-v3-"));
  const externalRoot = await mkdtemp(path.join(tmpdir(), "ibuki-external-v3-"));
  const linkedBlueprint = path.join(
    fixtureRoot,
    "blueprints",
    "web-hono",
  );
  const destination = path.join(fixtureRoot, "not-created");
  const bootstrapPath = path.join(fixtureRoot, "bootstrap.ps1");
  const manifest = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });

  try {
    await mkdir(path.join(externalRoot, "template"), { recursive: true });
    await mkdir(path.dirname(linkedBlueprint), { recursive: true });
    await writeFile(
      path.join(externalRoot, "manifest.json"),
      `${JSON.stringify(manifest, null, 2)}\n`,
      "utf8",
    );
    await writeFile(path.join(externalRoot, "template", "source.bin"), "x\n");
    await copyFile(
      path.join(repositoryRoot, "bootstrap.ps1"),
      bootstrapPath,
    );
    await symlink(externalRoot, linkedBlueprint, "junction");

    const result = spawnSync(
      "pwsh",
      [
        "-NoProfile",
        "-File",
        bootstrapPath,
        "-Blueprint",
        "web-hono",
        "-ProjectId",
        "reparse-test",
        "-Destination",
        destination,
        "-SkipGitHub",
        "-NonInteractive",
        "-Yes",
      ],
      {
        cwd: fixtureRoot,
        encoding: "utf8",
        timeout: 30_000,
      },
    );
    const output = `${result.stdout}\n${result.stderr}`;

    assert.notEqual(result.status, 0);
    assert.match(output, /reparse point/);
    await assert.rejects(access(destination));
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
    await rm(externalRoot, { recursive: true, force: true });
  }
});
