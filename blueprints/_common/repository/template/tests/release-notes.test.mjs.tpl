import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { generateNotes } from "@semantic-release/release-notes-generator";
import releaseConfig from "../release.config.mjs";

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

test("repository release notes include features and bug fixes", async () => {
  const packageJson = JSON.parse(await readFile("package.json", "utf8"));
  assert.equal(
    packageJson.devDependencies["conventional-changelog-conventionalcommits"],
    "9.3.1",
  );

  const notes = await generateNotes(
    getPluginConfiguration("@semantic-release/release-notes-generator"),
    {
      commits: [
        { hash: "1234567890abcdef", message: "feat: add a feature" },
        { hash: "abcdef1234567890", message: "fix: correct a defect" },
      ],
      lastRelease: { gitTag: "v0.1.0", version: "0.1.0" },
      nextRelease: { gitTag: "v0.2.0", version: "0.2.0" },
      options: { repositoryUrl: "https://github.com/example/project.git" },
      logger: silentLogger,
    },
  );

  assert.match(notes, /### Features/);
  assert.match(notes, /add a feature/);
  assert.match(notes, /### Bug Fixes/);
  assert.match(notes, /correct a defect/);
});
