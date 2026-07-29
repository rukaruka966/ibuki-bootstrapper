import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import {
  access,
  copyFile,
  mkdtemp,
  mkdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { analyzeCommits } from "@semantic-release/commit-analyzer";
import { generateNotes } from "@semantic-release/release-notes-generator";
import releaseConfig from "../release.config.mjs";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const bootstrapPath = path.join(repositoryRoot, "bootstrap.ps1");
const powerShellPath = spawnSync(
  process.platform === "win32" ? "where.exe" : "which",
  ["pwsh"],
  { encoding: "utf8" },
).stdout
  .trim()
  .split(/\r?\n/)[0];
const silentLogger = {
  log() {},
};

function getPluginConfiguration(name) {
  const plugin = releaseConfig.plugins.find((candidate) => {
    const pluginName = Array.isArray(candidate) ? candidate[0] : candidate;
    return pluginName === name;
  });

  assert.notEqual(plugin, undefined, `missing plugin: ${name}`);
  return Array.isArray(plugin) ? plugin[1] : {};
}

async function getReleaseType(message) {
  return analyzeCommits(
    getPluginConfiguration("@semantic-release/commit-analyzer"),
    {
      commits: [{ hash: "1234567890abcdef", message }],
      cwd: repositoryRoot,
      logger: silentLogger,
    },
  );
}

function runWithMockedGitHubApi({
  mainCommit,
  releaseCommit,
  releaseTag = "v0.3.0",
  fail = false,
  rateLimited = false,
  ghFallback = false,
  ghReleaseFail = false,
  ghAvailable = true,
  hideGitHubCli = false,
  input = "q\n",
}) {
  const escapedBootstrapPath = bootstrapPath.replaceAll("'", "''");
  const mockBody = rateLimited
    ? `
      $exception = [System.Exception]::new("GitHub API rate limit exceeded")
      $exception.Data["StatusCode"] = 403
      $exception.Data["RateLimitRemaining"] = "0"
      $exception.Data["RateLimitReset"] = "1785163531"
      throw $exception
    `
    : fail
      ? 'throw "GitHub API unavailable"'
    : `
      if ($Uri -like "*/commits/main") {
          return [PSCustomObject]@{ sha = "${mainCommit}" }
      }
      if ($Uri -like "*/releases/latest") {
          return [PSCustomObject]@{ tag_name = "${releaseTag}" }
      }
      if ($Uri -like "*/commits/*") {
          return [PSCustomObject]@{ sha = "${releaseCommit}" }
      }
      throw "Unexpected URI: $Uri"
    `;
  const mockGitHubCli = ghAvailable ? `
    function gh {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [object[]]$Arguments
        )

        if (-not $${ghFallback}) {
            Write-Error "gho_test_secret_must_not_leak" -ErrorAction Continue
            $global:LASTEXITCODE = 1
            return
        }

        $endpoint = [string]$Arguments[-1]
        $global:LASTEXITCODE = 0

        if ($${ghReleaseFail} -and $endpoint -like "*/releases/latest") {
            $global:LASTEXITCODE = 1
            return
        }
        if ($endpoint -like "*/commits/main") {
            return '{"sha":"${mainCommit}"}'
        }
        if ($endpoint -like "*/releases/latest") {
            return '{"tag_name":"${releaseTag}"}'
        }
        if ($endpoint -like "*/commits/*") {
            return '{"sha":"${releaseCommit}"}'
        }

        $global:LASTEXITCODE = 1
    }
  ` : "";
  const command = `
    function Invoke-RestMethod {
        param([string]$Uri, [hashtable]$Headers)
        ${mockBody}
    }
    ${mockGitHubCli}
    Invoke-Expression (Get-Content -Raw -LiteralPath '${escapedBootstrapPath}')
  `;

  const environment = hideGitHubCli
    ? Object.fromEntries(
      Object.entries(process.env)
        .filter(([name]) => name.toLowerCase() !== "path"),
    )
    : process.env;
  if (hideGitHubCli) {
    environment.PATH = "";
  }

  return spawnSync(powerShellPath, ["-NoProfile", "-Command", command], {
    cwd: repositoryRoot,
    encoding: "utf8",
    env: environment,
    input,
    timeout: 30_000,
  });
}

test("standalone script ignores an unrelated repository HEAD", async () => {
  const fixture = await mkdtemp(path.join(os.tmpdir(), "ibuki-standalone-"));
  const fixtureBootstrap = path.join(fixture, "bootstrap.ps1");
  const remoteCommit = "1234567890abcdef1234567890abcdef12345678";
  const runGit = (...arguments_) => {
    const result = spawnSync(
      "git",
      [
        "-c",
        "user.name=Unrelated Test",
        "-c",
        "user.email=unrelated@example.invalid",
        ...arguments_,
      ],
      { cwd: fixture, encoding: "utf8" },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    return result.stdout.trim();
  };

  try {
    await copyFile(bootstrapPath, fixtureBootstrap);
    await writeFile(path.join(fixture, "unrelated.txt"), "not Ibuki\n", "utf8");
    runGit("init", "-b", "main");
    runGit("add", "unrelated.txt");
    runGit("commit", "-m", "chore: unrelated repository");
    const unrelatedCommit = runGit("rev-parse", "HEAD");
    const escapedBootstrap = fixtureBootstrap.replaceAll("'", "''");
    const command = `
      function Invoke-RestMethod {
          param([string]$Uri, [hashtable]$Headers)
          if ($Uri -like "*/commits/main") {
              return [PSCustomObject]@{ sha = "${remoteCommit}" }
          }
          if ($Uri -like "*/releases/latest") {
              return [PSCustomObject]@{ tag_name = "v0.5.0" }
          }
          if ($Uri -like "*/commits/*") {
              return [PSCustomObject]@{ sha = "${remoteCommit}" }
          }
          throw "Unexpected URI: $Uri"
      }
      & '${escapedBootstrap}'
    `;
    const result = spawnSync("pwsh", ["-NoProfile", "-Command", command], {
      cwd: fixture,
      encoding: "utf8",
      input: "q\n",
      timeout: 30_000,
    });
    const output = `${result.stdout}\n${result.stderr}`;

    assert.equal(result.status, 0, output);
    assert.match(output, /Commit ID\s+: 1234567890ab/);
    assert.doesNotMatch(output, new RegExp(unrelatedCommit.slice(0, 12)));
    assert.match(output, /Release\/Tag : v0\.5\.0/);
    assert.match(output, /Cancelled\./);
  } finally {
    await rm(fixture, { recursive: true, force: true });
  }
});

test("standalone generation succeeds without a previous release tag", async () => {
  const fixture = await mkdtemp(path.join(os.tmpdir(), "ibuki-no-tag-"));
  const fixtureBootstrap = path.join(fixture, "bootstrap.ps1");
  const blueprintRoot = path.join(fixture, "blueprints", "web-hono");
  const templateRoot = path.join(blueprintRoot, "template");
  const destination = path.join(fixture, "generated");
  const runGit = (...arguments_) =>
    spawnSync(
      "git",
      [
        "-c",
        "user.name=No Tag Test",
        "-c",
        "user.email=no-tag@example.invalid",
        ...arguments_,
      ],
      { cwd: fixture, encoding: "utf8" },
    );

  try {
    await copyFile(bootstrapPath, fixtureBootstrap);
    await mkdir(templateRoot, { recursive: true });
    await writeFile(
      path.join(blueprintRoot, "manifest.json"),
      `${JSON.stringify(
        {
          schemaVersion: 5,
          id: "web-hono",
          version: "0.0.0",
          displayName: "No Tag Test",
          projectRequirements: [],
          recommendedCommands: [],
          fileSets: [],
          files: [
            {
              kind: "text",
              source: "template/README.md.tpl",
              target: "README.md",
              template: true,
            },
          ],
        },
        null,
        2,
      )}\n`,
      "utf8",
    );
    await writeFile(
      path.join(templateRoot, "README.md.tpl"),
      "# __PROJECT_DISPLAY_NAME__\n",
      "utf8",
    );

    assert.equal(runGit("init", "-b", "main").status, 0);
    assert.equal(runGit("add", "--all").status, 0);
    assert.equal(runGit("commit", "-m", "chore: add no-tag fixture").status, 0);

    const result = spawnSync(
      "pwsh",
      [
        "-NoProfile",
        "-File",
        fixtureBootstrap,
        "-Blueprint",
        "web-hono",
        "-ProjectId",
        "no-tag-test",
        "-DisplayName",
        "No Tag Test",
        "-Destination",
        destination,
        "-SkipGitHub",
        "-NonInteractive",
        "-Yes",
      ],
      {
        cwd: fixture,
        encoding: "utf8",
        timeout: 30_000,
      },
    );
    const output = `${result.stdout}\n${result.stderr}`;

    assert.equal(result.status, 0, output);
    assert.match(output, /Release\/Tag : Unreleased \(no previous tag\)/);
    assert.match(output, /Project created successfully/);
    await access(path.join(destination, "README.md"));
  } finally {
    await rm(fixture, { recursive: true, force: true });
  }
});

test("local generation rejects dirty Bootstrapper provenance before writing", async () => {
  const fixture = await mkdtemp(path.join(os.tmpdir(), "ibuki-dirty-source-"));
  const fixtureBootstrap = path.join(fixture, "bootstrap.ps1");
  const blueprintRoot = path.join(fixture, "blueprints", "web-hono");
  const templateRoot = path.join(blueprintRoot, "template");
  const templateRelativePath = "blueprints/web-hono/template/README.md.tpl";
  const templatePath = path.join(fixture, ...templateRelativePath.split("/"));
  const destination = path.join(fixture, "generated");
  const hiddenDestination = path.join(fixture, "generated-hidden-dirty");
  const runGit = (...arguments_) =>
    spawnSync(
      "git",
      [
        "-c",
        "user.name=Dirty Source Test",
        "-c",
        "user.email=dirty-source@example.invalid",
        "-c",
        "commit.gpgSign=false",
        "-c",
        "tag.gpgSign=false",
        ...arguments_,
      ],
      { cwd: fixture, encoding: "utf8" },
    );
  const runBootstrap = (outputDirectory) =>
    spawnSync(
      "pwsh",
      [
        "-NoProfile",
        "-File",
        fixtureBootstrap,
        "-Blueprint",
        "web-hono",
        "-ProjectId",
        "dirty-source-test",
        "-DisplayName",
        "Dirty Source Test",
        "-Destination",
        outputDirectory,
        "-SkipGitHub",
        "-NonInteractive",
        "-Yes",
      ],
      {
        cwd: fixture,
        encoding: "utf8",
        timeout: 30_000,
      },
    );

  try {
    await copyFile(bootstrapPath, fixtureBootstrap);
    await mkdir(templateRoot, { recursive: true });
    await writeFile(
      path.join(blueprintRoot, "manifest.json"),
      `${JSON.stringify(
        {
          schemaVersion: 5,
          id: "web-hono",
          version: "0.0.0",
          displayName: "Dirty Source Test",
          projectRequirements: [],
          recommendedCommands: [],
          fileSets: [],
          files: [
            {
              kind: "text",
              source: "template/README.md.tpl",
              target: "README.md",
              template: true,
            },
          ],
        },
        null,
        2,
      )}\n`,
      "utf8",
    );
    await writeFile(templatePath, "# __PROJECT_DISPLAY_NAME__\n", "utf8");

    assert.equal(runGit("init", "-b", "main", "--object-format=sha1").status, 0);
    assert.equal(runGit("add", "--all").status, 0);
    assert.equal(runGit("commit", "-m", "test: add clean source").status, 0);
    assert.equal(runGit("tag", "v0.1.0").status, 0);
    await writeFile(templatePath, "# Dirty __PROJECT_DISPLAY_NAME__\n", "utf8");

    const result = runBootstrap(destination);
    const output = `${result.stdout}\n${result.stderr}`;

    assert.notEqual(result.status, 0, output);
    assert.match(output, /requires a clean Bootstrapper working tree/);
    await assert.rejects(access(destination), { code: "ENOENT" });

    assert.equal(runGit("restore", "--", templateRelativePath).status, 0);
    assert.equal(
      runGit("update-index", "--assume-unchanged", templateRelativePath).status,
      0,
    );
    await writeFile(templatePath, "# Hidden dirty content\n", "utf8");
    assert.equal(runGit("status", "--porcelain").stdout.trim(), "");

    const hiddenResult = runBootstrap(hiddenDestination);
    const hiddenOutput = `${hiddenResult.stdout}\n${hiddenResult.stderr}`;
    assert.notEqual(hiddenResult.status, 0, hiddenOutput);
    assert.match(hiddenOutput, /differs from the recorded Bootstrapper commit/);
    await assert.rejects(access(hiddenDestination), { code: "ENOENT" });
  } finally {
    await rm(fixture, { recursive: true, force: true });
  }
});

test("local generation rejects a clean Commit switch during execution", async () => {
  const fixture = await mkdtemp(path.join(os.tmpdir(), "ibuki-commit-switch-"));
  const fixtureBootstrap = path.join(fixture, "bootstrap.ps1");
  const templateRoot = path.join(
    fixture,
    "blueprints",
    "web-hono",
    "template",
  );
  const templatePath = path.join(templateRoot, "README.md.tpl");
  const destination = path.join(fixture, "commit-switch");
  const replaceDestination = path.join(fixture, "replace-generated");
  const runGit = (...arguments_) =>
    spawnSync(
      "git",
      [
        "-c",
        "user.name=Commit Switch Test",
        "-c",
        "user.email=commit-switch@example.invalid",
        "-c",
        "commit.gpgSign=false",
        "-c",
        "tag.gpgSign=false",
        ...arguments_,
      ],
      { cwd: fixture, encoding: "utf8" },
    );
  let child;
  let childClosed;

  try {
    await copyFile(bootstrapPath, fixtureBootstrap);
    await mkdir(templateRoot, { recursive: true });
    await writeFile(
      path.join(fixture, "blueprints", "web-hono", "manifest.json"),
      `${JSON.stringify(
        {
          schemaVersion: 5,
          id: "web-hono",
          version: "0.0.0",
          displayName: "Commit Switch Test",
          projectRequirements: [],
          recommendedCommands: [],
          fileSets: [],
          files: [
            {
              kind: "text",
              source: "template/README.md.tpl",
              target: "README.md",
              template: true,
            },
          ],
        },
        null,
        2,
      )}\n`,
      "utf8",
    );
    await writeFile(templatePath, "# Commit A\n", "utf8");
    assert.equal(
      runGit("init", "-b", "main", "--object-format=sha1").status,
      0,
    );
    assert.equal(runGit("add", "--all").status, 0);
    assert.equal(runGit("commit", "--no-verify", "-m", "test: add Commit A").status, 0);
    const commitA = runGit("rev-parse", "HEAD").stdout.trim();
    assert.equal(runGit("tag", "v0.1.0").status, 0);
    await writeFile(templatePath, "# Commit B\n", "utf8");
    assert.equal(runGit("add", "--all").status, 0);
    assert.equal(runGit("commit", "--no-verify", "-m", "test: add Commit B").status, 0);
    const commitB = runGit("rev-parse", "HEAD").stdout.trim();
    assert.equal(runGit("switch", "--detach", commitA).status, 0);

    child = spawn("pwsh", ["-NoProfile", "-File", fixtureBootstrap], {
      cwd: fixture,
      stdio: ["pipe", "pipe", "pipe"],
    });
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    let output = "";
    const closed = new Promise((resolve, reject) => {
      child.once("close", resolve);
      child.once("error", reject);
    });
    childClosed = closed;

    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        child.kill();
        reject(new Error(`Timed out waiting for the wizard prompt.\n${output}`));
      }, 30_000);
      const inspect = (chunk) => {
        output += chunk;

        if (output.includes("Select a project configuration:")) {
          clearTimeout(timeout);
          resolve();
        }
      };
      child.stdout.on("data", inspect);
      child.stderr.on("data", inspect);
      child.once("close", () => {
        if (!output.includes("Select a project configuration:")) {
          clearTimeout(timeout);
          reject(new Error(`Process exited before the wizard prompt.\n${output}`));
        }
      });
    });

    assert.equal(runGit("switch", "--detach", commitB).status, 0);
    child.stdin.end(
      ["1", "commit-switch", "Commit Switch", "1", "n", "y", ""].join("\n"),
    );
    const exitCode = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        child.kill();
        reject(new Error(`Timed out waiting for Commit switch rejection.\n${output}`));
      }, 30_000);
      closed.then(
        (code) => {
          clearTimeout(timeout);
          resolve(code);
        },
        (error) => {
          clearTimeout(timeout);
          reject(error);
        },
      );
    });

    assert.notEqual(exitCode, 0, output);
    assert.match(output, /same immutable Bootstrapper commit throughout execution/);
    await assert.rejects(access(destination), { code: "ENOENT" });

    assert.equal(runGit("replace", commitA, commitB).status, 0);
    assert.equal(runGit("switch", "--detach", commitA).status, 0);
    assert.equal(runGit("status", "--porcelain").stdout.trim(), "");
    const noReplaceStatus = runGit(
      "--no-replace-objects",
      "status",
      "--porcelain",
    );
    assert.equal(noReplaceStatus.status, 0);
    assert.notEqual(noReplaceStatus.stdout.trim(), "");

    const replaceResult = spawnSync(
      "pwsh",
      [
        "-NoProfile",
        "-File",
        fixtureBootstrap,
        "-Blueprint",
        "web-hono",
        "-ProjectId",
        "replace-generated",
        "-DisplayName",
        "Replace Generated",
        "-Destination",
        replaceDestination,
        "-SkipGitHub",
        "-NonInteractive",
        "-Yes",
      ],
      {
        cwd: fixture,
        encoding: "utf8",
        timeout: 30_000,
      },
    );
    const replaceOutput = `${replaceResult.stdout}\n${replaceResult.stderr}`;

    assert.notEqual(replaceResult.status, 0, replaceOutput);
    assert.match(replaceOutput, /requires a clean Bootstrapper working tree/);
    await assert.rejects(access(replaceDestination), { code: "ENOENT" });
  } finally {
    child?.kill();
    await childClosed?.catch(() => {});
    await rm(fixture, {
      recursive: true,
      force: true,
      maxRetries: 5,
      retryDelay: 100,
    });
  }
});

