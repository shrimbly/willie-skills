---
name: dplat-review
description: "Post a review request for one or more pull requests to the #pillar3-dev-platform-code-reviews Slack channel, in the channel's convention, with the PR link, the Linear ticket link, and a preview link pointing at the page the change affects. Waits for the automated Cursor review and clears its findings before the PR is marked ready and before anything is posted. For ComfyUI_frontend PRs use fe-review instead. Use when asked to \"ask for review\", \"post to the code reviews channel\", \"send this PR for review\", \"/dplat-review PR-or-ticket\", or after opening a dev-platform PR that needs a reviewer."
---

# dplat-review

Post a review request for a dev-platform PR to **#pillar3-dev-platform-code-reviews** (channel id `C0C0MGTE78F`).

Input: one or more PR numbers or ticket ids (e.g. `1177`, `DPLAT-1818`), optionally a repo (default `Comfy-Org/platform`) and reviewers. One Slack message per PR.

## 1. Re-read the convention (every run — it drifts)

Read the last ~15 messages of `C0C0MGTE78F` with `slack_read_channel` (concise). Match what the team is doing now. At the time of writing, each post is:

```
[<repo-short>] <PR title without the ticket suffix> (<ticket link>)
<1–3 plain sentences: what was wrong, what changes, anything a reviewer must know (merge order, flags, no-op cases).>
PTAL <PR link> <@reviewer> …
```

- `<repo-short>` is the repo or service in brackets: `[platform]`, `[cloud]`, `[comfy-builder]`, `[platform-gateway]`, `[comfy-deploy]`, `[website]`.
- Links use Slack's `<url|label>` form: the ticket as `<https://linear.app/comfyorg/issue/DPLAT-1818|DPLAT-1818>`, the PR as `<https://github.com/Comfy-Org/platform/pull/1177|platform#1177>`.
- Plain English, short sentences, active voice, the user-visible effect first. No headers, no bullets unless several stacked PRs are listed (the channel lists stacks as bullets in merge order).
- The Slack app appends "Sent using Claude" by itself. Don't add it.

## 2. Gather the facts

```bash
${CLAUDE_SKILL_DIR}/scripts/pr-facts.sh <pr-or-ticket> [repo]
```

It returns JSON with the PR number, URL, title, ticket and ticket URL, the Vercel preview base URL for the head commit, the changed files, and the head of the PR body. Summarise from the body and the files. Never invent behaviour the PR doesn't describe.

## 3. Work out the preview link to the right page

The preview base is the deployment root. Point the link at the page the change is visible on:

- Map changed files to routes: `pages/profile/<x>.vue` → `/profile/<x>`; `pages/profile/builds/new.vue` → `/profile/builds/new`; `pages/index.vue` → `/`. For a component-only change, find the page that renders it (grep the component name under `pages/` and `layouts/`). A component used everywhere (layout, sidebar) → `/`.
- If the change only shows in a particular state, add the query or the step and say how to reach it in parentheses: `?onboarding=router`, "open a step taller than the window", "deploy a build to see the timer".
- Several affected pages: give the one or two that matter most.
- No preview found (CI still building, or a repo without Vercel previews such as cloud): say "preview building" or omit the line. Never invent a URL.

Verify the link returns 200 with `curl -s -o /dev/null -w "%{http_code}"` before posting. A protected preview's login page counts as fine.

Add a line `Preview: <url> (how to see it)` after the PTAL line.

## 4. Reviewers

Use the reviewers the user names. If none are named, default to Vinh (Slack `<@U0BU2EQ3GG1>`, GitHub `vqt123`) for every dev-platform PR, UI or not. Don't name Pablo unless the user asks for him. Look up any other name with `slack_search_users` and mention by id: `<@Uxxxx>`. Never guess an id.

On GitHub, request the same person after marking the PR ready (step 6), with REST, because the `gh pr edit` wrapper hits a hidden rate limit:

```bash
gh api -X POST repos/<owner>/<name>/pulls/<n>/requested_reviewers -f 'reviewers[]=vqt123'
```

The repo's assign-reviewers workflow adds its own assignees from `.github/reviewers.yml` on ready. Leave them alone. If `PabloWiedemann` shows up as a requested reviewer and the user didn't ask for him, remove him (`-X DELETE`, same endpoint).

## 5. Wait for the Cursor review, and clear it

**Do this before marking the PR ready and before any Slack message.** Nobody sees a PR the automated review has not cleared.

