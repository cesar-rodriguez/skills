# cesar-rodriguez/skills

A public, tool-agnostic collection of **LLM workflow “skills”** I use to ship production code quickly:

- Turn a vague idea into a **PRD**
- Convert PRD → **epic + well-scoped issues** with acceptance criteria
- Create a **dependency-aware execution plan** (phases / lanes / WIP)
- Execute with **dev + reviewer** loops, CI gating, and conflict recovery

These are written in an **OpenClaw skill style** (a single `SKILL.md` per skill), but you don’t need OpenClaw to benefit from them: you can copy/paste the prompts into Claude Code, Cursor, Codex CLI, etc.

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

## Non-proprietary

This repo intentionally contains **no company secrets**, tokens, internal URLs, or private architecture. Examples are generic (e.g., `owner/repo`).

## License

MIT (see `LICENSE`).