test("partial checkout displays remote metadata for a missing Blueprint", async () => {
  const fixture = await mkdtemp(path.join(os.tmpdir(), "ibuki-partial-"));
  const fixtureBootstrap = path.join(fixture, "bootstrap.ps1");
  const localBlueprint = path.join(fixture, "blueprints", "web-hono");
  const remoteCommit = "abcdef1234567890abcdef1234567890abcdef12";

  try {
    await copyFile(bootstrapPath, fixtureBootstrap);
    await mkdir(localBlueprint, { recursive: true });
    await writeFile(
      path.join(localBlueprint, "manifest.json"),
      '{"id":"web-hono"}\n',
      "utf8",
    );
    const git = (...arguments_) =>
      spawnSync(
        "git",
        [
          "-c",
          "user.name=Partial Test",
          "-c",
          "user.email=partial@example.invalid",
          ...arguments_,
        ],
        { cwd: fixture, encoding: "utf8" },
      );
    assert.equal(git("init", "-b", "main").status, 0);
    assert.equal(git("add", "--all").status, 0);
    assert.equal(git("commit", "-m", "chore: partial checkout").status, 0);
    assert.equal(git("tag", "v9.9.9").status, 0);
    const localCommit = git("rev-parse", "HEAD").stdout.trim();
    const escapedBootstrap = fixtureBootstrap.replaceAll("'", "''");
    const destination = path.join(fixture, "generated").replaceAll("'", "''");
    const command = `
      function Invoke-RestMethod {
          param([string]$Uri, [hashtable]$Headers)
          if ($Uri -like "*/commits/main") {
              return [PSCustomObject]@{ sha = "${remoteCommit}" }
          }
          if ($Uri -like "*/releases/latest") {
              return [PSCustomObject]@{ tag_name = "v0.5.0" }
          }
          if ($Uri -like "*/commits/*") {
              return [PSCustomObject]@{ sha = "${remoteCommit}" }
          }
          throw "Unexpected URI: $Uri"
      }
      & '${escapedBootstrap}' -Blueprint api-spring -ProjectId partial-test -DisplayName "Partial Test" -Destination '${destination}' -SkipGitHub -NonInteractive -Yes
    `;
    const child = spawn("pwsh", ["-NoProfile", "-Command", command], {
      cwd: fixture,
      stdio: ["ignore", "pipe", "pipe"],
    });
    const childClosed = new Promise((resolve) => child.once("close", resolve));
    let output = "";

    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        child.kill();
        reject(new Error(`Timed out waiting for remote metadata.\n${output}`));
      }, 30_000);
      const inspect = (chunk) => {
        output += chunk.toString();

        if (output.includes(remoteCommit.slice(0, 12))) {
          clearTimeout(timeout);
          child.kill();
          resolve();
        }
      };
      child.stdout.on("data", inspect);
      child.stderr.on("data", inspect);
      child.on("error", (error) => {
        clearTimeout(timeout);
        reject(error);
      });
      child.on("exit", () => {
        if (!output.includes(remoteCommit.slice(0, 12))) {
          clearTimeout(timeout);
          reject(new Error(`Process exited before remote metadata.\n${output}`));
        }
      });
    });
    await childClosed;

    assert.match(output, /Release\/Tag : v0\.5\.0/);
    assert.match(output, /Commit ID\s+: abcdef123456/);
    assert.doesNotMatch(output, /Release\/Tag : v9\.9\.9/);
    assert.doesNotMatch(output, new RegExp(localCommit.slice(0, 12)));
  } finally {
    await rm(fixture, { recursive: true, force: true });
  }
});

