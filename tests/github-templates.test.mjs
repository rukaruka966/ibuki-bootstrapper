import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { parseDocument } from "yaml";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const rootTemplateDirectory = path.join(
  repositoryRoot,
  ".github",
  "ISSUE_TEMPLATE",
);
const commonTemplateDirectory = path.join(
  repositoryRoot,
  "blueprints",
  "_common",
  "repository",
  "template",
  ".github",
  "ISSUE_TEMPLATE",
);
const interactiveTypes = new Set([
  "input",
  "textarea",
  "dropdown",
  "checkboxes",
]);
const formTypes = new Set(["markdown", ...interactiveTypes]);
const formKeys = new Set([
  "name",
  "description",
  "title",
  "labels",
  "assignees",
  "body",
]);

const formContracts = [
  {
    name: "root bug report",
    path: path.join(rootTemplateDirectory, "bug-report.yml"),
    labels: ["bug"],
    required: new Map([
      ["area", false],
      ["observed-behavior", true],
      ["expected-behavior", true],
      ["reproduction", true],
      ["bootstrapper-identity", false],
      ["blueprint", false],
      ["environment", false],
      ["impact", false],
      ["evidence", false],
      ["constraints", false],
      ["public-report-safety", false],
    ]),
    ibukiSpecific: true,
  },
  {
    name: "root feature request",
    path: path.join(rootTemplateDirectory, "feature-request.yml"),
    labels: ["enhancement"],
    required: new Map([
      ["area", false],
      ["problem", true],
      ["desired-outcome", true],
      ["responsibility-boundary", false],
      ["scope", false],
      ["out-of-scope", false],
      ["constraints", false],
      ["context", false],
      ["public-report-safety", false],
    ]),
    ibukiSpecific: true,
  },
  {
    name: "common bug report",
    path: path.join(commonTemplateDirectory, "bug-report.yml.tpl"),
    labels: undefined,
    required: new Map([
      ["component", false],
      ["observed-behavior", true],
      ["expected-behavior", true],
      ["reproduction", true],
      ["environment", false],
      ["impact", false],
      ["evidence", false],
      ["constraints", false],
      ["public-report-safety", false],
    ]),
    ibukiSpecific: false,
  },
  {
    name: "common feature request",
    path: path.join(commonTemplateDirectory, "feature-request.yml.tpl"),
    labels: undefined,
    required: new Map([
      ["component", false],
      ["problem", true],
      ["desired-outcome", true],
      ["scope", false],
      ["out-of-scope", false],
      ["constraints", false],
      ["context", false],
      ["public-report-safety", false],
    ]),
    ibukiSpecific: false,
  },
];

async function parseYamlFile(filePath) {
  const source = await readFile(filePath, "utf8");
  const document = parseDocument(source, {
    prettyErrors: true,
    uniqueKeys: true,
  });

  assert.deepEqual(
    document.errors.map((error) => error.message),
    [],
    filePath,
  );

  return { source, value: document.toJS() };
}

function assertPlainObject(value, context) {
  assert.equal(
    typeof value === "object" && value !== null && !Array.isArray(value),
    true,
    context,
  );
}

function assertOptionalRequiredValidation(field, expected, context) {
  if (expected) {
    assertPlainObject(field.validations, `${context} validations`);
    assert.equal(field.validations.required, true, `${context} required`);
    return;
  }

  if (field.validations !== undefined) {
    assertPlainObject(field.validations, `${context} validations`);
    assert.equal(
      field.validations.required ?? false,
      false,
      `${context} optional`,
    );
  }
}

