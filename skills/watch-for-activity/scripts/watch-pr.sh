#!/usr/bin/env bash
# Watch one GitHub pull request and print a line only when something changes.
#
#   watch-pr.sh <owner/repo> <pr-number> <your-github-login> [interval-seconds]
#
# Pass as the `command` of a persistent Monitor, or run it in the background with
# ONCE=1. Every line of stdout becomes one notification, so this prints nothing
# while the PR is quiet. It exits when the review decision reaches APPROVED or
# CHANGES_REQUESTED, or the PR leaves OPEN.
#
# Optional, all off by default:
#   ONCE=1            exit after the first check that printed anything. Use it for a
#                     background job that must end on the first real event.
#   IDLE_HOURS=24     also report when the reviewer has said nothing for this long,
#                     then exit. Needs IDLE_SINCE. Never fires on a Saturday or a
#                     Sunday (UTC), on a draft, or while threads wait on you.
#   IDLE_SINCE=<t>    when the clock starts: the review post or the last bump, as
#                     YYYY-MM-DDTHH:MM:SSZ. Newer activity by the reviewer restarts it.
#   IDLE_REVIEWERS=a,b  whose activity counts. Default: anyone but you and bots.
#   SLACK_THREAD=<channel-id>/<ts>  also watch the PR's Slack review thread: new
#                     replies and reactions by others. Needs SLACK_TOKEN and SLACK_ME
#                     (your Slack user id). Exits 3 at once if it cannot read the
#                     thread, so you never trust a Slack watch that can't speak.
#   IDLE_SLACK_REVIEWERS=U1,U2  Slack ids whose replies restart the IDLE clock.

set -uo pipefail

REPO="${1:?usage: watch-pr.sh <owner/repo> <pr-number> <your-login> [interval]}"
PR="${2:?missing pr number}"
ME="${3:?missing your github login}"
INTERVAL="${4:-300}"
ONCE="${ONCE:-}"
IDLE_HOURS="${IDLE_HOURS:-}"
IDLE_SINCE="${IDLE_SINCE:-}"
IDLE_REVIEWERS="${IDLE_REVIEWERS:-}"
SLACK_THREAD="${SLACK_THREAD:-}"
SLACK_ME="${SLACK_ME:-}"
IDLE_SLACK_REVIEWERS="${IDLE_SLACK_REVIEWERS:-}"

if [ -n "$IDLE_HOURS" ] && [ -z "$IDLE_SINCE" ]; then
  echo "watch-pr.sh: IDLE_HOURS needs IDLE_SINCE (the post or last bump, YYYY-MM-DDTHH:MM:SSZ)" >&2
  exit 2
fi

# Bots that comment on every PR as bookkeeping — a link-back, a deploy URL. They
# redeploy and re-comment on their own schedule, so counting them wakes you for
# something nobody said. Review bots are deliberately NOT here: CodeRabbit and
# friends post findings you have to answer. Override with IGNORE_LOGINS.
IGNORE_LOGINS="${IGNORE_LOGINS:-vercel[bot],linear-code[bot],github-actions[bot]}"
ignored_jq=$(jq -nc --arg s "$IGNORE_LOGINS" '$s | split(",") | map(select(length>0))')
reviewers_jq=$(jq -nc --arg s "$IDLE_REVIEWERS" '$s | split(",") | map(select(length>0))')

slack_channel=""
slack_ts=""
if [ -n "$SLACK_THREAD" ]; then
  slack_channel="${SLACK_THREAD%%/*}"
  slack_ts="${SLACK_THREAD##*/}"
  if [ -z "$SLACK_ME" ] || [ "$slack_channel" = "$SLACK_THREAD" ]; then
    echo "watch-pr.sh: SLACK_THREAD is <channel-id>/<ts> and needs SLACK_ME (your Slack user id)" >&2
    exit 2
  fi
  . "$(dirname "$0")/slack-thread.sh"
  slack_preflight "$slack_channel" "$slack_ts" "watch-pr.sh" || exit 3
fi

