---
name: cursor-review
description: |
  Run the repo's automated Cursor code review on an open pull request and work
  its findings to a clean state: add the `cursor-review` label, wait for the
  review bot's inline comments (not on a timer — on the change), triage each
  finding by severity, fix what is real, verify, push, and answer every thread
  in one line, then resolve the bot's threads. Use when asked to "run cursor review",
  "get the automated review", "add the cursor-review label", "wait for the bot
  review and fix", or "/cursor-review [pr-number]".
allowed-tools: Bash Read Edit Write Monitor
---

# Cursor review on a pull request

One label starts it. One bot review comes back. You answer every thread.

`$ARGUMENTS` is the PR number, optional. Without it, use the PR for the current
branch (`gh pr view --json number`).

## What the machinery looks like (Comfy-Org/platform)

- **Trigger:** the `cursor-review` label on the PR. Nothing else starts it.
- **Reviewer:** `cloud-code-bot[bot]`. It posts ONE pull-request review, state
  `COMMENTED`, with inline comments. Each comment opens with a severity mark:
  `🔴 Critical`, `🟡 Medium`, `🟢 Low`, `⚪ Nit`.
- **What runs:** the `CI - Cursor Review` workflow. A gate job checks the
  label and whether this commit was already reviewed, a diff-size job caps
  what it will read, then a PANEL runs: 4 models x 2 lenses (`adversarial`,
  `edge-case`) as 8 parallel jobs, each with its own "Run cursor review"
  step. An aggregation step merges the findings and posts them as one review.
  Nothing appears on the PR until the slowest panel job finishes.
- **Latency:** 12 to 15 minutes on a 200-line diff; 30+ minutes on a
  1,200-line one, because one panel model is usually much slower than the
  rest. To see where it is:

  ```bash
  gh run list --repo <owner/repo> --branch <branch> --workflow "CI - Cursor Review" --limit 1 --json databaseId,status
  gh api repos/<owner/repo>/actions/runs/<id>/jobs --jq '.jobs[] | "\(.name): \(.status)/\(.conclusion // "-")"'
  ```

  A job still `in_progress` on "Run cursor review" is working, not hung. If
  the run is `completed` and there is no review on the PR, read the gate
  job: the usual causes are a missing label, a draft PR, or a commit the bot
  already reviewed.
- **A push re-triggers nothing by itself.** The gate refuses a commit it
  already reviewed, so a new commit plus re-adding the label (remove, then
  add) gets a second pass. **Use `scripts/relabel.sh`, never a bare
  remove/add.** The label event reviews whatever head GitHub has *at that
  moment*. Straight after a push that is often still the old commit, so the run
  reviews or cancels on the old head and nothing ever runs on the new one. The
  script waits for the PR head to match the pushed sha, relabels, and exits 0
  only once a run's Gate has passed on that sha (platform#1256, 1 Oct 2026).

## Step 1 — label, prove it started, and seed the watch

```bash
${CLAUDE_SKILL_DIR}/scripts/relabel.sh <owner/repo> <n> [sha]   # default sha: local HEAD
```

It covers the first label and any re-label. Do not arm a watch until it exits
0: a watch on a run that never started waits the full half hour for nothing.
Exit 2 means the push has not reached the PR. Exit 3 means no run passed its
gate. Read the Gate job and say what it said; don't wait longer.

