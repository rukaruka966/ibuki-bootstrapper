import { spawnSync } from "node:child_process";
import {
  copyFile,
  cp,
  mkdtemp,
  rm,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

function runGit(directory, arguments_) {
  const result = spawnSync("git", ["-C", directory, ...arguments_], {
    encoding: "utf8",
  });

  if (result.status !== 0) {
    throw new Error(
      `Unable to create clean Bootstrapper test source with git ${
        arguments_.join(" ")
      }:\n${result.stdout}\n${result.stderr}`,
    );
  }

  return result.stdout;
}

export function assertCleanRepository(directory) {
  const status = runGit(directory, ["status", "--porcelain"]);

  if (status.trim() !== "") {
    throw new Error(
      `Bootstrapper test source is not clean:\n${status}`,
    );
  }
}

export function initializeCleanRepository(directory, tag = "v0.0.0") {
  runGit(directory, ["init", "-b", "main", "--quiet", "--object-format=sha1"]);
  runGit(directory, ["add", "--all"]);
  runGit(directory, [
    "-c",
    "user.name=Ibuki Test",
    "-c",
    "user.email=ibuki@example.invalid",
    "-c",
    "commit.gpgSign=false",
    "commit",
    "--no-verify",
    "-m",
    "test: snapshot Bootstrapper source",
    "--quiet",
  ]);
  runGit(directory, ["tag", "--no-sign", tag]);
  assertCleanRepository(directory);
}

export async function createCleanBootstrapSource(repositoryRoot) {
  const fixtureRoot = await mkdtemp(
    path.join(tmpdir(), "ibuki-bootstrap-source-"),
  );

  try {
    await copyFile(
      path.join(repositoryRoot, "bootstrap.ps1"),
      path.join(fixtureRoot, "bootstrap.ps1"),
    );
    await cp(
      path.join(repositoryRoot, "blueprints"),
      path.join(fixtureRoot, "blueprints"),
      { recursive: true },
    );
    initializeCleanRepository(fixtureRoot);
    return fixtureRoot;
  } catch (error) {
    await rm(fixtureRoot, { recursive: true, force: true });
    throw error;
  }
}
