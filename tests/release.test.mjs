import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { analyzeCommits } from "@semantic-release/commit-analyzer";
import releaseConfig from "../release.config.mjs";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const bootstrapPath = path.join(repositoryRoot, "bootstrap.ps1");
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
  input = "q\n",
}) {
  const escapedBootstrapPath = bootstrapPath.replaceAll("'", "''");
  const mockBody = fail
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
  const command = `
    function Invoke-RestMethod {
        param([string]$Uri, [hashtable]$Headers)
        ${mockBody}
    }
    Invoke-Expression (Get-Content -Raw -LiteralPath '${escapedBootstrapPath}')
  `;

  return spawnSync("pwsh", ["-NoProfile", "-Command", command], {
    cwd: repositoryRoot,
    encoding: "utf8",
    input,
    timeout: 30_000,
  });
}

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
  assert.match(output, /Cancelled\./);
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