test("release configuration publishes only from main without source commits", () => {
  assert.deepEqual(releaseConfig.branches, ["main"]);
  assert.equal(releaseConfig.tagFormat, "v${version}");

  const pluginNames = releaseConfig.plugins.map((plugin) =>
    Array.isArray(plugin) ? plugin[0] : plugin,
  );
  assert.deepEqual(pluginNames, [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/github",
  ]);
  assert.equal(
    pluginNames.some((name) =>
      ["@semantic-release/changelog", "@semantic-release/git"].includes(name),
    ),
    false,
  );

  const githubOptions = getPluginConfiguration("@semantic-release/github");
  assert.equal(githubOptions.successComment, false);
  assert.equal(githubOptions.failComment, false);
  assert.equal(githubOptions.releasedLabels, false);
  assert.equal(
    githubOptions.releaseNameTemplate,
    "Ibuki Bootstrapper <%= nextRelease.gitTag %>",
  );
});

test("repository Node.js minimum supports semantic-release", async () => {
  const packageJson = JSON.parse(
    await readFile(path.join(repositoryRoot, "package.json"), "utf8"),
  );
  const semanticReleasePackage = JSON.parse(
    await readFile(
      path.join(
        repositoryRoot,
        "node_modules",
        "semantic-release",
        "package.json",
      ),
      "utf8",
    ),
  );

  assert.equal(packageJson.engines.node, ">=24.10.0");
  assert.match(semanticReleasePackage.engines.node, />= 24\.10\.0/);
});

