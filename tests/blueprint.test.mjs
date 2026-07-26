import assert from "node:assert/strict";
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

test("template files use only supported tokens", async () => {
  const manifest = await readManifest();
  const supportedTokens = new Set([
    "__BOOTSTRAPPER_VERSION__",
    "__PROJECT_ID__",
    "__PROJECT_DISPLAY_NAME__",
    "__PROJECT_DISPLAY_NAME_HTML__",
    "__PROJECT_DISPLAY_NAME_JSON__",
    "__PROJECT_DISPLAY_NAME_YAML__",
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
    /\$script:BootstrapperVersion = "([^"]+)"/,
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
  assert.match(bootstrap, /allowedMergeMethods -notcontains "squash"/);
  assert.match(bootstrap, /requiredContexts -notcontains "Quality"/);
  assert.match(bootstrap, /strict_required_status_checks_policy/);
  assert.match(bootstrap, /currentBranch -ne "develop"/);
});
