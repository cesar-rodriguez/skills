---
name: pr-reviewer
description: Autonomous PR code review — clones repo, reviews diff against linked issue acceptance criteria, runs tests, and leaves structured GitHub review comments.
---

# PR Reviewer

## Inputs

| Param | Required | Example |
|-------|----------|---------|
| `repo` | yes | `owner/repo` |
| `pr` | yes | `42` |
| `issue` | no | `PLAT-123` or `#18` — auto-detected from PR body if omitted |

## Workflow

### 1. Setup

```bash
WORKDIR=$(mktemp -d)
cd "$WORKDIR"
gh repo clone "$REPO" . -- --depth=50
gh pr checkout "$PR"
```

### 2. Gather Context

```bash
# PR metadata
gh pr view "$PR" --json title,body,headRefName,baseRefName,files,additions,deletions

# Linked issue (extract from PR body if not provided)
# Look for: "Closes #N", "Fixes #N", "Resolves #N", or Linear "TEAM-N" references
gh issue view "$ISSUE" --json title,body,labels

# The diff
gh pr diff "$PR"
```

Extract **acceptance criteria** from the issue body. Look for:
- Checkbox lists (`- [ ]`)
- "Acceptance Criteria" / "Requirements" / "Definition of Done" sections
- Numbered requirements
- If none found, infer from issue title + description

### 3. Detect Language & Tooling

Check for these files in priority order:

| File | Language | Test Command | Build Command |
|------|----------|-------------|---------------|
| `go.mod` | Go | `go test ./...` | `go build ./...` |
| `package.json` | Node | `npm test` | `npm run build` |
| `pyproject.toml` / `setup.py` | Python | `pytest` | — |
| `Cargo.toml` | Rust | `cargo test` | `cargo build` |
| `Makefile` | Any | `make test` | `make build` |

Also check for:
- `Makefile` targets: `make -qp | grep '^[a-z].*:' | grep -E 'test|lint|smoke|check'`
- CI config (`.github/workflows/`) to understand expected checks

### 4. Run Tests

```bash
# Build first (catch compilation errors before test noise)
$BUILD_CMD 2>&1 | tail -50

# Run tests
$TEST_CMD 2>&1 | tee /tmp/test-output.txt
TEST_EXIT=$?

# Lint if available
# Go: golangci-lint run ./... (if installed)
# Node: npm run lint (if script exists)
# Python: ruff check . (if installed)

# Smoke tests if available
if make -q smoke 2>/dev/null; then
  make smoke 2>&1 | tee /tmp/smoke-output.txt
fi
```

### 5. Review the Diff

Read the full diff. Apply the review checklist from `references/review-checklist.md`. Focus on:

**Correctness:** Does the code do what the issue asks? Are edge cases handled?

**Security:** Input validation, auth checks, injection risks, secret exposure.

**Reliability:** Error handling, nil/null guards, race conditions, resource leaks.

**Tests:** Are new code paths tested? Are edge cases covered? Do tests actually assert meaningful things (not just "no error")?

**Clarity:** Naming, structure, comments where non-obvious.

**Review Heuristics** (from real bugs caught in production sprints):
- **ID collision risk** — Any generated IDs (UUIDs, hashes, composite keys) must have sufficient entropy or uniqueness guarantees. Check for deterministic seeds or truncated hashes.
- **Nondeterministic ordering** — `map` iteration, `sort` without stable tie-breakers, `SELECT` without `ORDER BY`. If output order matters (snapshots, tests, APIs), it must be deterministic.
- **Missing schema validation** — New API inputs, config fields, or DB columns need validation. Don't trust upstream data.
- **Nil/null guard panics** — Any pointer dereference, map access, or optional chain that could panic/crash on nil input. Especially in error paths.
- **Incomplete test coverage** — New `if` branches, error paths, and boundary conditions need tests. "Happy path only" is a finding.
- **Hardcoded values** — Magic numbers, hardcoded URLs/paths, environment-specific assumptions.
- **Missing error propagation** — Errors swallowed with `_` or empty catch blocks.
- **Backwards compatibility** — API changes, config format changes, DB migrations that break existing consumers.
- **Release tooling completeness** — If the PR adds goreleaser, check for: ldflags (version/commit injection), Dockerfile if the project uses containers, correct binary names, archive format consistency. A goreleaser config without ldflags ships binaries with no version info.
- **Config file completeness** — New config files (goreleaser, CI workflows, Dockerfiles) must be checked against the project's existing patterns. Don't just verify they parse — verify they do the right thing.

