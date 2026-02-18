---
name: ci-watcher
description: Watch a GitHub PR's CI status efficiently via a single shell loop, then trigger next actions
version: 1.0.0
triggers:
  - ci
  - checks
  - pr status
---

# ci-watcher

Watches a PR's CI checks in a single `exec` call instead of burning agent turns polling.

## Usage

### From shell (via exec)
```bash
bash skills/ci-watcher/scripts/wait_for_ci.sh <repo> <pr_number> [max_wait_secs] [poll_interval_secs]
```

### From an agent skill
```bash
exec("bash skills/ci-watcher/scripts/wait_for_ci.sh owner/repo 42 600 15", timeout=660)
```

Parse the JSON output, then take action based on `status`:

| status    | exit code | meaning                        |
|-----------|-----------|--------------------------------|
| `success` | 0         | All checks passed              |
| `failure` | 1         | One or more checks failed      |
| `timeout` | 2         | Exceeded max wait time         |

### Next actions (agent decides after parsing output)
- **merge**: `gh pr merge <pr> --repo <repo> --merge --delete-branch` (only if status=success + mergeable=MERGEABLE)
- **notify**: return the JSON to the calling skill
- **review**: spawn a reviewer subagent on the PR
- **rebase-and-retry**: if mergeable=CONFLICTING, run `git rebase` and re-push

## Output format
```json
{
  "status": "success|failure|timeout",
  "checks": [{"name": "...", "status": "...", "conclusion": "...", "url": "..."}],
  "mergeable": "MERGEABLE|CONFLICTING|UNKNOWN",
  "failed_checks": [{"name": "...", "url": "..."}],
  "elapsed_seconds": 45
}
```
