#!/usr/bin/env bash
# Reply in one review thread, by the root comment's id, over REST.
#
#   reply.sh <owner/repo> <pr-number> <root-comment-id> "<text>"
#
# REST rather than `gh pr comment` or GraphQL: the gh wrappers trip a hidden
# mutation rate limit that refuses while `gh api rate_limit` still reports
# thousands of calls left.
set -uo pipefail
REPO="${1:?usage: reply.sh <owner/repo> <pr-number> <comment-id> <text>}"
PR="${2:?missing pr number}"
ID="${3:?missing root comment id}"
TEXT="${4:?missing reply text}"

gh api -X POST "repos/$REPO/pulls/$PR/comments/$ID/replies" -f body="$TEXT" \
  --jq '"replied \(.id) on \(.path):\(.line // .original_line)"'
