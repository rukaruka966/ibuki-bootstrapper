import assert from "node:assert/strict";
import { access, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const bootstrapPath = path.join(repositoryRoot, "bootstrap.ps1");

test("interactive wizard returns from unavailable choices and cancels safely", async () => {
  const workingDirectory = await mkdtemp(
    path.join(tmpdir(), "ibuki-wizard-test-"),
  );
  const projectId = `ibuki-wizard-${process.pid}`;
  const destination = path.join(workingDirectory, projectId);

  try {
    const input = [
      "2",
      "3",
      "invalid",
      "1",
      projectId,
      "",
      "",
      "n",
      "n",
      "",
    ].join("\n");
    const result = spawnSync(
      "pwsh",
      ["-NoProfile", "-File", bootstrapPath],
      {
        cwd: workingDirectory,
        encoding: "utf8",
        input,
        timeout: 30_000,
      },
    );
    const output = `${result.stdout}\n${result.stderr}`;

    assert.equal(result.status, 0, output);
    assert.match(output, /Release\/Tag\s+:/);
    assert.match(output, /Commit ID\s+:/);
    assert.match(output, /Channel\s+:/);
    assert.match(output, /React \+ Hono \(available\)/);
    assert.match(output, /React \+ Hono \+ Spring Boot is Coming soon/);
    assert.match(output, /Web API: Spring Boot is Coming soon/);
    assert.match(output, /Unknown selection 'invalid'/);
    assert.match(output, /Blueprint ID\s+: web-hono/);
    assert.match(output, /GitHub\s+: skipped/);
    assert.match(output, /pnpm run typecheck/);
    assert.match(output, /Cancelled\./);
    await assert.rejects(access(destination));
  } finally {
    await rm(workingDirectory, { recursive: true, force: true });
  }
});

test("non-interactive mode rejects an unavailable blueprint before generation", async () => {
  const workingDirectory = await mkdtemp(
    path.join(tmpdir(), "ibuki-blueprint-test-"),
  );
  const destination = path.join(workingDirectory, "not-created");

  try {
    const result = spawnSync(
      "pwsh",
      [
        "-NoProfile",
        "-File",
        bootstrapPath,
        "-Yes",
        "-Destination",
        destination,
        "-ProjectId",
        "unavailable-blueprint",
        "-SkipGitHub",
        "-NonInteractive",
        "-Blueprint",
        "spring-boot",
      ],
      {
        cwd: workingDirectory,
        encoding: "utf8",
        timeout: 30_000,
      },
    );
    const output = `${result.stdout}\n${result.stderr}`;

    assert.notEqual(result.status, 0);
    assert.match(output, /Blueprint 'spring-boot' is not available/);
    await assert.rejects(access(destination));
  } finally {
    await rm(workingDirectory, { recursive: true, force: true });
  }
});

test("destination paths longer than 96 characters are rejected before generation", async () => {
  const workingDirectory = await mkdtemp(
    path.join(tmpdir(), "ibuki-long-path-test-"),
  );
  const destination = path.join(workingDirectory, "x".repeat(150));

  try {
    const result = spawnSync(
      "pwsh",
      [
        "-NoProfile",
        "-File",
        bootstrapPath,
        "-ProjectId",
        "long-path-test",
        "-Destination",
        destination,
        "-SkipGitHub",
        "-NonInteractive",
        "-Yes",
      ],
      {
        cwd: workingDirectory,
        encoding: "utf8",
        timeout: 30_000,
      },
    );
    const output = `${result.stdout}\n${result.stderr}`;

    assert.notEqual(result.status, 0);
    assert.match(output, /Destination path is too long/);
    assert.match(output, /maximum 96/);
    assert.match(output, /Choose a shorter destination/);
    assert.doesNotMatch(output, /\[Confirmation\]/);
    assert.doesNotMatch(output, /\[Generate\]/);
    await assert.rejects(access(destination));
  } finally {
    await rm(workingDirectory, { recursive: true, force: true });
  }
});

test("interactive wizard can cancel after a Coming soon choice", async () => {
  const workingDirectory = await mkdtemp(
    path.join(tmpdir(), "ibuki-wizard-cancel-test-"),
  );

  try {
    const result = spawnSync(
      "pwsh",
      ["-NoProfile", "-File", bootstrapPath],
      {
        cwd: workingDirectory,
        encoding: "utf8",
        input: "4\nq\n",
        timeout: 30_000,
      },
    );
    const output = `${result.stdout}\n${result.stderr}`;

    assert.equal(result.status, 0, output);
    assert.match(output, /Android: Jetpack Compose is Coming soon/);
    assert.match(output, /\[0\] Cancel/);
    assert.match(output, /Cancelled\./);
  } finally {
    await rm(workingDirectory, { recursive: true, force: true });
  }
});

test("interactive wizard defaults a whitespace-only display name", async () => {
  const workingDirectory = await mkdtemp(
    path.join(tmpdir(), "ibuki-display-name-test-"),
  );
  const projectId = `ibuki-display-name-${process.pid}`;
  const destination = path.join(workingDirectory, projectId);

  try {
    const result = spawnSync(
      "pwsh",
      ["-NoProfile", "-File", bootstrapPath],
      {
        cwd: workingDirectory,
        encoding: "utf8",
        input: `1\n${projectId}\n   \n\nn\nn\n`,
        timeout: 30_000,
      },
    );
    const output = `${result.stdout}\n${result.stderr}`;

    assert.equal(result.status, 0, output);
    assert.match(output, new RegExp(`Display name\\s+: ${projectId}`));
    assert.match(output, /Cancelled\./);
    assert.doesNotMatch(output, /\[Generate\]/);
    await assert.rejects(access(destination));
  } finally {
    await rm(workingDirectory, { recursive: true, force: true });
  }
});

test("GitHub choice EOF cancels before authentication or file creation", async () => {
  const workingDirectory = await mkdtemp(
    path.join(tmpdir(), "ibuki-github-eof-test-"),
  );
  const projectId = `ibuki-github-eof-${process.pid}`;
  const destination = path.join(workingDirectory, projectId);

  try {
    const result = spawnSync(
      "pwsh",
      ["-NoProfile", "-File", bootstrapPath],
      {
        cwd: workingDirectory,
        encoding: "utf8",
        input: `1\n${projectId}\n\n\n`,
        timeout: 30_000,
      },
    );
    const output = `${result.stdout}\n${result.stderr}`;

    assert.equal(result.status, 0, output);
    assert.match(output, /Cancelled\./);
    assert.doesNotMatch(output, /\[Confirmation\]/);
    assert.doesNotMatch(output, /\[OK\] gh/);
    assert.doesNotMatch(output, /\[Generate\]/);
    await assert.rejects(access(destination));
  } finally {
    await rm(workingDirectory, { recursive: true, force: true });
  }
});

test("confirmation EOF cancels without creating files", async () => {
  const workingDirectory = await mkdtemp(
    path.join(tmpdir(), "ibuki-confirm-eof-test-"),
  );
  const projectId = `ibuki-confirm-eof-${process.pid}`;
  const destination = path.join(workingDirectory, projectId);

  try {
    const result = spawnSync(
      "pwsh",
      ["-NoProfile", "-File", bootstrapPath],
      {
        cwd: workingDirectory,
        encoding: "utf8",
        input: `1\n${projectId}\n\n\nn\n`,
        timeout: 30_000,
      },
    );
    const output = `${result.stdout}\n${result.stderr}`;

    assert.equal(result.status, 0, output);
    assert.match(output, /\[Confirmation\]/);
    assert.match(output, /Cancelled\./);
    assert.doesNotMatch(output, /\[Generate\]/);
    await assert.rejects(access(destination));
  } finally {
    await rm(workingDirectory, { recursive: true, force: true });
  }
});

test("destination is rechecked after confirmation and before the first write", async () => {
  const bootstrap = await import("node:fs/promises").then(({ readFile }) =>
    readFile(bootstrapPath, "utf8"),
  );
  const confirmationIndex = bootstrap.indexOf(
    'Confirm-Action -Prompt "Generate this project?"',
  );
  const recheckIndex = bootstrap.indexOf(
    "Destination changed after confirmation",
  );
  const firstWriteIndex = bootstrap.indexOf(
    "New-Item -ItemType Directory -Path $Destination",
  );

  assert.ok(confirmationIndex >= 0);
  assert.ok(recheckIndex > confirmationIndex);
  assert.ok(firstWriteIndex > recheckIndex);
});

test("manifest entries are fully validated before the first generated write", async () => {
  const bootstrap = await import("node:fs/promises").then(({ readFile }) =>
    readFile(bootstrapPath, "utf8"),
  );
  const validatorIndex = bootstrap.indexOf("function Assert-BlueprintManifest");
  const validatorCallIndex = bootstrap.lastIndexOf("Assert-BlueprintManifest");
  const firstWriteIndex = bootstrap.indexOf(
    "New-Item -ItemType Directory -Path $Destination",
  );

  assert.ok(validatorIndex >= 0);
  assert.match(bootstrap, /contains an unsafe source path/);
  assert.match(bootstrap, /contains an unsafe target path/);
  assert.match(bootstrap, /contains a duplicate target/);
  assert.match(bootstrap, /has a non-boolean template flag/);
  assert.match(bootstrap, /source -isnot \[string\]/);
  assert.match(bootstrap, /canonicalTarget/);
  assert.match(bootstrap, /if \(\$UseLocalBlueprint\)/);
  assert.ok(validatorCallIndex > validatorIndex);
  assert.ok(firstWriteIndex > validatorCallIndex);
});

test("file generation uses atomic create-new writes and rejects reparse points", async () => {
  const bootstrap = await import("node:fs/promises").then(({ readFile }) =>
    readFile(bootstrapPath, "utf8"),
  );

  assert.match(bootstrap, /\[System\.IO\.FileMode\]::CreateNew/);
  assert.match(bootstrap, /function Assert-NoReparsePoint/);
  assert.match(bootstrap, /Refusing to generate through a reparse point/);
});

test("local and remote blueprint content paths are explicitly separated", async () => {
  const bootstrap = await import("node:fs/promises").then(({ readFile }) =>
    readFile(bootstrapPath, "utf8"),
  );

  assert.match(bootstrap, /if \(\$UseLocalBlueprint\)/);
  assert.match(bootstrap, /is missing its manifest source/);
  assert.match(bootstrap, /-UseLocalBlueprint:\$useLocalBlueprint/);
  assert.equal(bootstrap.includes(".ibuki-remote-source"), false);
});

test("PowerShell, Node.js, and pnpm minimum versions are explicitly enforced", async () => {
  const bootstrap = await import("node:fs/promises").then(({ readFile }) =>
    readFile(bootstrapPath, "utf8"),
  );

  assert.match(bootstrap, /PSVersionTable\.PSVersion -lt \[version\]"7\.6"/);
  assert.match(
    bootstrap,
    /nodeSemanticVersion -lt \[version\]"24\.10\.0"/,
  );
  assert.match(bootstrap, /pnpmMajor -lt 11/);
});
