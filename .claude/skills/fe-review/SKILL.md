---
name: fe-review
description: "Post a review request for one or more ComfyUI frontend pull requests to the #frontend-code-reviews Slack channel, in the channel's convention, with the PR link, the Linear ticket link and a screenshot of the change. Waits for the automated Cursor review and clears its findings before the PR is marked ready and before anything is posted. Use when asked to \"ask for review\" on a Comfy-Org/ComfyUI_frontend PR, \"post to frontend code reviews\", \"/fe-review <pr or ticket>\", or after opening a frontend PR that needs a reviewer."
---

# fe-review

Post a review request for a frontend PR to **#frontend-code-reviews** (channel id `C09EM82R2HL`).

Input: one or more PR numbers or ticket ids (e.g. `19466`, `DES-1219`), optionally a repo (default `Comfy-Org/ComfyUI_frontend`), reviewers, and images to attach. One Slack message per PR.

The order is fixed: **Cursor review → clean-up → ready for review → Slack.** Nobody sees a PR the automated review has not cleared.

## 1. Re-read the convention (every run — it drifts)

Read the last ~15 messages of `C09EM82R2HL` with `slack_read_channel` (concise). Match what the team is doing now. At the time of writing, a post is:

```
<@reviewer> <PR link> (<what it does, one clause>) is ready for review. <1–2 plain sentences: the user-visible change, anything a reviewer must know (merge order, flags, a sibling PR).>
```

- No `[repo]` prefix: the channel is frontend-only. Name the other repo only for a cross-repo pair (`<…/cloud/pull/11033|cloud #11033>`).
- Links use Slack's `<url|label>` form: the PR as `<https://github.com/Comfy-Org/ComfyUI_frontend/pull/19466|#19466>`, the ticket as `<https://linear.app/comfyorg/issue/DES-1219|DES-1219>`.
- Plain English, short sentences, active voice, the effect first. No headers. Bullets only for a stack of PRs, in merge order.
- Don't restate test counts or CI detail beyond "checks pass" / "automated review addressed". The PR holds those.
- The Slack app appends "Sent using Claude" by itself. Don't add it.

## 2. Gather the facts

```bash
${CLAUDE_SKILL_DIR}/scripts/pr-facts.sh <pr-or-ticket> [repo]
```

It returns JSON with the PR number, URL, title, draft flag, head sha, ticket and ticket URL, the Storybook preview (if the report comment has one), the changed files and the head of the PR body. Summarise from the body and the files. Never invent behaviour the PR doesn't describe.

## 3. Show the change: screenshots, not a preview link

Frontend PRs get no hosted app preview. The PR report comment only links Storybook and Playwright reports. So:

- **Attach the images the user gives you.** They are the preview. Upload them with the message (step 7).
- No image given and the change is visual: ask for one, or take one from a running dev server in the main checkout if the operator has one up. Don't post a visual change with no picture unless the user says to.
- A changed `*.stories.ts` and a Storybook URL in the facts: add `Storybook: <url>` for the affected story.
- Never invent a URL.

## 4. Reviewers

Use the reviewers the user names. If none are named, **ask**. This channel has no default reviewer. Look up names with `slack_search_users` and mention by id: `<@Uxxxx>`. Never guess an id. Ids seen in the channel: DrJKL (Alex) `U09A2BCFEVB`, Jaewon `U0AG6QVE1L7`, Ben Cooley `U0BJJSG5HK4`, ShihChi `U0BA79D8R1T`, Hunter `U09GW6DG82F`. Confirm each id before using it.

## 5. Wait for the Cursor review, and clear it

**Do this before marking the PR ready and before any Slack message.** Follow the `cursor-review` skill for triage, fixes and replies, with these frontend differences:

