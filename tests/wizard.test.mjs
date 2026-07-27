import assert from "node:assert/strict";
import { access, mkdtemp, readdir, readFile, rm } from "node:fs/promises";
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

async function readTreeBytes(root, relative = "") {
  const entries = await readdir(path.join(root, relative), {
    withFileTypes: true,
  });
  const files = new Map();

  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    const childRelative = path.join(relative, entry.name);

    if (entry.isDirectory()) {
      const childFiles = await readTreeBytes(root, childRelative);
      for (const [name, bytes] of childFiles) files.set(name, bytes);
    } else {
      files.set(childRelative.replaceAll("\\", "/"), await readFile(path.join(root, childRelative)));
    }
  }

  return files;
}

for (const configuration of [
  { blueprint: "web-hono", menuChoice: "1" },
  {
    blueprint: "api-spring",
    menuChoice: "3",
    basePackage: "net.rukaruka966.modeparity",
  },
  {
    blueprint: "api-spring-postgres",
    menuChoice: "4",
    basePackage: "net.rukaruka966.modeparity",
  },
]) {
  test(`${configuration.blueprint}: interactive and non-interactive generation produce identical paths and bytes`, async () => {
    const workingDirectory = await mkdtemp(
      path.join(tmpdir(), "ibuki-mode-parity-"),
    );
    const projectId = "mode-parity";
    const interactiveDestination = path.join(workingDirectory, projectId);
    const nonInteractiveDestination = path.join(
      workingDirectory,
      "noninteractive",
    );
    const displayName = "Mode parity __PROJECT_ID__";

    try {
      const interactiveInput = [
        configuration.menuChoice,
        projectId,
        displayName,
      ];
      if (configuration.basePackage) {
        interactiveInput.push(configuration.basePackage);
      }
      interactiveInput.push("1", "n", "y", "");

      const interactive = spawnSync(
        "pwsh",
        ["-NoProfile", "-File", bootstrapPath],
        {
          cwd: workingDirectory,
          encoding: "utf8",
          input: interactiveInput.join("\n"),
          timeout: 30_000,
        },
      );
      const nonInteractiveArguments = [
        "-NoProfile",
        "-File",
        bootstrapPath,
        "-Blueprint",
        configuration.blueprint,
        "-ProjectId",
        projectId,
        "-DisplayName",
        displayName,
      ];
      if (configuration.basePackage) {
        nonInteractiveArguments.push(
          "-BasePackage",
          configuration.basePackage,
        );
      }
      nonInteractiveArguments.push(
        "-Destination",
        nonInteractiveDestination,
        "-SkipGitHub",
        "-NonInteractive",
        "-Yes",
      );
      const nonInteractive = spawnSync("pwsh", nonInteractiveArguments, {
        cwd: workingDirectory,
        encoding: "utf8",
        timeout: 30_000,
      });

      assert.equal(
        interactive.status,
        0,
        `${interactive.stdout}\n${interactive.stderr}`,
      );
      assert.equal(
        nonInteractive.status,
        0,
        `${nonInteractive.stdout}\n${nonInteractive.stderr}`,
      );

      const interactiveTree = await readTreeBytes(interactiveDestination);
      const nonInteractiveTree = await readTreeBytes(nonInteractiveDestination);
      assert.deepEqual(
        [...interactiveTree.keys()],
        [...nonInteractiveTree.keys()],
      );

      for (const [name, bytes] of interactiveTree) {
        assert.deepEqual(bytes, nonInteractiveTree.get(name), name);
      }
    } finally {
      await rm(workingDirectory, { recursive: true, force: true });
    }
  });
}

