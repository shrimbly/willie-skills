---
name: watch-for-activity
description: |
  Watch something that changes on someone else's schedule — a pull request, a CI
  run, a deploy, a queue — and get told when it actually changes, not on a timer.
  Arms a persistent background monitor that reports only differences, filters out
  your own activity, and covers every terminal state so silence never reads as
  success. Also watches a PR's Slack review thread for replies and reactions.
  Use when asked to "poll for review", "watch the PR", "keep an eye on CI", "let
  me know when it's approved", "check on the deploy", "wait for X and then do Y",
  or whenever you are about to wait on something outside your control.
---

# Watch for activity

The job is to notice a change and act on it. It is not to produce a heartbeat.

An agent that reports "still waiting" every hour has spent the user's attention
to tell them nothing. An agent that reports the moment a review lands, and stays
silent otherwise, costs nothing until it is useful.

> **The rule: one notification per real change. Zero for the quiet.**

## Arm it once, persistently

Use `Monitor` with `persistent: true`. A monitor with a timeout expires and makes
you re-arm it, and every re-arm is a turn spent saying nothing happened.

```
Monitor({
  command: "<change-detecting loop, below>",
  description: "PR #678 approval, new threads, CI failures, conflicts",
  persistent: true,
})
```

Before arming a replacement, `TaskStop` the old one. Two watchers on the same
thing means every event arrives twice, and the duplicate looks like a second
event rather than an echo.

## The shape of the loop

Stdout is the event stream: **one line out means one notification.** So the loop
prints nothing unless a value differs from the value it saw last time.

```bash
prev_state=$(fetch_state)          # seed BEFORE looping — see "Do not announce the start"
prev_count=$(fetch_count)
while true; do
  sleep 300
  now=$(fetch_state) || continue   # a failed request must not kill the watch
  [ "$now" != "$prev_state" ] && { echo "state: $prev_state -> $now"; prev_state=$now; }
  # ... one of these per thing you track ...
  [ "$now" = "DONE" ] && { echo "DONE — acting now"; break; }
done
```

Four things that loop must get right.

### 1. Seed the previous value before the first iteration

Do not announce the starting state. A watch armed on a PR that is already
`REVIEW_REQUIRED` must not fire "review decision: REVIEW_REQUIRED" — that is the
status quo, and reporting it teaches the user to ignore the next one. Read the
current value into `prev_*` before the loop begins.

### 2. Filter out your own activity

You push, you comment, you reply. If the watch counts those, it wakes you to tell
you what you just did. Exclude anything whose author is you:

```bash
--jq '[.nodes[] | select(.isResolved==false and (.comments.nodes[0].author.login!="YOUR_LOGIN"))] | length'
```

Take the **last** comment in a thread, not the first: a thread you have already
answered is not waiting on you, even though the first comment is not yours.

Test the filter both ways before you trust it. A watch that never fires and a
watch with nothing to report look identical from the outside. Run it once against
a deliberately wrong seed value to prove it *can* speak, and once against the
real seed to prove it stays quiet.

### 3. Cover every terminal state — silence is not success

Ask: *if this thing failed right now, would my loop print anything?* If not,
widen it. A watch that only knows how to say "approved" sits mute through a
rejection, a red build, and a conflict, and mute is indistinguishable from
"still going".

At minimum, emit on: the success you want, every failure, and the thing
disappearing (closed, cancelled, deleted).

### 4. Match the interval to what you are waiting for

| Waiting on | Interval |
|---|---|
| Human review | 300s. People do not review in bursts of seconds. |
| A running CI job | 45–120s |
| A remote API you do not own | 30s minimum, or you will be rate-limited |
| A local file or process | 1–5s |

## Worked example: a GitHub pull request

`scripts/watch-pr.sh` in this skill is the whole thing, parameterised:

```bash
${CLAUDE_SKILL_DIR}/scripts/watch-pr.sh <owner/repo> <pr-number> <your-github-login>
```