- Make sure the `cursor-review` label is on the PR. It is the only trigger. The `CI - Cursor Review` run reviews the head as of when the label was added, and skips a commit it already reviewed. So if the head moved since then, re-label with the `cursor-review` skill's `scripts/relabel.sh <repo> <n>`, not a bare remove/add. A label added right after a push can fire on the old head, and then no run ever reviews the new one. The script waits for the PR head to match, relabels, and confirms the Gate passed on that sha. Don't start waiting until it exits 0.
- Wait for `cloud-code-bot[bot]`'s review of the PR's head as labelled, on the change, not a timer: arm the watch from the `cursor-review` skill (step 1) and do other work until it fires. It takes 12–30 minutes. Tell the user it's running.
- Then work the findings with the `cursor-review` skill: triage, fix, verify, push, one-line reply per thread, and `resolve.sh` for the bot's threads.
- **Size the review to the risk. Don't re-label by reflex.** Platform is a dashboard. Most changes stay on one page, and a bug reaches one surface of it. So one Cursor pass is the default: fix and answer its findings, and don't run it again. Re-label for a second pass only when the change is gnarly: auth or sessions, billing or credits, data writes or deletes, a contract with another service (comfy-api, the builder, the gateway), timers or concurrency, or a component or layout that many pages share. For those, keep going until a pass comes back with nothing Medium or above, with three passes at most in all. If Medium-or-above findings remain after the third, stop and report them. A comment-only or test-only fix never needs a pass.
- Say in the report which call you made and why, in one line. Example: "one pass: a contained Home UI change, fixes answered, not re-run".

## 6. Clean up, then mark the PR ready for review

Before a reviewer sees it, run two passes over the PR's diff (`git diff origin/<base>...HEAD`), in the PR's own worktree:

1. `/clean-code` (the `clean-code` skill): naming, function size, comments that narrate, duplication.
2. `/code-review` (the `code-review` skill): correctness and bugs.
3. **Every open comment on the PR.** List the unresolved review threads (bots and people alike):

   ```bash
   gh api graphql -f query='query{repository(owner:"<owner>",name:"<name>"){pullRequest(number:<n>){reviewThreads(first:100){nodes{id isResolved path line comments(first:10){nodes{author{login} body}}}}}}}' \
     --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved|not)'
   ```

   Also read the top-level review bodies and PR comments (`gh pr view <n> --comments`) for requests that are not threads. Fix each one that needs fixing. Then reply to **every** thread in one line, saying what you changed and in which commit, or why you left it, and resolve it:

   ```bash
   gh api graphql -f query='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){comment{id}} resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' -f t=<threadId> -f b="<reply>"
   ```

   Rerun the query before marking ready: it must return nothing. No thread goes to review unanswered or unresolved.

Fix what is real, rerun the affected specs, commit and push (`--no-verify`). Note what you judged not worth changing and why, in one line each, in the report. If the PR lives in another workspace, ask that workspace's agent to do this rather than editing its branch yourself.

Asking for review means the PR is ready for review. If the PR is a draft, run `gh pr ready <n> --repo <repo>` before posting, so the reviewer's approval counts and the channel never sees a draft. Do it in the same run without asking, and say in the report that you did.

## 7. Send

The user asking for this skill counts as approval to post. Send one `slack_send_message` per PR to `C0C0MGTE78F`, then report each message link back in one line per PR. If the user asked to preview first, use `slack_send_message_draft` instead.

**Record the post,** so step 9 can find its thread later from any session or workspace. Write `~/.claude/superset-orchestrator/reviews/<owner>-<name>-<n>.json` (for example `Comfy-Org-platform-1780.json`):

```json
{"repo": "Comfy-Org/platform", "pr": 1780, "channel": "C0C0MGTE78F", "ts": "<message ts>", "permalink": "<message link>", "reviewers": [{"slack": "U0BU2EQ3GG1", "github": "vqt123"}], "postedAt": "<date -u +%Y-%m-%dT%H:%M:%SZ>", "bumps": []}
```

## 8. Watch the PR quietly, and bump the reviewer when it goes quiet

Start one background job straight after the post, in the same run, without asking. It says nothing until something real happens, then ends, so each event is one notification. Don't use a `CronCreate` job or a Monitor: every cron fire and every Monitor expiry or re-arm starts a visible turn, and a quiet day turns into a hundred "nothing new" messages.

```bash
ONCE=1 IDLE_HOURS=24 IDLE_REVIEWERS=vqt123 IDLE_SINCE=<the newest of postedAt and the last bump's "at"> \
  ${CLAUDE_SKILL_DIR}/../watch-for-activity/scripts/watch-pr.sh <owner/repo> <n> <your-gh-login> 300
```