- The workflow is `PR: Cursor Review` (platform's is `CI - Cursor Review`). The trigger is the `cursor-review` label. The gate skips forks and PRs with `skip-cursor-review`. It does not skip drafts.
- The panel posts one review whose body starts `## 🔍 Cursor Review — Consolidated panel`, as **`github-actions[bot]`** (GraphQL login `github-actions`), not `cloud-code-bot`. Resolve its threads with `resolve.sh <repo> <n> github-actions`.
- A run reviews the head as of when the label was added, and skips a commit it already reviewed. **After you push, remove and re-add the label** so the panel reviews the new head. Re-labeling cancels an in-flight run for the old head:

  ```bash
  gh api -X DELETE "repos/<repo>/issues/<n>/labels/cursor-review"
  gh api -X POST "repos/<repo>/issues/<n>/labels" -f 'labels[]=cursor-review'
  ```

- **Wait on the review, not the clock.** Start this with Bash `run_in_background` *before* re-labeling. It exits once, when the panel has reviewed the current head or the run ends without a review:

  ```bash
  ${CLAUDE_SKILL_DIR}/scripts/wait-cursor.sh <n> [repo] 60   # timeout: 5400000 (90 min)
  ```

  Don't use `watch-pr.sh` for this. It ignores `github-actions[bot]` comments, and CodeRabbit threads wake it before Cursor has posted.
- CodeRabbit (`coderabbitai[bot]`) also reviews every FE PR. Its threads count as open comments in step 6.
- Latency is 12–30 minutes. Do other work meanwhile. Tell the user the review is running, then carry on when the wait exits.
- **Size the review to the risk, and set the bar higher here than on platform.** The frontend ships to every ComfyUI user, on Desktop and Cloud, and much of it is shared: the graph canvas, the stores, the node library, settings, keybindings, i18n and the extension API. A change that looks small can break workflows it never touches.
  - A fix pushed after the review is a new head. Re-label and wait again whenever the fix changed behaviour, unless it stays inside one leaf component's markup or styles.
  - For a change to shared state, the canvas, the extension API, serialization, or anything that loads or saves a workflow: re-review until a pass comes back with nothing Medium or above, with three passes at most in all. If Medium-or-above findings remain after the third, stop and report them instead of running a fourth.
  - A structural finding (a duplicated helper, a missing abstraction) follows the `cursor-review` skill's area rule. Use the area note's shared piece, or raise the finding. Never add a local helper to satisfy the panel.
  - A comment-only or test-only fix never needs a pass.
  - Say in the report which call you made and why, in one line.

## 6. Clean up, then mark the PR ready for review

In the PR's own worktree, over `git diff origin/<base>...HEAD`:

1. `/clean-code` (the `clean-code` skill): naming, function size, comments that narrate, duplication.
2. `/code-review` (the `code-review` skill): correctness and bugs.
3. **Every open comment on the PR**, bots and people alike:

   ```bash
   gh api graphql -f query='query{repository(owner:"<owner>",name:"<name>"){pullRequest(number:<n>){reviewThreads(first:100){nodes{id isResolved path line comments(first:10){nodes{author{login} body}}}}}}}' \
     --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved|not)'
   ```

   Also read the top-level review bodies and PR comments (`gh pr view <n> --comments`). Fix what needs fixing. Reply to every thread in one line (what changed, which commit, or why not). Resolve the bots' threads (Cursor, CodeRabbit). Don't resolve a human's thread: the human resolves it. Rerun the query: nothing unanswered may remain.

Verify the frontend way: `pnpm test:unit <paths>` for what you touched, and `pnpm exec oxlint`, `pnpm exec eslint` and `pnpm exec oxfmt --check` on the changed files. The pre-commit hook typechecks what you stage. No repo-wide runs (see the repo's AGENTS.md). Push with `--no-verify`. If the PR lives in another workspace, ask that workspace's agent to do this rather than editing its branch yourself.

When the PR is clean, update its title and body if the scope changed since it was opened. Then, if it is a draft, run `gh pr ready <n> --repo <repo>` in the same run without asking, and say so in the report.

## 7. Send

The user asking for this skill counts as approval to post. One message per PR to `C09EM82R2HL`.

- **With images:** upload each one with `slack_get_file_upload_url` (exact byte count, `alt_txt` describing the screenshot), POST the bytes with `curl -X POST "$URL" --data-binary @file`, then share it with `slack_complete_file_upload` (`channel_id: C09EM82R2HL`, and the message text as `initial_comment`). The message and the picture land as one post. For several images, share the first with the text and the rest in its thread (`thread_ts`).
- **Without images:** `slack_send_message`.
- If the user asked to preview first, use `slack_send_message_draft` and upload the image once they confirm.

Report each message link back in one line per PR.

## Don'ts

- Don't post, or mark ready, before the Cursor panel has reviewed the PR and its findings are answered. A fix round that changed behaviour usually needs another pass here (step 5).
- Don't post a draft PR. Step 6 marks it ready first.
- Don't paste the PR body, checklists or test counts.
- Never include secrets, tokens or env values, even from the PR body.