It fires on, and only on: the review decision changing, a new comment by someone
else, a review thread left waiting on you, a check going red, merge conflicts
appearing, and the PR leaving `OPEN`. It exits when the decision is `APPROVED` or
`CHANGES_REQUESTED`, because both mean it is your turn again.

Pass it to `Monitor` as the `command`.

Two opt-in modes, both env vars:
- `ONCE=1` ends the script after the first check that printed anything. Run it with Bash `run_in_background: true` when one event should mean one notification, with no Monitor expiry to re-arm.
- `IDLE_HOURS=24 IDLE_SINCE=<post or last bump, YYYY-MM-DDTHH:MM:SSZ> IDLE_REVIEWERS=<login>` also ends it with an `IDLE:` line when the reviewer has said nothing on GitHub for that long. It never fires at weekends (UTC), on a draft, or while threads wait on you. `dplat-review` step 8 uses it to bump a quiet review.

Bookkeeping bots are skipped — the link-back, the deploy URL. They re-comment on
their own schedule and none of it is addressed to you. Review bots are
deliberately kept, because CodeRabbit and its like post findings you must answer.
Change the list with `IGNORE_LOGINS="a[bot],b[bot]"`.

## Watching the Slack review thread too

A review request lives in two places: the PR and its post in a Slack review
channel. Reviewers often answer in Slack, or just react with :eyes: or
:white_check_mark:, and GitHub shows none of it. A watch that reads only GitHub
sits mute through all of that, so watch the thread as well.

You need the thread's channel id and `ts`. They are in the review record that
`dplat-review` writes when it posts (`channel`, `ts`), or in the post's link:
`.../archives/<channel>/p<ts without the dot>`.

The same rules apply: seed first, report only replies and reactions by someone
else, skip your own messages, and never heartbeat. Messages Claude posts for you
through the Slack connector are sent as your user ("Sent using Claude"), so
skipping your own Slack id skips those too.

### With a token: one background job for both

A shell loop can read Slack only through the Web API, with a token in
`SLACK_TOKEN`: a user token (`xoxp-`) or bot token (`xoxb-`) with
`channels:history`, `groups:history` and `reactions:read` (`users:read` turns ids
into names). Add the thread to the PR watch:

```bash
SLACK_THREAD=<channel-id>/<ts> SLACK_ME=<your-slack-id> IDLE_SLACK_REVIEWERS=<their-slack-id> \
  ${CLAUDE_SKILL_DIR}/scripts/watch-pr.sh <owner/repo> <pr-number> <your-github-login>
```

It then also fires on a new reply or reaction in the thread by anyone but you and
bots, and a reply from `IDLE_SLACK_REVIEWERS` restarts the `IDLE` clock, so
`IDLE` means quiet on GitHub and in Slack. `scripts/watch-slack.sh <channel-id>
<ts> <your-slack-id>` watches a thread on its own, with the same `ONCE=1`.

Both check the token before they start. If it is missing, cannot reach Slack or
cannot read the thread, they **exit 3** with the reason on stderr, before
watching anything. Don't drop `SLACK_THREAD` and carry on as if Slack were
covered: use the connector, below. If Slack starts refusing mid-watch, the PR
watch says `Slack watch stopped` once and keeps watching GitHub.

### Without a token: the Slack connector, on wake

The Slack connector (`slack_read_thread`) is an MCP tool. Only you can call it; a
shell loop cannot. Cloud threads are in this case today: the environment's
network policy blocks `slack.com` (the proxy answers 403), and it holds no Slack
token. Adding `slack.com` to the allowlist and a token to the environment's
secrets would let a cloud thread use the token path instead. Until then:

1. **Seed when you arm the PR watch.** Read the thread with `slack_read_thread`
   and keep the newest reply's `ts` and the reactions you saw. Put them in the
   review record as `"slackSeen": {"ts": "<newest reply ts>", "reactions":
   ["white_check_mark U0BU2EQ3GG1", ...]}`, so a later session starts from them
   rather than announcing old replies.