### 6. Verify Acceptance Criteria

For each acceptance criterion from the issue, determine:
- ✅ **Met** — Code implements it, tests verify it
- ⚠️ **Partially met** — Implemented but untested, or incomplete
- ❌ **Not met** — Missing or incorrect

### 7. Submit Review

Use `gh` to leave a PR review. **Never use `--approve`** (bot can't approve its own PRs, and we want human sign-off). Always use `--comment` or `--request-changes`.

```bash
gh pr review "$PR" --comment --body "$REVIEW_BODY"
# OR
gh pr review "$PR" --request-changes --body "$REVIEW_BODY"
```

Decision logic:
- **Request changes** if: any test fails, any acceptance criterion is ❌, or any High severity finding
- **Comment (soft approve)** if: all tests pass, all criteria met, only Low/Medium findings

### 8. Cleanup

```bash
rm -rf "$WORKDIR"
```

## Structured Review Output

Use this exact format for the review body AND the report back to the caller:

```markdown
## PR Review: <PR title>

**Verdict:** 🟢 APPROVE / 🔴 CHANGES REQUESTED
**Tests:** ✅ All passing / ❌ N failures
**Smoke:** ✅ Passing / ⚠️ Not available / ❌ Failures

### Acceptance Criteria

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | <from issue> | ✅/⚠️/❌ | <detail> |

### Findings

| Severity | File:Line | Finding |
|----------|-----------|---------|
| 🔴 High | `pkg/foo.go:42` | Nil pointer dereference on error path |
| 🟡 Medium | `api/handler.go:18` | Missing input validation for `name` field |
| 🟢 Low | `README.md:5` | Typo in setup instructions |

### Test Results

<summary of test output — pass count, fail count, any notable failures>

### What's Next

<If changes requested: specific list of what the developer must fix>
<If approved: "Ready to merge" or any optional suggestions>
```

## Calling from sprint-runner

When invoked by sprint-runner, return a structured result:

```json
{
  "verdict": "approve" | "changes_requested",
  "findings_high": 0,
  "findings_medium": 2,
  "findings_low": 1,
  "tests_pass": true,
  "acceptance_criteria_met": 4,
  "acceptance_criteria_total": 5,
  "next_actions": ["Fix nil guard in pkg/foo.go:42", "Add test for empty input case"],
  "review_url": "https://github.com/org/repo/pull/42#pullrequestreview-12345"
}
```

## Error Handling

- **Clone fails** → Check repo access: `gh repo view "$REPO"`. Report auth issue.
- **PR not found** → `gh pr view "$PR"` — report if closed/merged/nonexistent.
- **No issue linked** → Review without acceptance criteria. Note this in output.
- **Tests fail before your changes** → Check base branch: `git stash && $TEST_CMD`. If base also fails, note "pre-existing test failures" and don't count against PR.
- **No test command found** → Flag as 🟡 Medium finding: "No test infrastructure detected."

## Tips

- For large diffs (>500 lines), prioritize reviewing: new files > modified core logic > test files > config/docs.
- Check if the PR has existing review comments — don't duplicate what's already been said.
- If tests take >5 min, set a timeout and note partial results.
- Look at the PR's CI status too: `gh pr checks "$PR"`.

## Lessons from Production Reviews

### sg-policy Epic #114
- **PR #124 (goreleaser):** Initial review missed that ldflags weren't configured and no Dockerfile was included. The review caught these on second pass, but they should have been flagged immediately. **Always check release tooling PRs against a completeness checklist.**
- **Bot self-approval:** Codex subagents can't approve PRs from the same bot account. Always use `--comment` or `--request-changes`, never `--approve`. The structured review format ("LGTM ✅" in comment) serves as soft approval for the sprint-runner to proceed.
- **Nondeterministic sort bugs** were caught by reviewers in epic #77 — this validates that dev+reviewer pairs add real value.
