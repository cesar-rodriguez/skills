#!/usr/bin/env bash
# ci-watcher: wait for PR CI checks to complete in a single shell loop.
# Usage: wait_for_ci.sh <repo> <pr_number> [max_wait_secs=600] [poll_interval_secs=15]
# Exit: 0=success, 1=failure, 2=timeout

set -euo pipefail

REPO="${1:?Usage: wait_for_ci.sh <repo> <pr_number> [max_wait_secs] [poll_interval_secs]}"
PR="${2:?Missing PR number}"
MAX_WAIT="${3:-600}"
POLL_INTERVAL="${4:-15}"

START=$(date +%s)

# Helper: output final JSON and exit
emit() {
  local status="$1" exit_code="$2" checks="$3" mergeable="$4" failed="$5" elapsed="$6"
  cat <<EOF
{"status":"${status}","checks":${checks},"mergeable":"${mergeable}","failed_checks":${failed},"elapsed_seconds":${elapsed}}
EOF
  exit "$exit_code"
}

while true; do
  NOW=$(date +%s)
  ELAPSED=$(( NOW - START ))

  # Timeout check
  if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
    emit "timeout" 2 "[]" "UNKNOWN" "[]" "$ELAPSED"
  fi

  # Fetch PR data
  RAW=$(gh pr view "$PR" --repo "$REPO" --json statusCheckRollup,mergeable 2>&1) || {
    # gh CLI error — wait and retry (might be transient)
    sleep "$POLL_INTERVAL"
    continue
  }

  MERGEABLE=$(echo "$RAW" | jq -r '.mergeable // "UNKNOWN"')

  # Extract checks array
  CHECKS=$(echo "$RAW" | jq -c '[(.statusCheckRollup // [])[] | {name: .name, status: (.status // .state // "UNKNOWN"), conclusion: (.conclusion // "PENDING"), url: (.detailsUrl // .targetUrl // "")}]')

  TOTAL=$(echo "$CHECKS" | jq 'length')

  # If no checks yet, wait
  if [ "$TOTAL" -eq 0 ]; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  # Count pending (status IN_PROGRESS/QUEUED or conclusion null/PENDING/empty)
  PENDING=$(echo "$CHECKS" | jq '[.[] | select(.conclusion == "PENDING" or .conclusion == "" or .conclusion == null or .status == "IN_PROGRESS" or .status == "QUEUED" or .status == "PENDING")] | length')

  if [ "$PENDING" -gt 0 ]; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  # All checks completed — determine result
  FAILED=$(echo "$CHECKS" | jq -c '[.[] | select(.conclusion != "SUCCESS" and .conclusion != "NEUTRAL" and .conclusion != "SKIPPED") | {name: .name, url: .url}]')
  FAIL_COUNT=$(echo "$FAILED" | jq 'length')

  NOW=$(date +%s)
  ELAPSED=$(( NOW - START ))

  if [ "$FAIL_COUNT" -eq 0 ]; then
    emit "success" 0 "$CHECKS" "$MERGEABLE" "[]" "$ELAPSED"
  else
    emit "failure" 1 "$CHECKS" "$MERGEABLE" "$FAILED" "$ELAPSED"
  fi
done
