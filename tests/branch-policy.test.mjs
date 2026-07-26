import assert from "node:assert/strict";
import test from "node:test";
import { validatePullRequestBranchPolicy } from "../scripts/check-pr-branch-policy.mjs";

test("only develop may target main", () => {
  assert.doesNotThrow(() =>
    validatePullRequestBranchPolicy({
      eventName: "pull_request",
      baseRef: "main",
      headRef: "develop",
      baseRepository: "owner/project",
      headRepository: "owner/project",
    }),
  );

  assert.throws(
    () =>
      validatePullRequestBranchPolicy({
        eventName: "pull_request",
        baseRef: "main",
        headRef: "feature/example",
        baseRepository: "owner/project",
        headRepository: "owner/project",
      }),
    /same repository/,
  );
});

test("a fork develop branch may not target main", () => {
  assert.throws(
    () =>
      validatePullRequestBranchPolicy({
        eventName: "pull_request",
        baseRef: "main",
        headRef: "develop",
        baseRepository: "owner/project",
        headRepository: "fork-owner/project",
      }),
    /same repository/,
  );
});

test("feature pull requests to develop and pushes remain allowed", () => {
  assert.doesNotThrow(() =>
    validatePullRequestBranchPolicy({
      eventName: "pull_request",
      baseRef: "develop",
      headRef: "feature/example",
    }),
  );
  assert.doesNotThrow(() =>
    validatePullRequestBranchPolicy({
      eventName: "push",
      baseRef: "",
      headRef: "",
    }),
  );
});
