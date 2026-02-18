---
name: epic-decomposer
description: Turns a high-level goal into a GitHub epic with well-scoped issues, acceptance criteria, and dependency annotations — the missing step before execution-plan-generator.
version: 1.0.0
triggers:
  - "decompose epic"
  - "break down this initiative"
  - "create issues for"
  - "scope this work"
  - "plan issues for"
inputs:
  repo:
    description: "GitHub repo in org/name format"
    required: true
    example: "owner/repo"
  goal:
    description: "Plain-language description of the initiative (1-3 sentences)"
    required: true
    example: "Harden the policy engine: fix security issues, add adapters, improve determinism and performance"
  epic_title:
    description: "Title for the epic issue"
    required: false
    default: "auto-generated from goal"
  labels:
    description: "Labels to apply to all child issues"
    required: false
    default: "[]"
  max_issues:
    description: "Cap on how many issues to create (prevents scope explosion)"
    required: false
    default: 20
  tracker:
    description: "Issue tracker to use: 'github' (default) or 'linear'"
    required: false
    default: "github"
  linear_team:
    description: "Linear team key (e.g. 'PLAT') — required if tracker=linear"
    required: false
  dry_run:
    description: "If true, output the plan but don't create issues"
    required: false
    default: false
output: "Epic issue with linked child issues (on GitHub or Linear)"
tools:
  - gh
  - git
  - linear (if tracker=linear)
---

# Epic Decomposer

Takes a vague initiative ("harden the policy engine") and produces a fully-scoped GitHub epic with well-defined child issues, each containing acceptance criteria, file hints, and dependency annotations.

This is the **first step** in the autonomous sprint pipeline:

```
goal → EPIC-DECOMPOSER → issues → execution-plan-generator → plan → sprint-runner → merged PRs
```

## Quick Start

```
Decompose this into an epic for owner/repo:
"Add Terraform adapter support — parse HCL configs, map resources to policy subjects, integrate with scan CLI"
```

## Workflow

### Phase 1: Understand the Codebase

Clone and analyze the repo to understand what exists:

```bash
# Shallow clone
git clone --depth 1 https://github.com/{repo}.git /tmp/decompose-{repo_name}
cd /tmp/decompose-{repo_name}

# Language and structure
find . -name '*.go' -o -name '*.ts' -o -name '*.py' -o -name '*.rs' | head -200
cat go.mod 2>/dev/null || cat package.json 2>/dev/null

# Package layout
find . -type d -not -path '*/\.*' -not -path '*/vendor/*' -not -path '*/node_modules/*' | head -50

# Existing tests (to understand testing patterns)
find . -name '*_test.go' -o -name '*.test.ts' -o -name 'test_*.py' | head -30

# README and docs
cat README.md 2>/dev/null | head -100

# Recent activity (what areas are actively changing?)
git log --oneline --name-only -50 | grep -E '\.(go|ts|py|rs|java)$' | sort | uniq -c | sort -rn | head -20

# Existing interfaces/contracts (things new code must conform to)
grep -rn 'type.*interface' --include='*.go' | head -20
grep -rn 'export interface' --include='*.ts' | head -20
```

### Phase 2: Gap Analysis

Given the goal, identify what needs to change:

1. **What exists** — Current capabilities relevant to the goal
2. **What's missing** — Gaps between current state and the goal
3. **What needs fixing** — Existing code that doesn't meet the goal's quality bar
4. **What's adjacent** — Things not directly requested but needed for the goal to work (tests, docs, CLI integration)

Categorize each gap into a **work type**:

| Type | Examples |
|------|----------|
| `contract` | New interfaces, schemas, types, protobuf definitions |
| `security` | Auth, validation, input sanitization, path traversal fixes |
| `core` | Business logic, engine changes, algorithms |
| `adapter` | New integrations, format parsers, protocol handlers |
| `quality` | Determinism fixes, performance, error handling |
| `test` | Unit tests, integration tests, e2e, benchmarks |
| `docs` | README updates, API docs, migration guides |
| `infra` | CI/CD, config, build system, deployment |

### Phase 3: Issue Scoping

Each gap becomes an issue. Apply these scoping rules:

#### Size Rules
- **Target:** 1-4 hours of dev work per issue (for a Codex agent, this means ~1 session)
- **Max files touched:** 5-8 per issue (keeps PRs reviewable)
- **Split signal:** If an issue has >5 acceptance criteria, it's probably two issues
- **Merge signal:** If two issues touch the exact same 2 files, consider combining

#### Dependency Annotation
In each issue body, explicitly state dependencies:
```markdown
## Dependencies
- Depends on #N (need the FooInterface defined there)
- None (can start immediately)
```

