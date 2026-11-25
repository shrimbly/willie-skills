#!/usr/bin/env bash
# relabel.sh <owner/repo> <pr> [expected-sha]
#
# (Re)trigger the Cursor review on the PR's CURRENT head, and prove it started.
#
# Why: the label event runs against whatever head GitHub has for the PR at that
# moment. Re-labelling straight after a push can land before GitHub has taken
# the new commit, so the run reviews (or cancels on) the OLD head and nothing
# ever runs on the new one (platform#1256, 1 Oct 2026: two runs on cf45ff38f,
# none on 8993ebbee, and a watch waiting on a review that was never coming).
#
# 1. Waits until the PR's headRefOid equals expected-sha (default: local HEAD).
# 2. Removes and re-adds the `cursor-review` label.
# 3. Waits for a `CI - Cursor Review` run on that sha and reports its Gate job.
# Exit 0 = gate passed on the right sha; non-zero = say so, do not assume.
set -euo pipefail
repo="$1"; pr="$2"; want="${3:-$(git rev-parse HEAD)}"

for _ in $(seq 1 60); do
  head=$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq .headRefOid 2>/dev/null || true)
  [ "$head" = "$want" ] && break
  sleep 5
done
[ "$head" = "$want" ] || { echo "PR head is ${head:0:9}, not ${want:0:9}, after 5 min. Push first."; exit 2; }

gh api -X DELETE "repos/$repo/issues/$pr/labels/cursor-review" >/dev/null 2>&1 || true
sleep 3
gh api "repos/$repo/issues/$pr/labels" -f 'labels[]=cursor-review' >/dev/null
branch=$(gh pr view "$pr" --repo "$repo" --json headRefName --jq .headRefName)

for _ in $(seq 1 40); do
  sleep 15
  # The newest run on this sha; the unlabel event makes one too, which the
  # gate skips, so look for a Gate that succeeded rather than the first run.
  for id in $(gh run list --repo "$repo" --branch "$branch" --workflow "CI - Cursor Review" \
      --limit 5 --json databaseId,headSha --jq ".[] | select(.headSha==\"$want\") | .databaseId"); do
    gate=$(gh api "repos/$repo/actions/runs/$id/jobs" \
      --jq '.jobs[] | select(.name|test("Gate")) | "\(.status)/\(.conclusion // "-")"' 2>/dev/null || true)
    diff=$(gh api "repos/$repo/actions/runs/$id/jobs" \
      --jq '.jobs[] | select(.name|test("Diff size")) | .conclusion // .status' 2>/dev/null || true)
    if [ "$gate" = "completed/success" ] && [ "$diff" != "skipped" ] && [ -n "$diff" ]; then
      echo "Cursor review running on ${want:0:9} (run $id)."
      exit 0
    fi
  done
done
echo "No Cursor review run got past its gate on ${want:0:9} in 10 min. Read the Gate job before waiting."
exit 3
