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
    schemaVersion: 5,
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
        category: "repository",
      },
    ],
    recommendedCommands: [
      {
        command: "node",
        arguments: ["--version"],
        workingDirectory: ".",
      },
    ],
    fileSets: [],
    files: [file],
  };
}

async function runInvalidManifest(
  manifest,
  source = Buffer.from("source\n"),
  basePackage = "net.rukaruka966.manifesttest",
  fileSetTarget = "common.txt",
) {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), "ibuki-manifest-v5-"));
  const blueprintRoot = path.join(fixtureRoot, "blueprints", manifest.id);
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

    for (const fileSetId of manifest.fileSets ?? []) {
      const fileSetRoot = path.join(
        fixtureRoot,
        "blueprints",
        "_common",
        fileSetId,
      );
      await mkdir(path.join(fileSetRoot, "template"), { recursive: true });
      await writeFile(
        path.join(fileSetRoot, "manifest.json"),
        `${JSON.stringify(
          {
            schemaVersion: 5,
            id: fileSetId,
            version: "test",
            displayName: "File set fixture",
            projectRequirements: [],
            recommendedCommands: [],
            fileSets: [],
            files: [
              {
                kind: "text",
                source: "template/common.bin",
                target: fileSetTarget,
                template: false,
              },
            ],
          },
          null,
          2,
        )}\n`,
        "utf8",
      );
      await writeFile(
        path.join(fileSetRoot, "template", "common.bin"),
        "common\n",
        "utf8",
      );
    }

    const args = [
        "-NoProfile",
        "-File",
        bootstrapPath,
        "-Blueprint",
        manifest.id,
        "-ProjectId",
        "manifest-test",
        "-Destination",
        destination,
        "-SkipGitHub",
        "-NonInteractive",
        "-Yes",
    ];

    if (manifest.id.startsWith("api-spring")) {
      args.push("-BasePackage", basePackage);
    }

    const result = spawnSync(
      "pwsh",
      args,
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
  expectedTarget = "source.txt",
  basePackage = "net.rukaruka966.manifesttest",
) {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), "ibuki-manifest-v5-ok-"));
  const blueprintRoot = path.join(fixtureRoot, "blueprints", manifest.id);
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

    const args = [
        "-NoProfile",
        "-File",
        bootstrapPath,
        "-Blueprint",
        manifest.id,
        "-ProjectId",
        "manifest-test",
        "-DisplayName",
        displayName,
        "-Destination",
        destination,
        "-SkipGitHub",
        "-NonInteractive",
        "-Yes",
    ];

    if (manifest.id.startsWith("api-spring")) {
      args.push("-BasePackage", basePackage);
    }

    const result = spawnSync(
      "pwsh",
      args,
      {
        cwd: fixtureRoot,
        encoding: "utf8",
        timeout: 30_000,
      },
    );
    const output = `${result.stdout}\n${result.stderr}`;

    assert.equal(result.status, 0, output);
    const generatedContent = await readFile(
      path.join(destination, expectedTarget),
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

test("Base Package target template renders a safe source path", async () => {
  const manifest = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "src/main/kotlin/__BASE_PACKAGE_PATH__/Application.kt",
    template: true,
    targetTemplate: true,
  });
  manifest.id = "api-spring";

  const { generatedContent } = await runValidManifest(
    manifest,
    Buffer.from("package __BASE_PACKAGE__\n"),
    "Manifest test",
    "src/main/kotlin/net/rukaruka966/manifesttest/Application.kt",
  );
  assert.equal(generatedContent, "package net.rukaruka966.manifesttest\n");
});

test("target templates reject unsupported tokens and non-boolean flags", async () => {
  const unsupported = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "src/__PROJECT_ID__/source.txt",
    template: false,
    targetTemplate: true,
  });
  unsupported.id = "api-spring";
  assert.match(
    await runInvalidManifest(unsupported),
    /may only use __BASE_PACKAGE_PATH__/,
  );

  const nonBoolean = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "src/__BASE_PACKAGE_PATH__/source.txt",
    template: false,
    targetTemplate: "yes",
  });
  nonBoolean.id = "api-spring";
  assert.match(
    await runInvalidManifest(nonBoolean),
    /non-boolean targetTemplate/,
  );
});

