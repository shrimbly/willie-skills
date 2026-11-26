#!/usr/bin/env bash
# Shared Slack helpers for watch-slack.sh and watch-pr.sh. Source it; don't run it.
#
# Reads one Slack thread with the Web API (conversations.replies), so it needs a
# token in SLACK_TOKEN: a user token (xoxp-) or bot token (xoxb-) with
# channels:history, groups:history and reactions:read. users:read is optional and
# only turns user ids into names. A bot token reads only channels the bot is in.
#
# Nothing here prints to stdout except slack_diff, which prints one line per real
# change, so a caller can pass its output straight through as events.

SLACK_API="${SLACK_API:-https://slack.com/api}"
IGNORE_SLACK_USERS="${IGNORE_SLACK_USERS:-}"

# GET a Web API method. Sets SLACK_BODY to the JSON. Returns 1 on a network
# failure, 2 when Slack answered ok:false (the error is in SLACK_ERROR). Results go
# in globals, not stdout, because a $(...) subshell would lose SLACK_ERROR.
slack_api() {
  local method="$1"; shift
  SLACK_ERROR=""
  SLACK_BODY=$(curl -sS -m 20 -G "$SLACK_API/$method" \
    -H "Authorization: Bearer $SLACK_TOKEN" "$@" 2>/dev/null) || { SLACK_ERROR="network"; return 1; }
  if [ "$(jq -r '.ok' <<<"$SLACK_BODY" 2>/dev/null)" != "true" ]; then
    SLACK_ERROR=$(jq -r '.error // "bad response"' <<<"$SLACK_BODY" 2>/dev/null || echo "bad response")
    return 2
  fi
}

# Sets SLACK_SNAPSHOT to the whole thread as a compact JSON array, oldest first:
#   [{ts, user, bot, text, reactions: ["name user", ...]}, ...]
# Returns like slack_api.
slack_thread_snapshot() {
  local channel="$1" ts="$2" cursor="" all="[]"
  while :; do
    slack_api conversations.replies \
      --data-urlencode "channel=$channel" --data-urlencode "ts=$ts" \
      --data-urlencode "limit=200" ${cursor:+--data-urlencode "cursor=$cursor"} || return $?
    all=$(jq -c --argjson acc "$all" '$acc + [.messages[] | {
        ts,
        user: (.user // .bot_id // "unknown"),
        bot: ((.bot_id // "") != "" or (.subtype // "") == "bot_message"),
        text: ((.text // "") | gsub("\\s+"; " ") | .[0:120]),
        reactions: [(.reactions // [])[] | .name as $n | .users[] | "\($n) \(.)"]
      }]' <<<"$SLACK_BODY")
    cursor=$(jq -r '.response_metadata.next_cursor // ""' <<<"$SLACK_BODY")
    [ -z "$cursor" ] && break
  done
  SLACK_SNAPSHOT=$all
}

slack_name() {
  local name
  slack_api users.info --data-urlencode "user=$1" \
    && name=$(printf '%s' "$SLACK_BODY" | jq -r '.user | [.profile.display_name, .real_name] | map(select(. != null and length > 0)) | .[0] // empty' 2>/dev/null)
  printf '%s' "${name:-$1}"
}

# Print one line per reply or reaction that is in $2 but not in $1, skipping you
# ($3), bots and IGNORE_SLACK_USERS. The thread's own post is never a "new reply".
slack_diff() {
  local prev="$1" now="$2" me="$3" root_ts="$4" line kind who rest
  jq -r --argjson prev "$prev" --arg me "$me" --arg root "$root_ts" \
        --arg ignored "$IGNORE_SLACK_USERS" '
    ($ignored | split(",") | map(select(length>0))) as $skip
    | ($prev | map(.ts)) as $seen
    | ($prev | map(.ts as $t | .reactions[] | "\($t) \(.)")) as $seen_r
    | (.[] | select(.ts != $root and (.ts as $t | $seen | index($t) | not))
           | select(.user != $me and (.bot | not) and (.user as $u | $skip | index($u) | not))
           | "reply\t\(.user)\t\(.text)"),
      (.[] | .ts as $t | (if .ts == $root then "the post" else "a reply" end) as $where
           | .reactions[] | split(" ") as [$n, $u]
           | select($u != $me and ($skip | index($u) | not))
           | select(("\($t) \($n) \($u)") as $k | $seen_r | index($k) | not)
           | "reaction\t\($u)\t:\($n): on \($where)")
  ' <<<"$now" | while IFS=$'\t' read -r kind who rest; do
    case "$kind" in
      reply) printf 'Slack reply from %s: %s\n' "$(slack_name "$who")" "$rest" ;;
      reaction) printf 'Slack reaction from %s: %s\n' "$(slack_name "$who")" "$rest" ;;
    esac
  done
}

# Newest reply by one of the reviewers (comma-separated Slack ids), as epoch seconds.
slack_last_reviewer_reply() {
  local snapshot="$1" reviewers="$2" root_ts="$3"
  jq -r --arg r "$reviewers" --arg root "$root_ts" '
    ($r | split(",") | map(select(length>0))) as $ids
    | [.[] | select(.ts != $root and (.user as $u | $ids | index($u))) | .ts | split(".")[0] | tonumber]
    | max // empty' <<<"$snapshot"
}

# Preflight: prove the token can read this thread. On failure, explain on stderr
# and return non-zero, so the caller can fall back to connector checks.
slack_preflight() {
  local channel="$1" ts="$2" who="$3"
  if [ -z "${SLACK_TOKEN:-}" ]; then
    echo "$who: SLACK_TOKEN is not set, so this shell cannot read Slack. Check the thread with the Slack connector instead (watch-for-activity, 'Slack without a token')." >&2
    return 3
  fi
  slack_thread_snapshot "$channel" "$ts"
  case $? in
    0) return 0 ;;
    1) echo "$who: cannot reach $SLACK_API from this shell (blocked network?). Check the thread with the Slack connector instead." >&2; return 3 ;;
    *) echo "$who: Slack said '$SLACK_ERROR' for $channel/$ts. Check the token's scopes and the channel id and ts." >&2; return 3 ;;
  esac
}