The review can come back with **no inline threads**: when the bot cannot
anchor its findings to the diff, it lists them all in the review body ("Inline
comments could not be anchored"). A thread-count watch never fires on that.
So also watch for the review itself, and when it lands, read the body as well
as the threads:

```bash
gh api repos/<owner/repo>/pulls/<n>/reviews --jq '.[] | select(.user.login=="cloud-code-bot[bot]") | .commit_id[0:9]'
```

Answer body-only findings in one PR comment, a line per finding. There are no
threads to resolve.

Then arm a watch that fires on the review, not on the clock. The
`watch-for-activity` skill's `scripts/watch-pr.sh` already does this: it counts
review threads whose LAST comment is not yours, and prints a line only when that
count changes. Run it with a 60-second interval (this is a bot, not a human):

```
Monitor({
  command: "${CLAUDE_SKILL_DIR}/../watch-for-activity/scripts/watch-pr.sh <owner/repo> <n> <your-login> 60",
  description: "PR #<n>: cursor-review threads",
  timeout_ms: 1800000,
})
```

Do not poll by hand and do not sleep. Work on something else until it fires.

## Step 2 — read every thread in full

`${CLAUDE_SKILL_DIR}/scripts/threads.sh <owner/repo> <n>` prints each unresolved thread: its id,
severity, file:line, and the full body, with any replies indented under it.
`ALL=true` includes resolved threads, for reading a past round. Read all of
them before touching code. The bot's findings are ordered by file, not by
severity; a Critical can sit last.

Each finding ends with `Raised by K of 8 reviewers (...)`: the review is a
panel of models, and K is how many independently flagged it. A 1-of-8 Nit
is one model's taste; a 3-of-8 Medium is worth believing before you read it
twice.

## Step 3 — triage, then fix

For each finding decide one of three things, and write the decision down before
you edit:

| Verdict | What it means | What you do |
|---|---|---|
| **Fix** | The finding is real and in scope. | Change the code. Add a test if the finding is a behaviour. |
| **Narrow** | The code is fine, but a comment or claim over-promises. | Fix the comment or the test name, not the behaviour. |
| **No change** | The finding is wrong, out of scope, or by design. | Say why, in one or two sentences, with the fact that settles it. |

Rules of thumb from past rounds:

- The panel and a human reviewer often flag the same line. Fix once, and
  reply on both threads naming the one commit.
- Two findings can be one bug seen from two sides (a rule split mid-block,
  and a rule that never matched). Read all threads before the first edit.

- A `🟢 Low` about a comment that claims more than the code does is a **Narrow**,
  and it is nearly always right.
- A `🟡 Medium` about an env var, a fallback, or a guard is usually a **Fix**;
  the bot is good at `??` vs `||`, empty-string cases, and discarded errors.
- A `⚪ Nit` is a **No change** unless the fix is one line.
- Never widen the PR to satisfy a finding. Out of scope goes in the reply.
- A structural finding (a duplicated helper, a missing abstraction, "this should
  live in X") is not a one-PR fix. If the work has an area design note, use the
  piece the note names. If the note has none, answer **No change** for now, say
  the finding is raised with the area's design owner, and report it. Don't add a
  new local helper to satisfy the bot. That's how sibling PRs end up solving the
  same problem several ways.
- **Three passes at most.** The first review plus two fix rounds. If findings of
  Medium or above remain after the third, stop and report them. Don't run a fourth.
  Looping on the bot until it's clean drifts the design one finding at a time.

## Step 4 — verify like a first submission

Run the repo's suite in full, not just the file you touched:

```bash
npm run test:unit && npm run lint && npx nuxi typecheck && npm run format:check
```

A review fix breaks things at least as often as a first draft.

Run the unit suite ALONE. Another vitest on the machine (the pre-push hook
of your own earlier push, another workspace's run) makes unrelated specs
time out at 5 to 20 seconds each. If you see a handful of slow failures in
files you did not touch, check `pgrep -fl vitest` and rerun before you read
a single stack trace.

## Step 5 — commit, push, reply per thread

One commit for the round, in the repo's commit style. Push with
`--force-with-lease` only if you rebased; otherwise a plain push.

Then answer **every** thread, one line each, naming the commit. The
script takes four separate arguments; in zsh a `"owner/repo n"` variable
stays one word and the script refuses with "missing reply text":

```bash
${CLAUDE_SKILL_DIR}/scripts/reply.sh <owner/repo> <n> <comment-id> "Fixed in \`<sha>\`. <what changed, one clause>."
${CLAUDE_SKILL_DIR}/scripts/reply.sh <owner/repo> <n> <comment-id> "Narrowed in \`<sha>\`: <what the comment now claims>."
${CLAUDE_SKILL_DIR}/scripts/reply.sh <owner/repo> <n> <comment-id> "No change. <the fact that settles it>."
```

`reply.sh` uses the REST endpoint
(`pulls/<n>/comments/<id>/replies`), not `gh pr comment` or a GraphQL mutation:
the `gh pr` wrappers hit a hidden mutation rate limit that refuses while
`rate_limit` still says thousands remain.

Then **resolve the bot's threads you answered**:

```bash
${CLAUDE_SKILL_DIR}/scripts/resolve.sh <owner/repo> <n>
```

It resolves only threads the bot opened AND you replied on; an unanswered
finding stays open, and a human reviewer's thread is never touched — the
human resolves those. Willie's rule (25 Sep 2026): the automated review's
threads are yours to close once answered; leaving them open makes the human
reviewer wade through the bot's findings to reach their own.

## Step 6 — hand back

Re-request review from the humans on the PR
(`gh api -X POST repos/<owner/repo>/pulls/<n>/requested_reviewers -f 'reviewers[]=<login>'`),
then report in one short block: how many findings, how many fixed, how many
declined and why, the commit, that the bot's threads are resolved, and the
verification results. Nothing else.

## Traps

- `gh api --jq` takes no `--arg`; a filter that needs a variable must pipe to
  real `jq`, or it fails silently and looks like "no findings".
- In jq, `|` rebinds `.`. Bind `.user.login as $who` before comparing.
- A watch that never fires and a PR with no findings look the same. If the
  monitor expires with no events, read the threads once by hand before
  concluding the bot found nothing.
- The bot comments on the diff as of the review; a later push moves lines.
  Reply on the original comment id anyway — GitHub keeps the thread.
- `watch-pr.sh` exits on APPROVED. If a human approves while the panel is
  still running, the watch ends before the bot posts: re-arm it (or a
  smaller loop on the review-comment count) until `cloud-code-bot[bot]`
  appears in the PR's reviews.
- One panel model can be cancelled at the job ceiling; the consolidation
  still posts with "7/8 reviewers contributed". That is a complete review.