#### Acceptance Criteria Format
Every issue MUST have clear, testable acceptance criteria:
```markdown
## Acceptance Criteria
- [ ] `FooAdapter` implements the `Adapter` interface
- [ ] Unit tests cover happy path + 3 error cases
- [ ] `go test ./pkg/adapters/foo/...` passes
- [ ] No lint warnings introduced
```

**Rules for good ACs:**
- Each AC is independently verifiable (a reviewer can check it)
- Include the specific test command to run
- Include specific type/function names when possible
- Include edge cases (empty input, nil, error paths)
- Don't put "nice to have" in ACs — either it's required or it's a separate issue

### Phase 4: Ordering and Prioritization

Assign priority based on dependency depth + risk:

| Priority | Criteria |
|----------|----------|
| P0 - Critical | Foundation contracts, security fixes, blockers |
| P1 - High | Core implementation that others depend on |
| P2 - Medium | Independent features, adapters, integrations |
| P3 - Low | Nice-to-haves, docs, polish, optimization |

Group issues into a natural execution order:
1. Contracts and interfaces first (things others import)
2. Security fixes (don't build on insecure foundations)
3. Core logic (consumes contracts)
4. Integrations and adapters (consumes core)
5. Testing and quality (validates everything above)
6. Docs and infra (adoption layer)

### Phase 5: Create Issues

Create issues on the configured tracker.

#### GitHub Issues (default)
```bash
gh issue create --repo {repo} \
  --title "{type emoji} {concise title}" \
  --body "{formatted body}" \
  --label "{labels}"
```

#### Linear
```bash
linear issue create --team {linear_team} \
  --title "{type emoji} {concise title}" \
  --description "{formatted body}" \
  --label "{labels}"
```

**Important:** Don’t assume the tracker from the repo name. Some repos use GitHub Issues, others use Linear/Jira. Always check or ask.

**Title format:** `{emoji} {Verb} {thing}` — e.g., "🔒 Fix path traversal in bundle loader"

**Emoji convention:**
- 📐 Contract/schema/interface
- 🔒 Security
- ⚙️ Core logic
- 🔌 Adapter/integration
- ✅ Test/quality
- 📚 Docs
- 🏗️ Infra/CI

**Body template:**
```markdown
## Summary
{1-2 sentences: what and why}

## Context
{What exists today, why this change is needed, relevant code paths}

## Approach
{Suggested implementation strategy — files to touch, patterns to follow}

## Acceptance Criteria
- [ ] {specific, testable criterion}
- [ ] {specific, testable criterion}
- [ ] Tests pass: `{test command}`

## Dependencies
- {Depends on #N / None}

## Files Likely Touched
- `{path/to/file.go}`
- `{path/to/other_file.go}`
```

### Phase 6: Create the Epic

After all child issues are created, create the parent epic on the same tracker.

#### GitHub Issues
```bash
# Build task list from created issues
TASK_LIST=$(printf '- [ ] #%s\n' {issue_numbers...})

gh issue create --repo {repo} \
  --title "🎯 {epic_title}" \
  --body "## Goal
{goal description}

## Scope
{number} issues across {types} work types.

## Issues
${TASK_LIST}

## Execution
Use with: \`execution-plan-generator\` → \`sprint-runner\`
" \
  --label "epic"
```

#### Linear
Create a project or parent issue, then link all child issues as sub-issues.

### Phase 7: Output Summary

Print a summary table:

```
Epic #{epic_number}: {title}
{total_issues} issues created

| # | Title | Type | Priority | Depends On |
|---|-------|------|----------|------------|
| #N | ... | core | P1 | #M |
```

And the suggested next command:
```
Generate an execution plan for {repo} epic #{epic_number}
```

## Edge Cases

### Goal is too vague
Ask one clarifying question max. If still vague, make reasonable assumptions and document them in the epic body under "## Assumptions".

### Scope explosion (>max_issues)
Group related work into composite issues. Prefer fewer well-scoped issues over many tiny ones. Note deferred work in the epic body under "## Out of Scope / Future Work".

### Repo has no tests
Add a "testing foundation" issue as P0 that sets up the test harness before other issues add tests.

### Existing epic/issues already cover some gaps
Check for existing open issues first:
```bash
gh issue list --repo {repo} --state open --json number,title --limit 100
```
Reference existing issues instead of creating duplicates. Note in the epic which issues are new vs. pre-existing.

## Anti-Patterns

- ❌ Issues with no ACs ("Implement the thing" — what thing? how do we know it's done?)
- ❌ Mega-issues that touch 15 files (split them)
- ❌ Circular dependencies (A depends on B depends on A — restructure)
- ❌ ACs that are subjective ("code should be clean" — define clean)
- ❌ Missing test expectations (every issue should specify what tests to write or run)
