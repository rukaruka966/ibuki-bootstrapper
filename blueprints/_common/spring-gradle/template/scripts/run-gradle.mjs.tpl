import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const arguments_ = process.argv.slice(2);

if (
  arguments_.length === 0 ||
  arguments_.some((argument) => !/^[A-Za-z0-9][A-Za-z0-9:._=-]*$/.test(argument))
) {
  throw new Error("Provide safe Gradle task names or options.");
}

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const projectRoot = path.join(repositoryRoot, "systems", "api-server");
const wrapper = process.platform === "win32" ? "gradlew.bat" : "./gradlew";
const result = spawnSync(wrapper, arguments_, {
  cwd: projectRoot,
  shell: process.platform === "win32",
  stdio: "inherit",
});

if (result.error) {
  throw result.error;
}

process.exitCode = result.status ?? 1;