function assertIssueForm(form, contract) {
  assertPlainObject(form, contract.name);
  assert.deepEqual(
    Object.keys(form).filter((key) => !formKeys.has(key)),
    [],
    `${contract.name} unsupported top-level keys`,
  );
  assert.equal(typeof form.name, "string");
  assert.ok(form.name.length > 3);
  assert.equal(typeof form.description, "string");
  assert.ok(form.description.length > 0);
  assert.ok(Array.isArray(form.body));
  assert.ok(form.body.length > 0);
  assert.deepEqual(form.labels, contract.labels);

  const fields = new Map();
  let markdownCount = 0;

  for (const [index, field] of form.body.entries()) {
    const context = `${contract.name} body[${index}]`;
    assertPlainObject(field, context);
    assert.equal(formTypes.has(field.type), true, `${context} type`);
    assertPlainObject(field.attributes, `${context} attributes`);

    if (field.type === "markdown") {
      markdownCount += 1;
      assert.equal(field.id, undefined, `${context} markdown id`);
      assert.equal(typeof field.attributes.value, "string", `${context} value`);
      assert.ok(field.attributes.value.length > 0, `${context} value`);
      continue;
    }

    assert.match(field.id, /^[a-z0-9-]+$/, `${context} id`);
    assert.equal(fields.has(field.id), false, `${context} duplicate id`);
    assert.equal(typeof field.attributes.label, "string", `${context} label`);
    assert.ok(field.attributes.label.length > 0, `${context} label`);
    fields.set(field.id, field);

    if (field.type === "dropdown") {
      assert.ok(
        Array.isArray(field.attributes.options) &&
          field.attributes.options.length > 0,
        `${context} options`,
      );
      assert.equal(
        field.attributes.options.every(
          (option) => typeof option === "string" && option.length > 0,
        ),
        true,
        `${context} option values`,
      );
      assert.equal(
        new Set(field.attributes.options).size,
        field.attributes.options.length,
        `${context} duplicate options`,
      );
    }

    if (field.type === "checkboxes") {
      assert.ok(
        Array.isArray(field.attributes.options) &&
          field.attributes.options.length > 0,
        `${context} options`,
      );

      for (const option of field.attributes.options) {
        assertPlainObject(option, `${context} option`);
        assert.equal(typeof option.label, "string", `${context} option label`);
        assert.ok(option.label.length > 0, `${context} option label`);
        assert.equal(
          typeof option.required,
          "boolean",
          `${context} option required`,
        );
      }
    }
  }

  assert.ok(markdownCount > 0, `${contract.name} guidance`);
  assert.deepEqual([...fields.keys()], [...contract.required.keys()]);

  for (const [id, expectedRequired] of contract.required) {
    assertOptionalRequiredValidation(
      fields.get(id),
      expectedRequired,
      `${contract.name} ${id}`,
    );
  }

  const safety = fields.get("public-report-safety");
  assert.equal(safety.type, "checkboxes");
  assert.equal(safety.attributes.options.length, 2);
  assert.equal(
    safety.attributes.options.every((option) => option.required === true),
    true,
  );
  const safetyLabels = safety.attributes.options
    .map((option) => option.label)
    .join("\n");
  assert.match(safetyLabels, /secrets.*tokens.*personal information/is);
  assert.match(safetyLabels, /security vulnerability/is);

  if (contract.ibukiSpecific) {
    assert.match(`${form.name}\n${form.description}`, /Ibuki/);
  }
}

test("Issue Forms are valid YAML and satisfy the AI work contract", async () => {
  for (const contract of formContracts) {
    const { source, value } = await parseYamlFile(contract.path);
    assertIssueForm(value, contract);

    if (!contract.ibukiSpecific) {
      assert.doesNotMatch(
        source,
        /\b(?:Ibuki|Bootstrapper|Blueprint)\b|bootstrap\.ps1|pnpm run verify|rukaruka966/i,
        `${contract.name} contains an Ibuki-specific term`,
      );
    }
  }
});

test("Issue template chooser configs are valid and permit unclassified work", async () => {
  for (const configPath of [
    path.join(rootTemplateDirectory, "config.yml"),
    path.join(commonTemplateDirectory, "config.yml.tpl"),
  ]) {
    const { value } = await parseYamlFile(configPath);
    assertPlainObject(value, configPath);
    assert.deepEqual(Object.keys(value), ["blank_issues_enabled"]);
    assert.equal(value.blank_issues_enabled, true);
  }
});

test("YAML validation rejects duplicate mapping keys", () => {
  const document = parseDocument(
    "name: First\ndescription: Example\nname: Second\nbody: []\n",
    { uniqueKeys: true },
  );

  assert.ok(document.errors.length > 0);
});