Run it with Bash `run_in_background: true`. It ends on the first of these:
- a new comment or review thread;
- a review decision;
- red CI or a merge conflict;
- the PR merged or closed;
- `IDLE`: 24 hours with no comment or review from the reviewer on GitHub. It doesn't fire on a Saturday or Sunday (UTC), on a draft, or while threads wait on you.

When it ends, read the Slack thread (`slack_read_thread`, the record's `channel` and `ts`), then act:
- **Someone replied or reviewed, here or in Slack:** say in one line who said what. If it asks for a change, handle it the same way as step 6: fix, reply, and resolve bot threads only. Then bump the reviewer (step 9).
- **`IDLE`, and the Slack thread is quiet too:** bump the reviewer (below).
- **Merged, closed or approved:** stop.

After anything else, start the job again, with `IDLE_SINCE` set to the newest post, bump or reviewer reply. A reply in Slack restarts the clock as well, because the script sees only GitHub.

**The inactivity bump:** one line in the thread, with `slack_send_message` (`thread_ts` = the post's `ts`), mentioning the reviewer:

```
<@U0BU2EQ3GG1> bumping this one, it still needs your review. PTAL
```

Add one short clause only if something changed since they last looked, such as a merged parent PR.
- At most two inactivity bumps per round. After the second, don't bump again. Tell the user in one line, and let them chase it.
- Add each bump to the record's `bumps`: `{"kind": "idle", "ts": "<reply ts>", "at": "<date -u +%Y-%m-%dT%H:%M:%SZ>"}`.
- Don't bump if the user said they'll ping the reviewer, or if the PR went back to draft.

Say in the report that the watch is running, with its background task id.

## 9. When fixes land, bump the reviewer in the thread

Nothing tells a reviewer their feedback was addressed. GitHub doesn't re-request on a push, and Vinh works from the Slack thread. So whoever pushes the fixes for a person's review (on GitHub or in the thread) bumps that person, in the same run, without asking.

**When:** once per round of fixes, after all three of these are true:
- every one of that person's comments has a one-line reply;
- the fix commits are pushed;
- the Cursor pass, if step 5 calls for one, is answered.

Not per commit, and not for fixes that answer only the Cursor bot.

1. **Re-request on GitHub,** with REST. A POST re-requests someone who already reviewed:

   ```bash
   gh api -X POST repos/<owner>/<name>/pulls/<n>/requested_reviewers -f 'reviewers[]=vqt123'
   ```

2. **Reply in the review post's thread,** with `slack_send_message` (channel `C0C0MGTE78F`, `thread_ts` = the post's `ts`). Mention the reviewer, link the head commit, and say what changed in at most three short clauses:

   ```
   <@U0BU2EQ3GG1> addressed your feedback in <https://github.com/Comfy-Org/platform/pull/1780/commits/<sha>|<short sha>>: <what changed>. PTAL
   ```

   Add the preview line again only if the preview link changed.

3. **Record it and restart the watch.** Add `{"kind": "fixes", "ts": "<reply ts>", "at": "<date -u +%Y-%m-%dT%H:%M:%SZ>"}` to the record's `bumps`. Start step 8's job again, with `IDLE_SINCE` set to that time. A fixes bump starts a new round, so the two-bump limit resets.

**Finding the thread:**
1. Read `~/.claude/superset-orchestrator/reviews/<owner>-<name>-<n>.json`.
2. If it isn't there, search the channel for the PR link: `slack_search_public_and_private` with `<owner>/<name>/pull/<n> in:<#C0C0MGTE78F>`. Take the top-level message, and write the record for next time.
3. If the PR was never posted, don't start a new top-level post. Tell the user in one line.

**Don't bump when:**
- the reviewer approved and asked for nothing;
- the user said they'll ping the reviewer themselves.

Say in the report that you bumped them, with the reply's link.

## Don'ts

- Don't post, or mark ready, before the Cursor review has run and its findings are answered. Whether a fix round needs another pass depends on the risk (step 5).
- Don't post a PR that is still a draft. Step 6 marks it ready first.
- Don't push fixes for a person's review and stop there. Bump them in the thread (step 9).
- Don't let a review post go quiet for days. Step 8's watch bumps the reviewer after 24 hours, twice at most.
- Don't watch with a `CronCreate` job or a Monitor, and never post "nothing new".
- Don't paste the PR body, checklists or test counts. The PR holds those.
- Never include secrets, tokens or env values, even from the PR body.