test("interactive wizard returns from unavailable choices and cancels safely", async () => {
  const workingDirectory = await mkdtemp(
    path.join(tmpdir(), "ibuki-wizard-test-"),
  );
  const projectId = `ibuki-wizard-${process.pid}`;
  const destination = path.join(workingDirectory, projectId);

  try {
    const input = [
      "2",
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
    assert.match(output, /Web API: Spring Boot \(available\)/);
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

test("api-spring generation does not inspect JDK and repeats unexecuted checks at completion", async () => {
  const workingDirectory = await mkdtemp(
    path.join(tmpdir(), "ibuki-java-home-test-"),
  );
  const destination = path.join(workingDirectory, "generated-api");

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
        "java-home-test",
        "-SkipGitHub",
        "-NonInteractive",
        "-Blueprint",
        "api-spring",
      ],
      {
        cwd: workingDirectory,
        encoding: "utf8",
        env: {
          ...process.env,
          JAVA_HOME: path.join(workingDirectory, "different-jdk"),
        },
        timeout: 30_000,
      },
    );
    const output = `${result.stdout}\n${result.stderr}`;

    assert.equal(result.status, 0, output);
    assert.match(output, /Project created successfully\./);
    assert.match(
      output,
      /java\s+: major version 17 required \(minimum 17\.0\.0\)/,
    );
    assert.match(
      output,
      /javac\s+: major version 17 required \(minimum 17\.0\.0\)/,
    );
    assert.doesNotMatch(output, /java\s+: >= 17\.0\.0/);
    assert.match(output, /Next\s+: Set-Location -LiteralPath/);
    assert.match(output, /Project-owned checks below were not run by Ibuki:/);
    assert.match(output, /Base package\s+: net\.rukaruka966\.javahometest/);
    assert.match(output, /\[systems\/api-server\] \.\/gradlew\.bat check/);
    assert.match(output, /\[systems\/api-server\] \.\/gradlew\.bat bootJar/);
    await access(path.join(destination, "systems", "api-server", "build.gradle.kts"));
  } finally {
    await rm(workingDirectory, { recursive: true, force: true });
  }
});

test("Base Package validation is conditional on Spring Blueprints", async () => {
  const workingDirectory = await mkdtemp(
    path.join(tmpdir(), "ibuki-base-package-test-"),
  );

  try {
    const invalidSpringDestination = path.join(workingDirectory, "invalid-spring");
    const invalidSpring = spawnSync(
      "pwsh",
      [
        "-NoProfile",
        "-File",
        bootstrapPath,
        "-Blueprint",
        "api-spring-postgres",
        "-ProjectId",
        "invalid-package",
        "-BasePackage",
        "net.rukaruka966.bad/package",
        "-Destination",
        invalidSpringDestination,
        "-SkipGitHub",
        "-NonInteractive",
        "-Yes",
      ],
      { cwd: workingDirectory, encoding: "utf8", timeout: 30_000 },
    );
    assert.notEqual(invalidSpring.status, 0);
    assert.match(
      `${invalidSpring.stdout}\n${invalidSpring.stderr}`,
      /Base package must contain/,
    );
    await assert.rejects(access(invalidSpringDestination));

    const webDestination = path.join(workingDirectory, "invalid-web");
    const invalidWeb = spawnSync(
      "pwsh",
      [
        "-NoProfile",
        "-File",
        bootstrapPath,
        "-Blueprint",
        "web-hono",
        "-ProjectId",
        "invalid-web-package",
        "-BasePackage",
        "net.rukaruka966.web",
        "-Destination",
        webDestination,
        "-SkipGitHub",
        "-NonInteractive",
        "-Yes",
      ],
      { cwd: workingDirectory, encoding: "utf8", timeout: 30_000 },
    );
    assert.notEqual(invalidWeb.status, 0);
    assert.match(
      `${invalidWeb.stdout}\n${invalidWeb.stderr}`,
      /-BasePackage can only be used with a Spring Blueprint/,
    );
    await assert.rejects(access(webDestination));
  } finally {
    await rm(workingDirectory, { recursive: true, force: true });
  }
});

test("normalized Project IDs produce safe deterministic default Base Packages", async () => {
  const workingDirectory = await mkdtemp(
    path.join(tmpdir(), "ibuki-reserved-package-test-"),
  );

  try {
    for (const [projectId, normalizedSegment] of [
      ["class", "classapp"],
      ["object", "objectapp"],
      ["when", "whenapp"],
      ["data", "dataapp"],
      ["co-n", "conapp"],
      ["co-m1", "com1app"],
      ["lp-t1", "lpt1app"],
    ]) {
      const destination = path.join(workingDirectory, projectId);
      const result = spawnSync(
        "pwsh",
        [
          "-NoProfile",
          "-File",
          bootstrapPath,
          "-Blueprint",
          "api-spring-postgres",
          "-ProjectId",
          projectId,
          "-Destination",
          destination,
          "-SkipGitHub",
          "-NonInteractive",
          "-Yes",
        ],
        { cwd: workingDirectory, encoding: "utf8", timeout: 30_000 },
      );
      const output = `${result.stdout}\n${result.stderr}`;
      const expectedPackage = `net.rukaruka966.${normalizedSegment}`;

      assert.equal(result.status, 0, output);
      assert.match(
        output,
        new RegExp(`Base package\\s+: ${expectedPackage.replaceAll(".", "\\.")}`),
      );
      await access(
        path.join(
          destination,
          "systems",
          "api-server",
          "src",
          "main",
          "kotlin",
          ...expectedPackage.split("."),
          "Application.kt",
        ),
      );
    }
  } finally {
    await rm(workingDirectory, { recursive: true, force: true });
  }
});

test("Windows device names are rejected during Project ID and Base Package validation", async () => {
  const workingDirectory = await mkdtemp(
    path.join(tmpdir(), "ibuki-device-name-test-"),
  );

  try {
    for (const projectId of ["con", "com1", "lpt1"]) {
      const destination = path.join(workingDirectory, `project-${projectId}`);
      const result = spawnSync(
        "pwsh",
        [
          "-NoProfile",
          "-File",
          bootstrapPath,
          "-ProjectId",
          projectId,
          "-Destination",
          destination,
          "-SkipGitHub",
          "-NonInteractive",
          "-Yes",
        ],
        { cwd: workingDirectory, encoding: "utf8", timeout: 30_000 },
      );
      const output = `${result.stdout}\n${result.stderr}`;

      assert.notEqual(result.status, 0, output);
      assert.match(output, /reserved Windows device name/);
      await assert.rejects(access(destination));
    }

    for (const deviceSegment of ["con", "com1", "lpt1"]) {
      const destination = path.join(workingDirectory, `package-${deviceSegment}`);
      const result = spawnSync(
        "pwsh",
        [
          "-NoProfile",
          "-File",
          bootstrapPath,
          "-Blueprint",
          "api-spring-postgres",
          "-ProjectId",
          `package-${deviceSegment}`,
          "-BasePackage",
          `net.rukaruka966.${deviceSegment}`,
          "-Destination",
          destination,
          "-SkipGitHub",
          "-NonInteractive",
          "-Yes",
        ],
        { cwd: workingDirectory, encoding: "utf8", timeout: 30_000 },
      );
      const output = `${result.stdout}\n${result.stderr}`;

      assert.notEqual(result.status, 0, output);
      assert.match(output, /reserved Windows device name/);
      await assert.rejects(access(destination));
    }
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
        input: "5\nq\n",
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
  assert.match(bootstrap, /unsafe \$Label path/);
  assert.match(bootstrap, /Assert-SafeBlueprintRelativePath/);
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

test("only PowerShell is enforced while project requirements are informational", async () => {
  const bootstrap = await import("node:fs/promises").then(({ readFile }) =>
    readFile(bootstrapPath, "utf8"),
  );
  const webManifest = JSON.parse(
    await import("node:fs/promises").then(({ readFile }) =>
      readFile(
        path.join(repositoryRoot, "blueprints", "web-hono", "manifest.json"),
        "utf8",
      ),
    ),
  );
  const springManifest = JSON.parse(
    await import("node:fs/promises").then(({ readFile }) =>
      readFile(
        path.join(repositoryRoot, "blueprints", "api-spring", "manifest.json"),
        "utf8",
      ),
    ),
  );

  assert.match(bootstrap, /PSVersionTable\.PSVersion -lt \[version\]"7\.6"/);
  assert.doesNotMatch(bootstrap, /function Assert-BlueprintToolchains/);
  assert.match(
    bootstrap,
    /foreach \(\$step in @\(\$manifest\.recommendedCommands\)\)/,
  );
  assert.doesNotMatch(bootstrap, /-FilePath \$step\.command/);
  assert.deepEqual(
    webManifest.projectRequirements.map(({ id, minimumVersion }) => [
      id,
      minimumVersion,
    ]),
    [
      ["node", "24.10.0"],
      ["pnpm", "11.0.0"],
    ],
  );
  assert.deepEqual(
    springManifest.projectRequirements.map(({ id, minimumVersion, requiredMajor }) => [
      id,
      minimumVersion,
      requiredMajor,
    ]),
    [
      ["java", "17.0.0", 17],
      ["javac", "17.0.0", 17],
    ],
  );
});
