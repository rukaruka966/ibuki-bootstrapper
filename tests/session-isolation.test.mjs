import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { access, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const bootstrapPath = path.join(repositoryRoot, "bootstrap.ps1");
const resultPrefix = "IBUKI_ISOLATION_RESULT=";

function runIsolationHarness({
  initializeLastExitCode = true,
  input,
  invocation,
  setup = [],
}) {
  const escapedPath = bootstrapPath.replaceAll("'", "''");
  const command = [
    "$ErrorActionPreference = 'Continue'",
    "$OutputEncoding = [System.Text.ASCIIEncoding]::new()",
    "[Console]::OutputEncoding = [System.Text.ASCIIEncoding]::new()",
    "$consoleEncodingBefore = [Console]::OutputEncoding.WebName",
    "$outputEncodingBefore = $OutputEncoding.WebName",
    "$ProjectId = 'caller-project'",
    "$state = 'caller-state'",
    "$utf8WithoutBom = 'caller-encoding'",
    ...(initializeLastExitCode ? ["$global:LASTEXITCODE = 73"] : []),
    "$lastExitCodeExistedBefore = $null -ne (Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue)",
    "function Write-Phase { return 'caller-write-phase' }",
    "Set-StrictMode -Off",
    `$source = Get-Content -LiteralPath '${escapedPath}' -Raw`,
    ...setup,
    "$caught = $false",
    invocation,
    "$strictModeLeaked = $false",
    "try { $null = $undefinedVariableForIbukiIsolationTest } catch { $strictModeLeaked = $true }",
    "$readHostAnswersVariable = Get-Variable -Name readHostAnswers -ErrorAction SilentlyContinue",
    "$readHostAnswersRemaining = if ($null -eq $readHostAnswersVariable) { $null } else { $readHostAnswersVariable.Value.Count }",
    "$result = [ordered]@{",
    "  ErrorActionPreference = $ErrorActionPreference.ToString()",
    "  OutputEncoding = $OutputEncoding.WebName",
    "  ConsoleOutputEncoding = [Console]::OutputEncoding.WebName",
    "  ConsoleEncodingBefore = $consoleEncodingBefore",
    "  OutputEncodingBefore = $outputEncodingBefore",
    "  ProjectId = $ProjectId",
    "  State = $state",
    "  Utf8Variable = $utf8WithoutBom",
    "  LastExitCode = $global:LASTEXITCODE",
    "  LastExitCodeExistedBefore = $lastExitCodeExistedBefore",
    "  LastExitCodeExistsAfter = $null -ne (Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue)",
    "  StrictModeLeaked = $strictModeLeaked",
    "  ExistingFunction = Write-Phase",
    "  ReadHostPreserved = (Get-Command Read-Host).Definition -match 'caller-read-host'",
    "  ReadHostAnswersRemaining = $readHostAnswersRemaining",
    "  ReadHostQueuePreserved = if ($null -eq $readHostAnswersVariable) { $null } else { [object]::ReferenceEquals($readHostAnswersReference, $readHostAnswersVariable.Value) }",
    "  HelperLeaked = $null -ne (Get-Command Invoke-CheckedCommand -ErrorAction SilentlyContinue)",
    "  Caught = $caught",
    "}",
    `Write-Output ("${resultPrefix}" + ($result | ConvertTo-Json -Compress))`,
  ].join("\n");

  const result = spawnSync("pwsh", ["-NoProfile", "-Command", command], {
    encoding: "utf8",
    input,
    timeout: 30_000,
  });
  const output = `${result.stdout}\n${result.stderr}`;
  const resultLine = result.stdout
    .split(/\r?\n/)
    .find((line) => line.startsWith(resultPrefix));

  assert.equal(result.status, 0, output);
  assert.notEqual(resultLine, undefined, output);

  return {
    output,
    session: JSON.parse(resultLine.slice(resultPrefix.length)),
  };
}

function assertCallerSessionPreserved(session) {
  assert.equal(session.ErrorActionPreference, "Continue");
  assert.equal(session.OutputEncoding, session.OutputEncodingBefore);
  assert.equal(session.ConsoleOutputEncoding, session.ConsoleEncodingBefore);
  assert.equal(session.ProjectId, "caller-project");
  assert.equal(session.State, "caller-state");
  assert.equal(session.Utf8Variable, "caller-encoding");
  assert.equal(session.LastExitCode, 73);
  assert.equal(session.LastExitCodeExistedBefore, true);
  assert.equal(session.LastExitCodeExistsAfter, true);
  assert.equal(session.StrictModeLeaked, false);
  assert.equal(session.ExistingFunction, "caller-write-phase");
  assert.equal(session.HelperLeaked, false);
}

test("IEX ignores caller args and preserves the caller session on cancel", () => {
  const { output, session } = runIsolationHarness({
    input: "0\n",
    invocation: [
      "function Invoke-IbukiFromCaller { Invoke-Expression $source }",
      "Invoke-IbukiFromCaller '-NonInteractive' '-ProjectId' 'must-be-ignored'",
    ].join("\n"),
  });

  assert.match(output, /Select a project configuration/);
  assert.match(output, /Cancelled\./);
  assert.doesNotMatch(output, /required in non-interactive mode/);
  assert.equal(session.Caught, false);
  assertCallerSessionPreserved(session);
});

test("IEX with stdin EOF cancels without leaking caller state", () => {
  const { output, session } = runIsolationHarness({
    input: "",
    invocation: "Invoke-Expression $source",
  });

  assert.match(output, /Select a project configuration/);
  assert.match(output, /Cancelled\./);
  assert.equal(session.Caught, false);
  assertCallerSessionPreserved(session);
});

test("IEX leaves LASTEXITCODE undefined when it was initially absent", () => {
  const { output, session } = runIsolationHarness({
    initializeLastExitCode: false,
    input: "0\n",
    invocation: "Invoke-Expression $source",
  });

  assert.match(output, /Cancelled\./);
  assert.equal(session.LastExitCodeExistedBefore, false);
  assert.equal(session.LastExitCodeExistsAfter, false);
});

test("IEX restores the caller session when bootstrap throws", () => {
  const { output, session } = runIsolationHarness({
    input: "",
    invocation:
      "try { Invoke-Expression $source } catch { $caught = $true }",
    setup: [
      "$readHostAnswers = [System.Collections.Generic.Queue[object]]::new()",
      "$readHostAnswersReference = $readHostAnswers",
      "$readHostAnswers.Enqueue('1')",
      "$readHostAnswers.Enqueue('INVALID PROJECT')",
      "$readHostAnswers.Enqueue('')",
      "$readHostAnswers.Enqueue('')",
      "$readHostAnswers.Enqueue('n')",
      "function Read-Host { param([string]$Prompt) # caller-read-host",
      "  if ($readHostAnswers.Count -eq 0) { return $null }",
      "  return $readHostAnswers.Dequeue()",
      "}",
    ],
  });

  assert.match(output, /Ibuki Bootstrapper failed/);
  assert.match(output, /Project ID must start with a lowercase letter/);
  assert.equal(session.Caught, true);
  assert.equal(session.ReadHostPreserved, true);
  assert.equal(session.ReadHostAnswersRemaining, 0);
  assert.equal(session.ReadHostQueuePreserved, true);
  assertCallerSessionPreserved(session);
});

test("IEX from a physical caller script ignores caller root and args", async () => {
  const workingDirectory = await mkdtemp(
    path.join(tmpdir(), "ibuki-physical-caller-"),
  );
  const callerPath = path.join(workingDirectory, "caller.ps1");
  const destination = path.join(workingDirectory, "must-not-exist");
  const escapedBootstrapPath = bootstrapPath.replaceAll("'", "''");

  try {
    const fakeBlueprintRoot = path.join(
      workingDirectory,
      "blueprints",
      "web-hono",
    );
    await mkdir(fakeBlueprintRoot, { recursive: true });
    await writeFile(
      path.join(fakeBlueprintRoot, "manifest.json"),
      '{"id":"fake-caller-blueprint","files":[]}',
      "utf8",
    );
    await writeFile(
      callerPath,
      [
        "$ErrorActionPreference = 'Continue'",
        "$OutputEncoding = [System.Text.ASCIIEncoding]::new()",
        "[Console]::OutputEncoding = [System.Text.ASCIIEncoding]::new()",
        "$consoleBefore = [Console]::OutputEncoding.WebName",
        "$state = 'physical-caller-state'",
        "$global:LASTEXITCODE = 73",
        `$source = Get-Content -LiteralPath '${escapedBootstrapPath}' -Raw`,
        "Invoke-Expression $source",
        "$result = [ordered]@{",
        "  ConsoleBefore = $consoleBefore",
        "  ConsoleAfter = [Console]::OutputEncoding.WebName",
        "  LastExitCode = $global:LASTEXITCODE",
        "  State = $state",
        "  HelperLeaked = $null -ne (Get-Command Invoke-CheckedCommand -ErrorAction SilentlyContinue)",
        "}",
        'Write-Output ("IBUKI_PHYSICAL_CALLER_RESULT=" + ($result | ConvertTo-Json -Compress))',
      ].join("\n"),
      "utf8",
    );

    const result = spawnSync(
      "pwsh",
      [
        "-NoProfile",
        "-File",
        callerPath,
        "-NonInteractive",
        "-Blueprint",
        "must-be-ignored",
        "-ProjectId",
        "must-be-ignored",
        "-Destination",
        destination,
        "-SkipGitHub",
        "-Yes",
      ],
      {
        cwd: workingDirectory,
        encoding: "utf8",
        input: "",
        timeout: 30_000,
      },
    );
    const output = `${result.stdout}\n${result.stderr}`;
    const resultLine = result.stdout
      .split(/\r?\n/)
      .find((line) => line.startsWith("IBUKI_PHYSICAL_CALLER_RESULT="));

    assert.equal(result.status, 0, output);
    assert.match(output, /Cancelled\./);
    assert.doesNotMatch(output, /must-be-ignored/);
    assert.notEqual(resultLine, undefined, output);

    const session = JSON.parse(
      resultLine.slice("IBUKI_PHYSICAL_CALLER_RESULT=".length),
    );

    assert.equal(session.ConsoleAfter, session.ConsoleBefore);
    assert.equal(session.LastExitCode, 73);
    assert.equal(session.State, "physical-caller-state");
    assert.equal(session.HelperLeaked, false);
    await assert.rejects(access(destination));
  } finally {
    await rm(workingDirectory, { recursive: true, force: true });
  }
});