printed=0
say() { printf '%s\n' "$*"; printed=1; }

# macOS date first, then GNU. Prints nothing for a value it cannot read.
to_epoch() {
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s 2>/dev/null
}

threads_awaiting_me() {
  gh api graphql -F owner="${REPO%%/*}" -F repo="${REPO##*/}" -F number="$PR" -f query='
    query($owner:String!,$repo:String!,$number:Int!){
      repository(owner:$owner,name:$repo){
        pullRequest(number:$number){
          reviewThreads(first:100){nodes{
            isResolved
            comments(last:1){nodes{author{login}}}
          }}
        }}}' \
    --jq "[.data.repository.pullRequest.reviewThreads.nodes[]
           | select(.isResolved==false and (.comments.nodes[0].author.login!=\"$ME\"))]
          | length" 2>/dev/null
}

failing_checks() {
  gh pr checks "$PR" --repo "$REPO" --json name,bucket 2>/dev/null \
    | jq -r '[.[] | select(.bucket=="fail") | .name] | join(", ")'
}

comment_count() {
  gh api "repos/$REPO/issues/$PR/comments" --jq 'length' 2>/dev/null
}

# Newest comment, review or inline comment by the reviewer, as YYYY-MM-DDTHH:MM:SSZ.
# With no IDLE_REVIEWERS, anyone but you, the ignored logins and any [bot] counts.
last_reviewer_activity() {
  local filter='.user.login as $who
    | select(if ($reviewers|length) > 0 then ($reviewers|index($who))
             else ($who != $me and ($ignored|index($who)|not) and ($who|endswith("[bot]")|not)) end)'
  {
    gh api "repos/$REPO/issues/$PR/comments" --paginate 2>/dev/null \
      | jq -r --arg me "$ME" --argjson ignored "$ignored_jq" --argjson reviewers "$reviewers_jq" ".[] | $filter | .created_at"
    gh api "repos/$REPO/pulls/$PR/reviews" --paginate 2>/dev/null \
      | jq -r --arg me "$ME" --argjson ignored "$ignored_jq" --argjson reviewers "$reviewers_jq" ".[] | $filter | .submitted_at // empty"
    gh api "repos/$REPO/pulls/$PR/comments" --paginate 2>/dev/null \
      | jq -r --arg me "$ME" --argjson ignored "$ignored_jq" --argjson reviewers "$reviewers_jq" ".[] | $filter | .created_at"
  } | sort | tail -1
}

# Seed from the current state so the starting values are never announced.
prev_decision=$(gh pr view "$PR" --repo "$REPO" --json reviewDecision --jq '.reviewDecision // "NONE"' 2>/dev/null || echo "NONE")
prev_comments=$(comment_count || echo 0)
prev_threads=$(threads_awaiting_me || echo 0)
prev_conflict=""
prev_slack=""
if [ -n "$slack_channel" ]; then
  slack_thread_snapshot "$slack_channel" "$slack_ts" || exit 3
  prev_slack=$SLACK_SNAPSHOT
fi

while true; do
  sleep "$INTERVAL"
  printed=0

  pr=$(gh pr view "$PR" --repo "$REPO" --json reviewDecision,mergeStateStatus,state,isDraft 2>/dev/null) || continue

  state=$(jq -r '.state' <<<"$pr")
  if [ "$state" != "OPEN" ]; then
    say "PR #$PR is now $state"
    break
  fi

  decision=$(jq -r '.reviewDecision // "NONE"' <<<"$pr")
  [ -z "$decision" ] && decision="NONE"
  if [ "$decision" != "$prev_decision" ]; then
    say "review decision: $prev_decision -> $decision"
    prev_decision=$decision
  fi

  # Edge-triggered: a PR that stays conflicted must not say so every cycle.
  conflict=$(jq -r '.mergeStateStatus' <<<"$pr")
  if [ "$conflict" = "DIRTY" ] && [ "$prev_conflict" != "DIRTY" ]; then
    say "MERGE CONFLICTS — mergeStateStatus DIRTY"
  fi
  prev_conflict=$conflict

  fails=$(failing_checks)
  if [ -n "$fails" ] && [ "$fails" != "${prev_fails:-}" ]; then
    say "CI FAILING: $fails"
    say "  (check where each job died before calling it a test failure)"
  fi
  prev_fails=$fails

  comments=$(comment_count) || comments=$prev_comments
  if [ "$comments" -gt "$prev_comments" ] 2>/dev/null; then
    # Piped to jq rather than `gh --jq`: gh's built-in filter takes no --arg,
    # and the whole expression fails silently if you hand it one.
    new=$(gh api "repos/$REPO/issues/$PR/comments" 2>/dev/null \
      | jq -r --arg me "$ME" --argjson ignored "$ignored_jq" \
          ".[$prev_comments:][]
           | .user.login as \$who
           | select(\$who != \$me and (\$ignored | index(\$who) | not))
           | \"new comment from \(\$who)\"")
    [ -n "$new" ] && say "$new"
    prev_comments=$comments
  fi

  if [ -n "$slack_channel" ]; then
    slack_thread_snapshot "$slack_channel" "$slack_ts"
    case $? in
      0)
        slack_now=$SLACK_SNAPSHOT
        slack_new=$(slack_diff "$prev_slack" "$slack_now" "$SLACK_ME" "$slack_ts")
        [ -n "$slack_new" ] && say "$slack_new"
        prev_slack=$slack_now ;;
      1) ;;
      *)
        if [ "$SLACK_ERROR" != "ratelimited" ]; then
          say "Slack watch stopped: Slack said '$SLACK_ERROR'. GitHub is still watched; check the thread with the Slack connector"
          slack_channel=""
        fi ;;
    esac
  fi

  threads=$(threads_awaiting_me) || threads=$prev_threads
  if [ -n "$threads" ] && [ "$threads" != "$prev_threads" ] && [ "$threads" != "0" ]; then
    say "review threads awaiting you: $threads"
    prev_threads=$threads
  fi

  case "$decision" in
    APPROVED) say "APPROVED — your turn"; break ;;
    CHANGES_REQUESTED) say "CHANGES REQUESTED — your turn"; break ;;
  esac

  # Reviewer silence. Only while the ball is in their court: no threads waiting on
  # you, not a draft, not yet decided. Weekends never fire; the hours still count,
  # so a Friday post that ran out over the weekend fires on Monday (UTC).
  if [ -n "$IDLE_HOURS" ] && [ "$printed" = 0 ] && [ "$(date -u +%u)" -lt 6 ] \
     && [ "$(jq -r '.isDraft' <<<"$pr")" = "false" ] && [ "${threads:-0}" = "0" ]; then
    since=$(to_epoch "$IDLE_SINCE")
    if [ -n "$since" ]; then
      last=$(last_reviewer_activity)
      if [ -n "$last" ]; then
        l=$(to_epoch "$last")
        [ -n "$l" ] && [ "$l" -gt "$since" ] && since=$l
      fi
      if [ -n "$slack_channel" ] && [ -n "$IDLE_SLACK_REVIEWERS" ]; then
        l=$(slack_last_reviewer_reply "$prev_slack" "$IDLE_SLACK_REVIEWERS" "$slack_ts")
        [ -n "$l" ] && [ "$l" -gt "$since" ] && since=$l
      fi
      now=$(date -u +%s)
      if [ $(( now - since )) -ge $(( IDLE_HOURS * 3600 )) ]; then
        if [ -n "$slack_channel" ]; then
          say "IDLE: no word from ${IDLE_REVIEWERS:-the reviewer} on GitHub or in the Slack thread for $(( (now - since) / 3600 ))h. Bump"
        else
          say "IDLE: no word from ${IDLE_REVIEWERS:-the reviewer} on GitHub for $(( (now - since) / 3600 ))h. Read the Slack thread, then bump"
        fi
        break
      fi
    fi
  fi

  [ "$ONCE" = 1 ] && [ "$printed" = 1 ] && break
done