test("Base Package cannot inject an escaping or Windows-invalid target path", async () => {
  const manifest = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "src/__BASE_PACKAGE_PATH__/source.txt",
    template: false,
    targetTemplate: true,
  });
  manifest.id = "api-spring";

  assert.match(
    await runInvalidManifest(manifest, Buffer.from("source\n"), "net.safe.../CON"),
    /Base package must contain/,
  );
});

test("rendered targets reject duplicate, file-directory collision, and overlong paths", async () => {
  const duplicate = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "src/__BASE_PACKAGE_PATH__/source.txt",
    template: false,
    targetTemplate: true,
  });
  duplicate.id = "api-spring";
  duplicate.files.push({
    kind: "text",
    source: "template/source.bin",
    target: "src/net/rukaruka966/manifesttest/source.txt",
    template: false,
  });
  assert.match(
    await runInvalidManifest(duplicate),
    /Rendered Blueprint contains a duplicate target/,
  );

  const collision = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "src/__BASE_PACKAGE_PATH__",
    template: false,
    targetTemplate: true,
  });
  collision.id = "api-spring";
  collision.files.push({
    kind: "text",
    source: "template/source.bin",
    target: "src/net/rukaruka966/manifesttest/child.txt",
    template: false,
  });
  assert.match(
    await runInvalidManifest(collision),
    /Rendered Blueprint targets have a file\/directory collision/,
  );

  const overlong = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "src/__BASE_PACKAGE_PATH__/source.txt",
    template: false,
    targetTemplate: true,
  });
  overlong.id = "api-spring";
  const longBasePackage = `net.rukaruka966.${Array(24).fill("abcdefghij").join(".")}`;
  assert.match(
    await runInvalidManifest(overlong, Buffer.from("source\n"), longBasePackage),
    /Rendered Blueprint target path is too long/,
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
  manifest.schemaVersion = 4;

  assert.match(
    await runInvalidManifest(manifest),
    /must use schemaVersion 5/,
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

test("project requirements declare a supported category", async () => {
  const missing = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });
  delete missing.projectRequirements[0].category;
  assert.match(
    await runInvalidManifest(missing),
    /incomplete project requirement declaration/,
  );

  const unsupported = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });
  unsupported.projectRequirements[0].category = "toolchain";
  assert.match(
    await runInvalidManifest(unsupported),
    /invalid project requirement category/,
  );
});

test("file set IDs are safe and unique", async () => {
  const unsafe = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });
  unsafe.fileSets = ["../repository"];
  assert.match(
    await runInvalidManifest(unsafe),
    /invalid or duplicate file set ID/,
  );

  const duplicate = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });
  duplicate.fileSets = ["repository", "repository"];
  assert.match(
    await runInvalidManifest(duplicate),
    /invalid or duplicate file set ID/,
  );
});

test("file set target collisions fail before destination creation", async () => {
  const manifest = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "same.txt",
    template: false,
  });
  manifest.fileSets = ["repository"];

  assert.match(
    await runInvalidManifest(
      manifest,
      Buffer.from("source\n"),
      "net.rukaruka966.manifesttest",
      "same.txt",
    ),
    /duplicate target/,
  );
});

test("schema and argument types are validated without coercion", async () => {
  const stringSchema = createManifest({
    kind: "text",
    source: "template/source.bin",
    target: "source.txt",
    template: false,
  });
  stringSchema.schemaVersion = "5";
  assert.match(
    await runInvalidManifest(stringSchema),
    /must use schemaVersion 5/,
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
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), "ibuki-reparse-v4-"));
  const externalRoot = await mkdtemp(path.join(tmpdir(), "ibuki-external-v4-"));
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
