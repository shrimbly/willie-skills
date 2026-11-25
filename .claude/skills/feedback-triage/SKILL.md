---
name: feedback-triage
description: |
  Turn a burst of raw feedback — a Slack channel after a user testing session,
  a survey dump, a partner's bug report — into a reviewed set of tickets.
  Dedupes against the tracker and the open PRs first, then presents the survivors
  as a card-per-ticket web app the user approves, cancels and annotates. The
  export round-trips back for correction before anything is filed.
  Use when the user says "review these and start writing tickets", "triage this
  channel", "we had a feedback session", or asks to turn feedback into issues.
metadata:
  version: "1.0.0"
---

# Feedback triage

Raw feedback is not a ticket list. Most of it is already known, already fixed,
already filed, or belongs to another team. **The value of this skill is the
subtraction**, not the transcription.

A real run: 31 findings in a channel became 16 proposals, 13 approvals, and 11
new tickets. Two thirds of the raw feed did not need a ticket. An assistant that
transcribes all 31 wastes the reviewer's afternoon and pollutes the board.

## The loop

```
read → dedupe → verify → group → present → correct → file
```

Never skip dedupe or verify. They are where the work is.

---

## 1. Read the source completely

Read the channel, the thread, the document — all of it, and the **replies**.

**Replies are not decoration.** In one run they held:

- an item the reporter withdrew two minutes later ("Oh jk I think I selected
  both serverless and local at the start, so I see why it's showing up")
- an answer that reversed the fix ("Actually, maybe not. We may need to store
  them if we plan to test the deployment against the workflow.")
- a ticket someone had already filed from the thread (`BE-7502`)
- the strongest evidence on a card ("This keeps coming back")

Parent messages alone will make you file resolved items and miss the reasoning.

Capture for every candidate: **who**, **when**, the **verbatim quote**, and a
**permalink**. Slack permalinks are `<channel-url>/p<ts-with-the-dot-removed>`.

## 2. Dedupe against the tracker

Pull the team's issues and read **both** halves:

- **Open and backlog** — the obvious duplicates.
- **Completed and canceled** — the non-obvious ones. Feedback from a user on
  production describes a product that may be weeks behind main. Several
  "findings" will be things already shipped.

For each candidate ask which of these it is:

| Verdict | Meaning |
|---|---|
| New | Nothing on the board covers it |
| Update | The board holds the idea; this adds evidence or a decision |
| Covered | Already done, or in review |
| Other team | Real, but not this team's surface |

**An update is not a duplicate.** When an issue already frames the problem, add
the new evidence to it. A second issue on the same idea splits the discussion
and neither gets done.

**Watch for "the same idea on a different screen."** One run had an issue for a
build's estimated finish time and a new report about a deployment's provisioning
wait. Same idea, different screen, different code. Two tickets, and say so in
both so nobody merges them later.

## 3. Dedupe against the work in flight

The tracker lags the branches. Check:

- open PRs by every author, not just the user's
- PRs merged since the feedback was written

In one run the exact bug a partner reported had been fixed by a PR that merged
*after* they wrote it up. Filing it would have looked careless.

## 4. Verify in the code before proposing

Do not propose from a screenshot alone. Confirm the thing is still true.

- Grep the locale file for the exact string a copy fix would change, and quote
  it in the ticket. It proves the fix is needed and tells the implementer where.
- Read the component before claiming a control is missing.
- Check whether a guard already exists elsewhere — the pattern usually does, and
  "the pattern exists at `X:312`, it is just not applied here" is worth more to
  the implementer than a description of the symptom.

Where you cannot verify — a slide deck you cannot open, a preview you cannot
run — **say so on the card**. Mark it low confidence rather than dropping it or
asserting it.

## 5. Group before presenting

Merge candidates that resolve to one change. Two people asking different
questions about the same step is one ticket with two sources — and two
independent reports is the strongest argument a card can carry, so say
"two reports" on it.

## 6. Present as a review app

Build a single self-contained HTML page and publish it with the Artifact tool.
Load `artifact-design` first.

**Each card carries:**

- a stable short id (`N1`, `U2`, `O3`) — the export and the conversation both
  need to name cards
- one line saying what the task is
- one sentence saying how to resolve it
- collapsed detail: why it matters, what you checked, the verbatim quotes with
  permalinks
- a feedback textarea
- Approve and Cancel, both toggleable

**Section the board by verdict** from step 2. Give each section a note saying
what approving means there — "approving means I file it" reads differently from
"approving means I add it to that issue".

**Items with no verdict to give get no buttons.** The already-covered list is
reference: what it was, which PR or issue covers it, one line of why. Making
someone click Approve twelve times on work already done is busywork.

**Requirements that matter:**

- persist verdicts and notes to `localStorage`, keyed per card — a reviewer will
  reload
- a sticky bar with live counts and the export button
- an "Expand all" toggle
- export to markdown into a readonly `<textarea>` with a copy button

**The export must round-trip.** Group by verdict, and per card emit the id, the
title, the fix, and the note. That is exactly enough for corrections to come
back unambiguous, and little enough to paste.

## 7. Apply the corrections

Expect corrections to change the **approach**, not just the wording. In one run,
four of thirteen approvals arrived with a different solution than proposed:

> "We should not put this next to the provisioning pill, lets show a dialog on
> starting the deployment…"

Rewrite the ticket body around the user's approach and open it with the decision
in bold — `**Approach decided: …**`. The next reader must not have to reconstruct
which of two designs won.

A correction can also answer an open question the card raised. Record the answer
in the ticket as settled, not as a question.

## 8. File

Match the tracker's house style — read two or three of the user's own recent
tickets first. Generally:

- title names the surface and the fault: `Runs: the page does not say whose runs it lists`
- lead with the decision when one was made
- **Why** — the user impact, with the quote
- **What I checked** — the dedupe and code evidence, with file and line
- **Source** — attribution, date, permalink
- link related issues by identifier; state why a near-neighbour is *not* this ticket

Write it to `simple-english` if that skill is present.

Report back with every identifier and what changed from the proposal.

---

## Rules learned the hard way

**Never file for another team without asking.** Real findings that belong to
backend, API or docs still go on the board as cards — the user may want them
routed, or may want to raise them in person. In the first run the user cancelled
all six. Propose, do not assume.

**Do not create anything before the review gate.** The whole point is that the
user sees the tickets before they exist. Publish the board, stop, and wait for
the pasted markdown.

**After the gate, act.** Once corrections arrive, file them. Do not open a second
approval round — the gate has passed, and a correction is an instruction.

**Quote verbatim.** A paraphrase costs the reviewer a trip to Slack to check
whether you understood. The quote plus a permalink lets them decide in seconds.

**Never soften "already covered" into a ticket.** If a PR fixed it, say which
PR and move on. Filing it anyway is how a board fills with noise.
