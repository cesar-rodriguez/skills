# cesar-rodriguez/skills

A public, tool-agnostic collection of **LLM workflow “skills”** I use to ship production code quickly:

- Turn a vague idea into a **PRD**
- Convert PRD → **epic + well-scoped issues** with acceptance criteria
- Create a **dependency-aware execution plan** (phases / lanes / WIP)
- Execute with **dev + reviewer** loops, CI gating, and conflict recovery

These are written as simple, readable `SKILL.md` templates. You can copy/paste them into Claude Code, Cursor, Codex CLI, etc.

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

### A) Claude Code
1. Generate a PRD using `skills/prd/SKILL.md`.
2. Generate epic + issues from the PRD using `skills/epic-decomposer/SKILL.md`.
3. Generate an execution plan (phases/lanes/WIP) using `skills/execution-plan-generator/SKILL.md`.
4. Implement issue-by-issue (paste the issue body + AC into Claude Code; run tests).
5. Do a separate review pass using `skills/pr-reviewer/SKILL.md`.

### B) Cursor
- Put the PRD + issue acceptance criteria in the repo under `docs/`.
- Keep diffs small, run tests often.
- Before opening a PR, run the reviewer checklist (from `skills/pr-reviewer/`).

### C) Codex CLI
- Run Codex with: issue body + acceptance criteria + test command.
- Then run a second pass as “reviewer” using `skills/pr-reviewer/SKILL.md`.

### D) GitHub + terminal only
- You can still follow the artifacts: PRD doc → GitHub Issues → execution plan in Markdown → PRs.

## Licensing & attribution

See `LICENSE` and `THIRD_PARTY_NOTICES.md`.

## Non-proprietary

This repo intentionally contains **no company secrets**, tokens, internal URLs, or private architecture. Examples are generic (e.g., `owner/repo`).

## License

MIT (see `LICENSE`).