test("Conventional Commits produce the expected release types", async () => {
  assert.equal(await getReleaseType("fix: correct metadata"), "patch");
  assert.equal(await getReleaseType("feat: automate releases"), "minor");
  assert.equal(await getReleaseType("docs: explain releases"), null);
  assert.equal(
    await getReleaseType(
      "feat: replace the manifest contract\n\n" +
        "BREAKING CHANGE: previous manifests are incompatible",
    ),
    "major",
  );
});

test("Conventional Commits produce feature and bug fix release notes", async () => {
  const packageJson = JSON.parse(
    await readFile(path.join(repositoryRoot, "package.json"), "utf8"),
  );
  assert.equal(
    packageJson.devDependencies["conventional-changelog-conventionalcommits"],
    "9.3.1",
  );

  const notes = await generateNotes(
    getPluginConfiguration("@semantic-release/release-notes-generator"),
    {
      commits: [
        {
          hash: "1234567890abcdef",
          message: "feat: add PostgreSQL Blueprint",
        },
        {
          hash: "abcdef1234567890",
          message: "fix: handle Windows device names",
        },
      ],
      cwd: repositoryRoot,
      lastRelease: {
        gitTag: "v0.6.0",
        version: "0.6.0",
      },
      nextRelease: {
        gitTag: "v0.7.0",
        version: "0.7.0",
      },
      options: {
        repositoryUrl:
          "https://github.com/rukaruka966/ibuki-bootstrapper.git",
      },
      logger: silentLogger,
    },
  );

  assert.match(notes, /### Features/);
  assert.match(notes, /add PostgreSQL Blueprint/);
  assert.match(notes, /### Bug Fixes/);
  assert.match(notes, /handle Windows device names/);
});

test("release analysis reads feature commits through a real no-ff merge", async () => {
  const gitRoot = await mkdtemp(path.join(os.tmpdir(), "ibuki-release-test-"));
  const runGit = (...arguments_) => {
    const result = spawnSync(
      "git",
      ["-c", "user.name=Ibuki Test", "-c", "user.email=ibuki@example.invalid", ...arguments_],
      { cwd: gitRoot, encoding: "utf8" },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    return result.stdout.trim();
  };

  try {
    runGit("init", "-b", "main");
    await writeFile(path.join(gitRoot, "fixture.txt"), "base\n", "utf8");
    runGit("add", "fixture.txt");
    runGit("commit", "-m", "chore: establish release baseline");
    runGit("tag", "v0.1.0");
    runGit("switch", "-c", "develop");
    await writeFile(path.join(gitRoot, "fixture.txt"), "base\nfeature\n", "utf8");
    runGit("add", "fixture.txt");
    runGit("commit", "-m", "feat: add generated policy");
    runGit("switch", "main");
    runGit("merge", "--no-ff", "develop", "-m", "Merge develop into main");

    const hashes = runGit("rev-list", "--reverse", "v0.1.0..HEAD")
      .split(/\r?\n/)
      .filter(Boolean);
    const commits = hashes.map((hash) => ({
      hash,
      message: runGit("show", "-s", "--format=%B", hash),
    }));
    const releaseType = await analyzeCommits(
      getPluginConfiguration("@semantic-release/commit-analyzer"),
      { commits, cwd: gitRoot, logger: silentLogger },
    );

    assert.equal(commits.length, 2);
    assert.match(commits.at(-1).message, /Merge develop into main/);
    assert.equal(releaseType, "minor");
  } finally {
    await rm(gitRoot, { recursive: true, force: true });
  }
});

test("release workflow waits for Quality and has minimal write permission", async () => {
  const workflow = await readFile(
    path.join(repositoryRoot, ".github", "workflows", "ci.yml"),
    "utf8",
  );

  assert.match(workflow, /release:\n\s+name: Release/);
  assert.match(workflow, /needs:\n\s+- quality/);
  assert.match(
    workflow,
    /if: github\.event_name == 'push' && github\.ref == 'refs\/heads\/main'/,
  );
  assert.match(workflow, /permissions:\n\s+contents: write/);
  assert.match(workflow, /group: release-\$\{\{ github\.ref \}\}/);
  assert.match(workflow, /fetch-depth: 0/);
  assert.match(workflow, /run: pnpm run release/);
});

test("Quality fetches release tags for generated project provenance", async () => {
  const workflow = await readFile(
    path.join(repositoryRoot, ".github", "workflows", "ci.yml"),
    "utf8",
  );
  const qualityStart = workflow.indexOf("  quality:");
  const releaseStart = workflow.indexOf("  release:");

  assert.ok(qualityStart >= 0);
  assert.ok(releaseStart > qualityStart);

  const qualityJob = workflow.slice(qualityStart, releaseStart);

  assert.match(qualityJob, /uses: actions\/checkout@v6/);
  assert.match(qualityJob, /fetch-depth: 0/);
});

test("remote metadata identifies a released main commit", () => {
  const commit = "1234567890abcdef1234567890abcdef12345678";
  const result = runWithMockedGitHubApi({
    mainCommit: commit,
    releaseCommit: commit,
  });
  const output = `${result.stdout}\n${result.stderr}`;

  assert.equal(result.status, 0, output);
  assert.match(output, /Release\/Tag : v0\.3\.0/);
  assert.match(output, /Commit ID\s+: 1234567890ab/);
  assert.match(output, /Channel\s+: main/);
  assert.doesNotMatch(output, /gho_test_secret_must_not_leak/);
  assert.match(output, /Cancelled\./);
});

test("anonymous metadata does not require GitHub CLI", () => {
  const commit = "1234567890abcdef1234567890abcdef12345678";
  const result = runWithMockedGitHubApi({
    mainCommit: commit,
    releaseCommit: commit,
    ghAvailable: false,
    hideGitHubCli: true,
  });
  const output = `${result.stdout}\n${result.stderr}`;

  assert.equal(result.status, 0, output);
  assert.match(output, /Release\/Tag : v0\.3\.0/);
  assert.match(output, /Commit ID\s+: 1234567890ab/);
  assert.doesNotMatch(output, /GitHub CLI fallback/);
});

test("rate-limited metadata uses authenticated GitHub CLI without exposing secrets", () => {
  const commit = "1234567890abcdef1234567890abcdef12345678";
  const result = runWithMockedGitHubApi({
    mainCommit: commit,
    releaseCommit: commit,
    rateLimited: true,
    ghFallback: true,
  });
  const output = `${result.stdout}\n${result.stderr}`;

  assert.equal(result.status, 0, output);
  assert.match(output, /Release\/Tag : v0\.3\.0/);
  assert.match(output, /Commit ID\s+: 1234567890ab/);
  assert.match(output, /Anonymous GitHub API rate limit exceeded/);
  assert.match(output, /Retry after \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/);
  assert.match(output, /Used authenticated GitHub CLI fallback/);
  assert.doesNotMatch(output, /gho_test_secret_must_not_leak/);
});

test("later release failure preserves its diagnostic after authenticated fallback", () => {
  const commit = "1234567890abcdef1234567890abcdef12345678";
  const result = runWithMockedGitHubApi({
    mainCommit: commit,
    releaseCommit: commit,
    rateLimited: true,
    ghFallback: true,
    ghReleaseFail: true,
  });
  const output = `${result.stdout}\n${result.stderr}`;

  assert.equal(result.status, 0, output);
  assert.match(output, /Release\/Tag : unavailable/);
  assert.match(output, /Commit ID\s+: 1234567890ab/);
  assert.match(output, /Used authenticated GitHub CLI fallback/);
  assert.match(output, /Authenticated GitHub CLI fallback failed/);
  assert.doesNotMatch(output, /gho_test_secret_must_not_leak/);
});

test("remote metadata marks main ahead of the latest release", () => {
  const result = runWithMockedGitHubApi({
    mainCommit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    releaseCommit: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    releaseTag: "v0.2.0",
  });
  const output = `${result.stdout}\n${result.stderr}`;

  assert.equal(result.status, 0, output);
  assert.match(output, /Release\/Tag : Unreleased \(latest: v0\.2\.0\)/);
  assert.match(output, /Commit ID\s+: aaaaaaaaaaaa/);
  assert.match(output, /Cancelled\./);
});

test("unreleased metadata keeps the latest release version for provenance", () => {
  const result = runWithMockedGitHubApi({
    mainCommit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    releaseCommit: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    releaseTag: "v0.3.0",
    input: "1\nbad_name\n\n\nn\n",
  });
  const output = `${result.stdout}\n${result.stderr}`;

  assert.match(output, /Release\/Tag : Unreleased \(latest: v0\.3\.0\)/);
  assert.match(output, /Version : 0\.3\.0/);
  assert.match(output, /Project ID must start with a lowercase letter/);
});

test("release metadata lookup failure is non-blocking", () => {
  const result = runWithMockedGitHubApi({
    fail: true,
    mainCommit: "",
    releaseCommit: "",
  });
  const output = `${result.stdout}\n${result.stderr}`;

  assert.equal(result.status, 0, output);
  assert.match(output, /Release\/Tag : unavailable/);
  assert.match(output, /Commit ID\s+: unavailable/);
  assert.match(output, /Authenticated GitHub CLI fallback failed or is not logged in/);
  assert.doesNotMatch(output, /gho_test_secret_must_not_leak/);
  assert.match(output, /Cancelled\./);
});

test("release metadata lookup failure does not stamp a stale version", () => {
  const result = runWithMockedGitHubApi({
    fail: true,
    mainCommit: "",
    releaseCommit: "",
    input: "1\nbad_name\n\n\nn\n",
  });
  const output = `${result.stdout}\n${result.stderr}`;

  assert.match(output, /Release\/Tag : unavailable/);
  assert.match(output, /Version : unavailable/);
  assert.match(output, /Project ID must start with a lowercase letter/);
});

test("remote Blueprint retrieval fails closed without an immutable commit", () => {
  const result = runWithMockedGitHubApi({
    fail: true,
    mainCommit: "",
    releaseCommit: "",
    input: "1\nimmutable-test\n\n\nn\n",
  });
  const output = `${result.stdout}\n${result.stderr}`;

  assert.notEqual(result.status, 0);
  assert.match(output, /Unable to resolve an immutable Bootstrapper commit/);
  assert.doesNotMatch(output, /\[Generate\]/);
});

test("rate limit diagnostics survive fail-closed Blueprint retrieval", () => {
  const result = runWithMockedGitHubApi({
    rateLimited: true,
    ghFallback: false,
    input: "1\nimmutable-rate-limit-test\n\n\nn\n",
  });
  const output = `${result.stdout}\n${result.stderr}`;

  assert.notEqual(result.status, 0);
  assert.match(output, /Anonymous GitHub API rate limit exceeded/);
  assert.match(output, /Retry after \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/);
  assert.match(output, /Unable to resolve an immutable Bootstrapper commit/);
  assert.doesNotMatch(output, /gho_test_secret_must_not_leak/);
  assert.doesNotMatch(output, /\[Generate\]/);
});

test("standalone script also fails closed without an immutable commit", async () => {
  const fixtureRoot = await mkdtemp(
    path.join(os.tmpdir(), "ibuki-standalone-pin-"),
  );
  const scriptPath = path.join(fixtureRoot, "bootstrap.ps1");
  const destination = path.join(fixtureRoot, "not-created");
  const escapedScriptPath = scriptPath.replaceAll("'", "''");
  const escapedDestination = destination.replaceAll("'", "''");

  try {
    await copyFile(bootstrapPath, scriptPath);
    const command = [
      "function Invoke-RestMethod { throw 'GitHub API unavailable' }",
      "function gh { $global:LASTEXITCODE = 1 }",
      `& '${escapedScriptPath}' -Blueprint web-hono -ProjectId standalone-pin-test -Destination '${escapedDestination}' -SkipGitHub -NonInteractive -Yes`,
    ].join("\n");
    const result = spawnSync("pwsh", ["-NoProfile", "-Command", command], {
      cwd: fixtureRoot,
      encoding: "utf8",
      timeout: 30_000,
    });
    const output = `${result.stdout}\n${result.stderr}`;

    assert.notEqual(result.status, 0);
    assert.match(output, /Unable to resolve an immutable Bootstrapper commit/);
    assert.doesNotMatch(output, /\[Generate\]/);
    await assert.rejects(access(destination));
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
  }
});
