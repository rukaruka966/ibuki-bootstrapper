import { pathToFileURL } from "node:url";

export function validatePullRequestBranchPolicy({
  eventName,
  baseRef,
  headRef,
  baseRepository,
  headRepository,
}) {
  if (
    eventName === "pull_request" &&
    baseRef === "main" &&
    (headRef !== "develop" || headRepository !== baseRepository)
  ) {
    throw new Error(
      "Pull requests targeting main must come from develop in the same repository.",
    );
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  validatePullRequestBranchPolicy({
    eventName: process.env.GITHUB_EVENT_NAME,
    baseRef: process.env.GITHUB_BASE_REF,
    headRef: process.env.GITHUB_HEAD_REF,
    baseRepository: process.env.GITHUB_BASE_REPOSITORY,
    headRepository: process.env.GITHUB_HEAD_REPOSITORY,
  });
}
