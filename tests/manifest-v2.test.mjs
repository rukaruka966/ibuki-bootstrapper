import assert from "node:assert/strict";
import {
  access,
  copyFile,
  mkdir,
  mkdtemp,
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
    schemaVersion: 2,
    id: "web-hono",
    version: "test",
    displayName: "Manifest test",
    toolchains: [
      {
        id: "node",
        command: "node",
        versionArguments: ["--version"],
        minimumVersion: "0.0.0",
        versionPattern: "v?(\\d+\\.\\d+\\.\\d+)",
      },
    ],
    verification: [
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
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), "ibuki-manifest-v2-"));
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

test("schema v1 is rejected before the destination is created", async () => {
  const manifest = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });
  manifest.schemaVersion = 1;

  assert.match(
    await runInvalidManifest(manifest),
    /must use schemaVersion 2/,
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
  stringSchema.schemaVersion = "2";
  assert.match(
    await runInvalidManifest(stringSchema),
    /must use schemaVersion 2/,
  );

  const scalarArguments = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });
  scalarArguments.verification[0].arguments = "--version";
  assert.match(
    await runInvalidManifest(scalarArguments),
    /invalid verification command/,
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
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), "ibuki-reparse-v2-"));
  const externalRoot = await mkdtemp(path.join(tmpdir(), "ibuki-external-v2-"));
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
