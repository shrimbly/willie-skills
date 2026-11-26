#!/usr/bin/env bash
# Watch one Slack thread and print a line only when someone else replies or reacts.
#
#   watch-slack.sh <channel-id> <thread-ts> <your-slack-user-id> [interval-seconds]
#
# Needs SLACK_TOKEN (see slack-thread.sh for scopes). Exits 3 before watching if the
# token is missing or cannot read the thread, so the caller knows to fall back to
# the Slack connector instead of trusting a watch that can never speak.
#
# Your own messages are skipped, and so are messages Claude sends for you: the
# Slack connector posts them as your user. Bots are skipped too.
#
# Optional:
#   ONCE=1                    exit after the first check that printed anything.
#   IGNORE_SLACK_USERS=U1,U2  more user ids to skip.

set -uo pipefail

CHANNEL="${1:?usage: watch-slack.sh <channel-id> <thread-ts> <your-slack-id> [interval]}"
TS="${2:?missing thread ts}"
ME="${3:?missing your slack user id}"
INTERVAL="${4:-300}"
ONCE="${ONCE:-}"

. "$(dirname "$0")/slack-thread.sh"

slack_preflight "$CHANNEL" "$TS" "watch-slack.sh" || exit 3
slack_thread_snapshot "$CHANNEL" "$TS" || exit 3
prev=$SLACK_SNAPSHOT

while true; do
  sleep "$INTERVAL"
  slack_thread_snapshot "$CHANNEL" "$TS"
  case $? in
    0) now=$SLACK_SNAPSHOT ;;
    1) continue ;;
    *)
      case "$SLACK_ERROR" in
        ratelimited) continue ;;
        thread_not_found|message_not_found) echo "Slack review post is gone ($SLACK_ERROR)"; exit 0 ;;
        *) echo "Slack watch stopped: Slack said '$SLACK_ERROR'"; exit 1 ;;
      esac ;;
  esac
  out=$(slack_diff "$prev" "$now" "$ME" "$TS")
  prev=$now
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    [ "$ONCE" = 1 ] && break
  fi
done
