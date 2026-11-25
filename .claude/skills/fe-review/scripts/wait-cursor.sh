#!/usr/bin/env bash
# Usage: wait-cursor.sh <pr-number> [repo] [interval-seconds]
# Blocks until the Cursor panel has reviewed the PR's CURRENT head, then prints
# one line and exits. Run it with Bash run_in_background: one notification.
#   0  "REVIEWED <sha>: <n> inline findings"
#   1  "RUN <conclusion> without a review for <sha>" (cancelled, failed, skipped
#      by the gate) or "LABEL MISSING" — read the run's gate job.
#   2  "GH API FAILING" after 5 failed calls in a row.
# Give the background task a timeout past the review's worst case (~60 min).
# The FE panel posts as github-actions[bot], so watch-pr.sh (which ignores that
# login for comments) is the wrong tool here.
set -uo pipefail
n="${1:?usage: wait-cursor.sh <pr> [repo] [interval]}"; repo="${2:-Comfy-Org/ComfyUI_frontend}"; every="${3:-60}"
# Only a run started after this script counts as terminal: right after a
# re-label, the newest run on the branch is still the cancelled previous one.
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fails=0
while true; do
  # A gh that keeps failing (auth, network) must say so, not loop silently.
  if ! pr=$(gh api "repos/$repo/pulls/$n" 2>&1); then
    fails=$((fails + 1))
    [ "$fails" -ge 5 ] && { echo "GH API FAILING x$fails: ${pr:0:200}"; exit 2; }
    sleep "$every"; continue
  fi
  fails=0
  sha=$(jq -r .head.sha <<<"$pr"); branch=$(jq -r .head.ref <<<"$pr")
  jq -e '[.labels[].name] | index("cursor-review")' <<<"$pr" >/dev/null || { echo "LABEL MISSING on #$n"; exit 1; }
  review=$(gh api "repos/$repo/pulls/$n/reviews?per_page=100" 2>/dev/null \
    | jq -r --arg sha "$sha" '[.[] | select(.commit_id==$sha and .state!="DISMISSED" and (.body|startswith("## 🔍 Cursor Review")))] | last | .id // empty')
  if [ -n "$review" ]; then
    count=$(gh api "repos/$repo/pulls/$n/reviews/$review/comments?per_page=100" --jq 'length' 2>/dev/null || echo "?")
    echo "REVIEWED ${sha:0:10}: $count inline findings"; exit 0
  fi
  # Removing the label spawns a run whose job is skipped; it is not the review.
  run=$(gh run list --repo "$repo" --branch "$branch" --workflow "PR: Cursor Review" --limit 5 --json status,conclusion,createdAt 2>/dev/null | jq "[.[] | select(.conclusion != \"skipped\")]")
  if [ "$(jq -r '.[0].status // ""' <<<"$run")" = "completed" ] \
    && [[ "$(jq -r '.[0].createdAt' <<<"$run")" > "$started" ]]; then
    concl=$(jq -r '.[0].conclusion' <<<"$run")
    # A completed success can still precede the review POST by a few seconds.
    sleep 20
    gh api "repos/$repo/pulls/$n/reviews?per_page=100" 2>/dev/null \
      | jq -e --arg sha "$sha" 'any(.[]; .commit_id==$sha and (.body|startswith("## 🔍 Cursor Review")))' >/dev/null \
      && continue
    echo "RUN $concl without a review for ${sha:0:10}"; exit 1
  fi
  sleep "$every"
done
