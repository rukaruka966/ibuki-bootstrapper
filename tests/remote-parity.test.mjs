import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import {
  access,
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);

function runPowerShell(scriptPath, destination, cwd) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      "pwsh",
      [
        "-NoProfile",
        "-File",
        scriptPath,
        "-Blueprint",
        "web-hono",
        "-ProjectId",
        "parity-project",
        "-DisplayName",
        "Parity Project",
        "-Destination",
        destination,
        "-SkipGitHub",
        "-NonInteractive",
        "-Yes",
      ],
      { cwd },
    );
    let stdout = "";
    let stderr = "";

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", reject);
    child.on("close", (code) => {
      resolve({ code, output: `${stdout}\n${stderr}` });
    });
  });
}

function initializeRepository(directory) {
  for (const args of [
    ["init", "-b", "main", "--quiet"],
    ["config", "user.name", "Ibuki Test"],
    ["config", "user.email", "ibuki@example.invalid"],
    ["commit", "--allow-empty", "-m", "test", "--quiet"],
  ]) {
    const result = spawnSync("git", ["-C", directory, ...args], {
      encoding: "utf8",
    });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  }
}

async function readTree(root) {
  const result = new Map();

  async function visit(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const absolutePath = path.join(directory, entry.name);

      if (entry.isDirectory()) {
        await visit(absolutePath);
      } else {
        result.set(
          path.relative(root, absolutePath).replaceAll("\\", "/"),
          await readFile(absolutePath),
        );
      }
    }
  }

  await visit(root);
  return result;
}

test("local and HTTP Blueprint sources generate identical bytes", async () => {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), "ibuki-parity-"));
  const localRoot = path.join(fixtureRoot, "local");
  const remoteRoot = path.join(fixtureRoot, "remote");
  const blueprintRoot = path.join(localRoot, "blueprints", "web-hono");
  const localDestination = path.join(fixtureRoot, "local-output");
  const remoteDestination = path.join(fixtureRoot, "remote-output");
  const corruptDestination = path.join(fixtureRoot, "corrupt-output");
  const text = Buffer.from("project=__PROJECT_ID__\n", "utf8");
  const binary = Buffer.from([0x00, 0xff, 0x0d, 0x0a, 0x7f]);
  const manifest = {
    schemaVersion: 2,
    id: "web-hono",
    version: "test",
    displayName: "Parity fixture",
    toolchains: [
      {
        id: "node",
        command: "node",
        versionArguments: ["--version"],
        minimumVersion: "0.0.0",
        versionPattern: "v?(\\d+\\.\\d+\\.\\d+)",
      },
    ],
    verification: [
      {
        command: "node",
        arguments: ["--version"],
        workingDirectory: ".",
      },
    ],
    files: [
      {
        kind: "text",
        source: "template/project.txt.tpl",
        target: "project.txt",
        template: true,
      },
      {
        kind: "binary",
        source: "template/asset.bin",
        target: "asset.bin",
        template: false,
        sha256: createHash("sha256").update(binary).digest("hex"),
      },
    ],
  };
  const manifestBytes = Buffer.from(
    `${JSON.stringify(manifest, null, 2)}\n`,
    "utf8",
  );
  const immutableCommit = "1234567890abcdef1234567890abcdef12345678";
  const repositoryApiPath = "/repos/rukaruka966/ibuki-bootstrapper";
  const routes = new Map([
    [
      `${repositoryApiPath}/commits/main`,
      Buffer.from(`${JSON.stringify({ sha: immutableCommit })}\n`, "utf8"),
    ],
    [
      `${repositoryApiPath}/releases/latest`,
      Buffer.from(`${JSON.stringify({ tag_name: "v0.5.0" })}\n`, "utf8"),
    ],
    [
      `${repositoryApiPath}/commits/v0.5.0`,
      Buffer.from(`${JSON.stringify({ sha: immutableCommit })}\n`, "utf8"),
    ],
    ["/blueprints/web-hono/manifest.json", manifestBytes],
    ["/blueprints/web-hono/template/project.txt.tpl", text],
    ["/blueprints/web-hono/template/asset.bin", binary],
  ]);
  const requestedUrls = [];
  const server = createServer((request, response) => {
    requestedUrls.push(request.url);
    const blueprintPathIndex = request.url.indexOf("/blueprints/");
    const route = blueprintPathIndex >= 0
      ? request.url.slice(blueprintPathIndex)
      : request.url;
    const content = routes.get(route);

    if (content === undefined) {
      response.writeHead(404).end();
      return;
    }

    const contentType = route.startsWith("/repos/")
      ? "application/json"
      : "application/octet-stream";
    response.writeHead(200, {
      "Content-Length": content.length,
      "Content-Type": contentType,
    });
    response.end(content);
  });

  try {
    await mkdir(path.join(blueprintRoot, "template"), { recursive: true });
    await mkdir(remoteRoot, { recursive: true });
    await copyFile(
      path.join(repositoryRoot, "bootstrap.ps1"),
      path.join(localRoot, "bootstrap.ps1"),
    );
    await writeFile(
      path.join(blueprintRoot, "manifest.json"),
      manifestBytes,
    );
    await writeFile(path.join(blueprintRoot, "template", "project.txt.tpl"), text);
    await writeFile(path.join(blueprintRoot, "template", "asset.bin"), binary);
    initializeRepository(localRoot);

    await new Promise((resolve) => {
      server.listen(0, "127.0.0.1", resolve);
    });
    const address = server.address();
    assert.notEqual(address, null);

    const remoteBootstrap = path.join(remoteRoot, "bootstrap.ps1");
    const bootstrap = await readFile(
      path.join(repositoryRoot, "bootstrap.ps1"),
      "utf8",
    );
    const remoteBaseUrl = `http://127.0.0.1:${address.port}`;
    await writeFile(
      remoteBootstrap,
      bootstrap
        .replaceAll("https://api.github.com", remoteBaseUrl)
        .replaceAll("https://raw.githubusercontent.com", remoteBaseUrl),
      "utf8",
    );
    initializeRepository(remoteRoot);

    const localResult = await runPowerShell(
      path.join(localRoot, "bootstrap.ps1"),
      localDestination,
      localRoot,
    );
    assert.equal(localResult.code, 0, localResult.output);

    const remoteResult = await runPowerShell(
      remoteBootstrap,
      remoteDestination,
      remoteRoot,
    );
    assert.equal(remoteResult.code, 0, remoteResult.output);
    assert.equal(
      requestedUrls.some((url) =>
        /\/rukaruka966\/ibuki-bootstrapper\/[0-9a-f]{40}\/blueprints\//.test(
          url,
        ),
      ),
      true,
    );

    const localTree = await readTree(localDestination);
    const remoteTree = await readTree(remoteDestination);
    assert.deepEqual([...remoteTree.keys()], [...localTree.keys()]);

    for (const [relativePath, localBytes] of localTree) {
      assert.deepEqual(remoteTree.get(relativePath), localBytes, relativePath);
    }

    routes.set(
      "/blueprints/web-hono/template/asset.bin",
      Buffer.from([0x01, 0xff, 0x0d, 0x0a, 0x7f]),
    );
    const corruptResult = await runPowerShell(
      remoteBootstrap,
      corruptDestination,
      remoteRoot,
    );
    assert.notEqual(corruptResult.code, 0);
    assert.match(corruptResult.output, /binary checksum mismatch/);
    await assert.rejects(access(corruptDestination));
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await rm(fixtureRoot, { recursive: true, force: true });
  }
});