2. **Read it again every time you wake for this PR**: the PR watch firing, `IDLE`,
   the person writing to you. Report only replies newer than `slackSeen.ts` and
   reactions not in the list, by someone else. Then update `slackSeen`.
3. **In a cloud thread, add spaced check-ins.** Set a `send_later` reminder 1 hour
   after the post, then 2 hours after that, then 4. A check-in that finds nothing
   new ends with no reply. Stop scheduling once the review is answered, the PR
   leaves review, or after the third, when the `IDLE` fire and the Review bump
   task cover it.

The trade-off: a Slack reply is noticed at the next wake, which can be hours
late, rather than within five minutes, and every check-in costs a model turn,
where a shell poll costs nothing. Reading the thread before any bump (step 2)
keeps the costly mistake, bumping someone who already answered in Slack, from
happening.

### Two traps this script already fell into

**`gh api --jq` takes no `--arg`.** Hand it one and the whole filter fails
*silently* — you get an empty result that looks exactly like "nothing new". Pipe
to real `jq` when you need variables.

**In jq, `|` rebinds `.`.** `select(.user.login != $me and ($ignored | index(.user.login)))`
does not work: after `$ignored |`, `.` is `$ignored`, so `.user.login` indexes an
array. Bind first — `.user.login as $who` — then compare. Both of these produce
*silence*, which in a watch is the most expensive possible failure.

## When it fires, act — do not just relay

The point of noticing is the next move.

- **Approved** → do the thing you were waiting to do, if you were told to. Check
  the merge state and CI are still good first; an approval from an hour ago says
  nothing about a conflict from a minute ago.
- **Changes requested / new thread** → read every unresolved thread in full,
  fix, reply per thread, re-request review. Do not resolve threads yourself.
- **Conflicts** → rebase, re-run the *whole* verification, force-with-lease.
- **CI red** → the next section.

## A red check is not the same as a failed test

Before reporting a failure, find out where the job died. These are different
facts and they lead to different actions:

| What you see | What it might be | How to tell |
|---|---|---|
| Job red | A test failed | The test step ran and reported failures |
| Job red | The job never ran a test | The test step is `skipped`; an earlier step is `cancelled` |
| Job red, ~6h | The platform's job ceiling | Duration is suspiciously round; a setup step never completed |

```bash
gh api repos/<owner>/<repo>/actions/jobs/<job-id> \
  --jq '.steps[] | "\(.status)\t\(.conclusion // "-")\t\(.name)"'
```

A job that hung in dependency installation and was killed at the timeout has told
you nothing about your code. Saying "CI is failing" there is inaccurate, and it
sends the user hunting for a bug that does not exist.

### Re-running

Re-run **once**, and say why in the same breath. If it fails the same way twice,
stop re-running and get evidence of blast radius instead — check whether other
branches are hitting it:

```bash
gh run list --repo <owner/repo> --workflow ci.yml --limit 15 \
  --json databaseId,headBranch,status,conclusion
```

An unrelated branch stuck on the identical step turns "my PR is broken" into "the
pipeline is broken", which is a different problem with a different owner. Report
it; do not quietly patch shared CI config that was not in your scope.

**Never re-run until green.** A flaky *test* gets named as flaky, with the failure
mode and a passing re-run as evidence. Re-running to make red go away hides the
thing the user needed to know.

## What to say when it fires

State the change and what you did about it. Nothing else.

| Do not write | Write |
|---|---|
| Still waiting on review, no movement yet. | *(say nothing)* |
| CI is failing! | e2e (1) and (3) were killed at the 6h ceiling inside `install-deps`. No test ran. |
| I'll keep monitoring and let you know. | *(implied — you already armed the watch)* |

If the user asks for a status while nothing has changed, answer with the current
state and stop. That is a reply, not a heartbeat.
