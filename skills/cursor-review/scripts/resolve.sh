#!/usr/bin/env bash
# Resolve every bot-opened review thread you have answered.
#
#   resolve.sh <owner/repo> <pr-number> [bot-login]
#
# Only threads whose ROOT comment is the bot's (default cloud-code-bot) and
# whose LAST comment is not the bot's — i.e. you replied — are resolved. A
# thread with no reply stays open, so an unanswered finding cannot be hidden.
# Human reviewers' threads are never touched: the human resolves those.
#
# Uses the bare graphql mutation, not a `gh pr` wrapper: the wrappers hit a
# hidden mutation rate limit that refuses while `rate_limit` says thousands
# remain.
set -uo pipefail
REPO="${1:?usage: resolve.sh <owner/repo> <pr-number> [bot-login]}"
PR="${2:?missing pr number}"
BOT="${3:-cloud-code-bot}"

ids=$(gh api graphql -F owner="${REPO%%/*}" -F repo="${REPO##*/}" -F number="$PR" -f query='
  query($owner:String!,$repo:String!,$number:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$number){
        reviewThreads(first:100){nodes{
          id isResolved path
          comments(first:20){nodes{author{login}}}
        }}}}}' \
| jq -r --arg bot "$BOT" '
  .data.repository.pullRequest.reviewThreads.nodes[]
  | select(.isResolved==false)
  | select(.comments.nodes[0].author.login==$bot)
  | select(.comments.nodes[-1].author.login!=$bot)
  | "\(.id) \(.path)"')

[ -z "$ids" ] && { echo "nothing to resolve (no answered $BOT threads)"; exit 0; }

while read -r id path; do
  gh api graphql -F id="$id" -f query='
    mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved } } }' \
    --jq '.data.resolveReviewThread.thread.isResolved' >/dev/null \
    && echo "resolved $path" || echo "FAILED $path ($id)"
done <<< "$ids"
