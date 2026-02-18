---
name: sprint-runner
description: "Run a full implementation sprint autonomously from an execution plan. Use when asked to 'run the sprint', 'execute the plan', 'implement the epic', or after an execution plan has been generated and needs to be executed."
version: 1.0.0
triggers:
  - "run the sprint"
  - "execute the plan"
  - "run execution plan"
  - "implement the epic"
  - "start the sprint"
---

# Sprint Runner Skill

Autonomous execution engine for GitHub or Linear-based implementation sprints. Reads an execution plan, spawns dev+reviewer Codex subagents, and drives issues through the full lifecycle: dev → review → fix → CI → merge → close.

## When to Use

- You have an **execution plan** (markdown file with issues, dependency graph, lane assignments, acceptance criteria)
- You want autonomous end-to-end implementation without Opus coordination overhead
- Triggered via your preferred agent runner (or a scheduler/cron)

## Prerequisites

**WORKSPACE:** If you use the optional progress/temp-file conventions below, set `WORKSPACE` (default: `~/.skills-workspace`).


1. **Execution plan file** in the workspace (e.g. `sprint-plans/my-plan.md`)
2. **Issues already created** with acceptance criteria (GitHub Issues or Linear — the plan's `Config` section specifies which tracker)
3. **Repo cloned** and accessible
4. Gateway config: `subagents.maxConcurrent: 4`, `approvals.exec.enabled: false`

## Critical Pre-Flight Checks

Before starting a sprint, verify these or you'll waste time:

1. **`/elevated off`** — run this in the session to prevent exec approval blocks
2. **No stale `index.lock`** — run `find /tmp -name "index.lock" -delete 2>/dev/null` 
3. **Verify exec works** — run a simple `exec echo "ok"` to confirm no approvals needed
4. **Check disk space** — each subagent clones the repo (~50-200MB per clone)

## Execution Plan Format

The plan file must contain:

```markdown
# Sprint: <name>

## Config
- **repo:** <org>/<repo>
- **base-branch:** main
- **tracker:** github | linear
- **tracker-project:** <linear project name, or "github" for GitHub Issues>
- **wip-limit:** 3

## Dependency Graph
<!-- Which issues block which. Use # prefix for GitHub, project prefix for Linear -->
- #101 (no deps)
- #102 (no deps)
- #103 → depends on #101
- #104 → depends on #101, #102

## Lanes
<!-- Parallel execution lanes -->
Lane A: #101 → #103
Lane B: #102 → #104

## Issues

### #101: <title>
- **Files:** src/foo.ts, src/foo.test.ts
- **Acceptance criteria:**
  - [ ] Implements X
  - [ ] Tests pass
  - [ ] No lint errors
- **Dev prompt:** <specific instructions for Codex>
- **Review focus:** <what reviewer should check>

### #102: <title>
...
```

## Progress File

**CRITICAL: Always create and maintain the progress file.** This is how the sprint survives compactions and session restarts.

The runner creates/updates `sprint-plans/<name>-progress.json`:

```json
{
  "sprint": "my-plan",
  "repo": "org/repo",
  "tracker": "github",
  "startedAt": "2026-02-16T03:20:00Z",
  "issues": {
    "#104": {
      "state": "merged",
      "branch": "fix/104-severity-enum",
      "pr": 115,
      "phase": 0,
      "lane": "A",
      "attempts": 1,
      "mergedAt": "2026-02-16T04:31:34Z"
    },
    "#107": {
      "state": "in-review",
      "branch": "refactor/107-jsonpointer-shared",
      "pr": 116,
      "phase": 0,
      "lane": "B",
      "attempts": 1
    }
  },
  "completedAt": null
}
```

**States:** `pending` → `dev` → `pr-created` → `in-review` → `fixing` → `ci-check` → `merging` → `merged` → `closed`

**Update the progress file after EVERY state change.** This is your lifeline if the session compacts.

## How the Runner Works

### 1. Init
- Read execution plan
- Create or resume progress file
- Validate all issues exist in the configured tracker (GitHub Issues or Linear — check the plan's `tracker` field)
- **Detect tracker from plan config** — never assume Linear/GitHub/Jira; read the plan

### 2. Main Loop
```
while unfinished issues exist:
  for each lane:
    find next ready issue (deps met, not blocked)
    if issue is pending:
      spawn dev subagent (Codex)
    if issue is dev-complete:
      create PR, spawn reviewer subagent
    if issue has review feedback:
      spawn fix subagent
    if issue passed review:
      check CI, merge, close Linear issue
    if merge conflict:
      clone, rebase, resolve, push
  update progress file
  wait 30s before next loop
```

### 3. Subagent Prompts

**Dev agent:**
```
You are implementing {issue_id}: {title}

Repo: {repo} Branch: {branch} (create from {base_branch})

Files to modify: {files}

Acceptance criteria:
{criteria}

Instructions:
{dev_prompt}

When done, commit with message: "feat({issue_id}): {title}" and push.
```

**Review agent:**
```
You are reviewing PR #{pr_number} for {issue_id}: {title}

Review focus: {review_focus}

Check:
1. Does it meet acceptance criteria?
2. Are tests adequate?
3. Any bugs, edge cases, or security issues?

If approved: comment "LGTM ✅"
If changes needed: comment with specific fixes required, prefixed with "CHANGES NEEDED:"
```

### 4. Merge Conflict Resolution (Auto-Invocation)

**Always auto-invoke the `merge-conflict-resolver` skill** when a PR shows CONFLICTING/DIRTY status or merge fails. Don't attempt manual rebase first — the skill handles classification, resolution, testing, and fallback.

```
Invocation:
  repo={repo}, pr={pr_number}, test_cmd={test_command from plan}
```

**Retry policy:**
1. First conflict → auto-invoke merge-conflict-resolver
2. If resolver bails → attempt the cherry-pick-to-new-PR fallback (create new branch from `main`, cherry-pick commits, open replacement PR, close old one — this is what we did with PR #119 → #122)
3. If that also fails → escalate to human with conflict details

**When to expect conflicts:**
- After merging a PR that touches shared files (imports, registrations, init blocks)
- When parallel lanes modify adjacent lines in the same file
- Hot files identified in the execution plan are conflict magnets — watch them

**Detection:** After each merge, check remaining open PRs for CONFLICTING status:
```bash
for pr in $(open_prs); do
  mergeable=$(gh pr view $pr --repo {repo} --json mergeable -q .mergeable)
  if [[ "$mergeable" == "CONFLICTING" ]]; then
    # Auto-invoke merge-conflict-resolver
  fi
done
```

### 5. Cleanup

After each issue merges:
```bash
# Remove the subagent's temp clone directory
rm -rf /tmp/{issue_id}-*
rm -rf $WORKSPACE/tmp/{repo_name}-{issue_id}* 2>/dev/null
```

After all issues merge:
```bash
# Clean up all sprint-related temp dirs
find /tmp -maxdepth 1 -name "*{sprint_name}*" -type d -exec rm -rf {} +
find $WORKSPACE/tmp -name "*{repo_name}*" -type d -exec rm -rf {} + 2>/dev/null
```

### 6. Completion
- Update progress file with `completedAt`
- Generate summary: issues closed, PRs merged, time elapsed, any escalations
- Notify the operator with the summary
- Clean up temp directories (see above)
- Close the epic issue on the tracker

## Shell Quoting in Dev Prompts

**Critical lesson from epic #114:** Complex shell quoting in dev agent prompts causes parse errors that waste entire subagent sessions.

**Rules:**
- Keep dev prompts as plain English — no backticks, no heredocs, no nested quotes
- If you need to show code examples, put them in a temp file and reference it: `See /tmp/sprint-{issue}/example.go`
- Avoid `$()`, `$(())`, backtick substitution in prompt text
- Test prompt strings locally with `echo` before spawning a subagent

## Escalation

The runner stops and reports when:
- A subagent fails 3 times on the same issue
- Merge conflict can't be auto-resolved after merge-conflict-resolver + cherry-pick fallback
- CI fails after 2 fix attempts
- A dependency cycle is detected
- Sandbox/git issues (`index.lock`, permission errors) — try `rm -f .git/index.lock` first

## Error Recovery Patterns

**Git index.lock:** `find /tmp -name "index.lock" -delete && find . -name "index.lock" -delete` then retry
**Shell parse errors in dev agent:** Simplify the dev prompt — see "Shell Quoting" section above
**Exec approvals blocking:** Verify `/elevated off` is set, restart gateway if needed
**PR CONFLICTING/DIRTY:** Auto-invoke merge-conflict-resolver (see section 4). If it bails, try cherry-pick-to-new-PR. If that fails, escalate.
**Subagent can't approve own PRs:** Bot accounts can't approve their own PRs — use comment-reviews instead of approve reviews. The pr-reviewer skill handles this correctly.

## Spawning the Runner

**Example:**
```
<agent_runner_spawn>(
  task: "Run sprint: sprint-plans/sg-policy-v2.md — follow skills/sprint-runner/SKILL.md",
  model: "codex",
  label: "sprint-runner"
)
```

**From cron (scheduled):**
```json
{
  "schedule": { "kind": "at", "at": "2026-02-16T14:00:00Z" },
  "payload": {
    "kind": "agentTurn",
    "message": "Run sprint: sprint-plans/sg-policy-v2.md — follow skills/sprint-runner/SKILL.md",
    "model": "codex"
  },
  "sessionTarget": "isolated"
}
```

## What Stays with the Coordinator (High-Context Model)

- **Creating execution plans** — codebase analysis, dependency design, acceptance criteria
- **Reviewing sprint results** — sanity-checking what shipped
- **Handling escalations** — decisions the runner can't make

## Lessons from Real-World Runs

- **Always keep a progress ledger** (JSON or Markdown) so an interruption doesn’t scramble state.
- **Pre-flight checks save hours:** clean git state, no stale locks, verify test command(s), confirm permissions.
- **Parallel lanes create merge conflicts** when they touch shared/hot files — plan lanes around file overlap.
- **Keep agent prompts simple** (avoid complex shell quoting); put long snippets in files instead.
- **Bots can’t always approve their own PRs** depending on auth model — use comment-reviews / request-changes workflows.
- **Automate conflict resolution** for mechanical cases (imports, lockfiles), but escalate semantic conflicts quickly.
