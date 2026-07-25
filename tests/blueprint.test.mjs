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
