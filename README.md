# cesar-rodriguez/skills

A public, tool-agnostic collection of **LLM workflow “skills”** I use to ship production code quickly:

- Turn a vague idea into a **PRD**
- Convert PRD → **epic + well-scoped issues** with acceptance criteria
- Create a **dependency-aware execution plan** (phases / lanes / WIP)
- Execute with **dev + reviewer** loops, CI gating, and conflict recovery

These are written as simple, readable `SKILL.md` templates. You can copy/paste them into Claude Code, Cursor, Codex CLI, etc.

## Install (optional): Skills CLI

If you use the community **Skills CLI**, you can install these templates into your local skills directory.

```bash
# Install the CLI (one-time)
npm install -g skills

# Install Cesar’s workflow skills (global)
npx skills add cesar-rodriguez/skills \
  --skill prd \
  --skill epic-decomposer \
  --skill execution-plan-generator \
  --skill repo-onboarder \
  --skill sprint-runner \
  --skill pr-reviewer \
  --skill merge-conflict-resolver \
  --skill ci-watcher \
  --global -y
```

Notes:
- Remove `--global` if you want a per-project/per-user install.
- Remove `-y` if you want interactive prompts.
- If you don’t use Skills CLI: just browse this repo and copy/paste the `SKILL.md` templates.

## What’s in here

### Requirements & planning
- `skills/prd/` — PRD generator (clarifying questions + structured PRD)
- `skills/epic-decomposer/` — goal → epic + issues (ACs, dependencies, file hints)
- `skills/execution-plan-generator/` — epic → phased plan (lanes/WIP, conflict-risk warnings)
- `skills/repo-onboarder/` — repo briefing generator (structure, commands, hot files)

### Execution & quality
- `skills/sprint-runner/` — orchestration playbook for running the plan end-to-end
- `skills/pr-reviewer/` — structured PR review against acceptance criteria + checklist
- `skills/merge-conflict-resolver/` — mechanical conflict resolution patterns + bailout protocol
- `skills/ci-watcher/` — a single-shell-loop CI wait script (JSON output)

## How to use (tool-agnostic)

1) **PRD (requirements)**
- Use `skills/prd/SKILL.md` as a prompt template.
- Output: a PRD Markdown doc.

2) **Epic + issues**
- Use `skills/epic-decomposer/SKILL.md` to produce:
 - a parent epic
 - child issues with crisp acceptance criteria

3) **Execution plan**
- Use `skills/execution-plan-generator/SKILL.md` to produce:
 - phases (dependency boundaries)
 - lanes (parallel streams)
 - WIP limits

4) **Implement + review loop**
- Use Codex CLI / Claude Code / Cursor for implementation.
- Use `skills/pr-reviewer/SKILL.md` as the reviewer prompt + checklist.

5) **CI gating + merging**
- Use `skills/ci-watcher/` to efficiently wait for checks.
- Use `skills/merge-conflict-resolver/` for conflict handling.

## Run this in X (quickstart)

Same workflow, different interface. The only non-negotiable: **don’t skip the PRD and acceptance criteria**.

### Recommended team convention
Keep the artifacts in the repo so everyone shares the same ground truth:
- `docs/prd/<feature>.md`
- `docs/plan/<epic>.md`
- `docs/progress/<epic>.md` (optional run ledger)

### A) Claude Code
1. Generate a PRD using `skills/prd/SKILL.md`.
2. Generate epic + issues from the PRD using `skills/epic-decomposer/SKILL.md`.
3. Generate an execution plan (phases/lanes/WIP) using `skills/execution-plan-generator/SKILL.md`.
4. Implement issue-by-issue (paste the issue body + AC verbatim; run tests).
5. Do a separate review pass using `skills/pr-reviewer/SKILL.md`.

### B) Cursor
- Put the PRD and plan in `docs/` so the agent always sees the same requirements.
- Keep diffs small, run tests often.
- Before opening a PR, run the reviewer checklist (from `skills/pr-reviewer/`).

### C) Codex CLI
- Paste: issue body + acceptance criteria + test command.
- Add constraints: small diffs, update tests, deterministic output.
- Then run a second pass as “reviewer” using `skills/pr-reviewer/SKILL.md`.

### D) GitHub + terminal only
You can still follow the artifacts: PRD doc → GitHub Issues → execution plan in Markdown → PRs.

Helpful `gh` commands:
```bash
# Create issues
gh issue create --repo owner/repo --title "..." --body "..."

# Create PR
gh pr create --repo owner/repo --title "..." --body "Closes #N" --fill

# Watch CI
gh pr checks <pr> --repo owner/repo

# Merge when green
gh pr merge <pr> --repo owner/repo --merge --delete-branch
```

## Licensing & attribution

See `LICENSE` and `THIRD_PARTY_NOTICES.md`.

## Non-proprietary

This repo intentionally contains **no company secrets**, tokens, internal URLs, or private architecture. Examples are generic (e.g., `owner/repo`).

## License

MIT (see `LICENSE`).
