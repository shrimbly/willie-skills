#!/usr/bin/env bash
# Print every unresolved review thread on a PR, in full.
#
#   threads.sh <owner/repo> <pr-number>
#
# One block per thread: the root comment id (reply to THIS id), severity, file
# and line, author, and the body. Replies already in the thread follow,
# indented, so a thread you have answered reads as answered.
set -uo pipefail
REPO="${1:?usage: threads.sh <owner/repo> <pr-number>}"
PR="${2:?missing pr number}"

gh api graphql -F owner="${REPO%%/*}" -F repo="${REPO##*/}" -F number="$PR" -f query='
  query($owner:String!,$repo:String!,$number:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$number){
        reviewThreads(first:100){nodes{
          isResolved isOutdated path line originalLine
          comments(first:20){nodes{databaseId author{login} body}}
        }}}}}' \
| jq -r --argjson all "${ALL:-false}" '
  .data.repository.pullRequest.reviewThreads.nodes[]
  | select(.isResolved==false or $all)
  | . as $t
  | ($t.comments.nodes[0]) as $root
  | "=== thread root=\($root.databaseId) \($t.path):\($t.line // $t.originalLine)\(if $t.isOutdated then " (outdated)" else "" end) by \($root.author.login)\n\($root.body)\n"
    + ([$t.comments.nodes[1:][] | "    ↳ \(.author.login): \(.body)"] | join("\n"))
    + "\n"'