test("pull request templates preserve AI handoff and human acceptance", async () => {
  const templates = [
    {
      name: "root",
      path: path.join(
        repositoryRoot,
        ".github",
        "PULL_REQUEST_TEMPLATE.md",
      ),
      ibukiSpecific: true,
    },
    {
      name: "common",
      path: path.join(
        repositoryRoot,
        "blueprints",
        "_common",
        "repository",
        "template",
        ".github",
        "PULL_REQUEST_TEMPLATE.md.tpl",
      ),
      ibukiSpecific: false,
    },
  ];
  const headings = [
    "## Contract",
    "## Delivered outcome",
    "## Decisions and differences",
    "## AI verification",
    "## AI review handoff",
    "## Stop conditions",
    "## Human acceptance",
  ];

  for (const contract of templates) {
    const content = await readFile(contract.path, "utf8");
    let previousIndex = -1;

    for (const heading of headings) {
      const headingIndex = content.indexOf(heading);
      assert.ok(headingIndex > previousIndex, `${contract.name}: ${heading}`);
      previousIndex = headingIndex;
    }

    assert.match(content, /Related issue:/);
    assert.match(content, /Known differences from the request:/);
    assert.match(content, /Review result:/);
    assert.match(content, /Triggered: None/);
    assert.match(content, /Resolution or human decision: Not applicable/);
    assert.match(content, /Status: `Pending`/);
    assert.match(
      content,
      /Status values: Pending \/ Accepted \/ Changes requested \/ Not required\./,
    );
    assert.match(content, /Acceptance target:/);
    assert.match(
      content,
      /For a Pull Request to main, Human acceptance must be Accepted/,
    );
    assert.match(content, /secrets or user-specific absolute paths/i);

    if (contract.ibukiSpecific) {
      assert.match(content, /pnpm run verify/);
      assert.match(content, /All available Blueprints/);
      assert.match(
        content,
        /Generated-project install, test, build, and startup commands were not run/,
      );
    } else {
      assert.doesNotMatch(
        content,
        /\b(?:Ibuki|Bootstrapper|Blueprint)\b|bootstrap\.ps1|pnpm run verify|rukaruka966/i,
      );
      assert.doesNotMatch(content, /\b(?:React|Hono|Spring Boot)\b/i);
    }
  }
});

test("AI and human responsibilities remain in persistent guidance", async () => {
  const englishGuides = [
    path.join(repositoryRoot, "AGENTS.md"),
    path.join(repositoryRoot, "blueprints", "web-hono", "template", "AGENTS.md.tpl"),
    path.join(repositoryRoot, "blueprints", "api-spring", "template", "AGENTS.md.tpl"),
    path.join(repositoryRoot, "blueprints", "api-spring-postgres", "template", "AGENTS.md.tpl"),
    path.join(repositoryRoot, "blueprints", "_common", "repository", "template", "docs", "REPOSITORY_OPERATIONS.md.tpl"),
  ];
  const japaneseGuides = [
    path.join(repositoryRoot, "blueprints", "web-hono", "template", "docs", "ja-JP", "AGENTS-ja.md.tpl"),
    path.join(repositoryRoot, "blueprints", "api-spring", "template", "docs", "ja-JP", "AGENTS-ja.md.tpl"),
    path.join(repositoryRoot, "blueprints", "api-spring-postgres", "template", "docs", "ja-JP", "AGENTS-ja.md.tpl"),
    path.join(repositoryRoot, "blueprints", "_common", "repository", "template", "docs", "ja-JP", "REPOSITORY_OPERATIONS-ja.md.tpl"),
  ];

  for (const guide of englishGuides) {
    const content = await readFile(guide, "utf8");
    assert.match(content, /Humans provide observed and desired outcomes|Humans provide observed and desired outcomes and perform acceptance checks/);
    assert.match(content, /When the repository uses GitHub\s+Issues/);
    assert.match(content, /scope, non-goals/);
    assert.match(content, /acceptance targets/);
    assert.match(content, /verification plan/);
  }

  for (const guide of japaneseGuides) {
    const content = await readFile(guide, "utf8");
    assert.match(content, /人間は観測結果と期待結果/);
    assert.match(content, /GitHub Issueを使用する場合/);
    assert.match(content, /対象範囲、対象外/);
    assert.match(content, /受け入れ条件/);
    assert.match(content, /検証計画/);
  }
});
