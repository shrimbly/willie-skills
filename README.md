# willie-skills

Willie's Claude Code skills for Comfy-Org Developer Platform work, kept in one repo so cloud sessions can load them.

| Skill | What it does |
| --- | --- |
| `superset-implementer` | The contract for an implementation agent: one brief, one branch, one draft PR, then review fixes until merge. |
| `dplat-review` | Get a platform PR reviewed: facts, Cursor pass, the post for #pillar3-dev-platform-code-reviews, the follow-up. |
| `fe-review` | The same for ComfyUI_frontend PRs and #frontend-code-reviews. |
| `cursor-review` | Run the Cursor review bot on a PR and work its findings to clean. |
| `feedback-triage` | Turn a burst of raw feedback into a reviewed set of tickets, deduped against the tracker and open PRs. |
| `watch-for-activity` | Watch a PR, CI run or deploy and report only real changes. Provides `watch-pr.sh`. |

## How Claude Code finds them

Claude Code loads project skills from `.claude/skills/<name>/SKILL.md` in the repo it is working in. So every skill here lives at `.claude/skills/<name>/`.

- **Cloud sessions:** add this repo to the project (Project settings, Repositories). Each new thread clones it, and its skills show up next to the other repos' skills.
- **Your Mac:** clone it and link each skill into `~/.claude/skills`:

  ```bash
  git clone git@github.com:shrimbly/willie-skills.git ~/Dev/willie-skills
  for d in ~/Dev/willie-skills/.claude/skills/*/; do ln -sfn "${d%/}" ~/.claude/skills/"$(basename "$d")"; done
  ```

## Script paths

The skills used to call their scripts at `~/.claude/skills/<name>/scripts/...`. That path does not exist in a cloud session. They now use `${CLAUDE_SKILL_DIR}/scripts/...`, which Claude Code fills in with the skill's own folder. A skill that calls another skill's script uses `${CLAUDE_SKILL_DIR}/../<other-skill>/scripts/...`, so `dplat-review` and `cursor-review` reach `watch-for-activity/scripts/watch-pr.sh` inside this repo.

The `reference/` files in `superset-implementer` use the same form, but Claude Code only fills the variable in a SKILL.md. When an agent reads it in a reference file, it means the folder that holds `superset-implementer/SKILL.md`.

## Known gaps

These still assume Willie's Mac. They were left as they are, not rewritten.

- **The `board` CLI.** `superset-implementer` reports status with `board status ...`. The CLI is not in this repo and not in cloud sessions. The skill already says to skip `board status` in a cloud session and let the draft PR be the signal. `scripts/status.sh` is the older script version of the same thing.
- **superset-orchestrator paths.** Briefs, status files and review records live under `~/.claude/superset-orchestrator/` (`briefs/`, `workspaces/`, `reviews/`). Nothing creates that folder in a cloud session, and nothing syncs it between machines.
- **Review records.** `dplat-review` writes `~/.claude/superset-orchestrator/reviews/<owner>-<name>-<n>.json` when it posts, and reads it in the follow-up step. In a cloud session that file is lost when the container goes, so a later thread cannot find the Slack thread from it. It has to search Slack instead.
- **design-os.** `superset-implementer` reads `~/Dev/design-os`. In a cloud session that repo is at the project's clone path instead, if it is attached.
- **Slack and Linear.** The review skills post to Slack and read Linear through connectors. A session without those connectors cannot do those steps.
- **`gh`, `jq`.** Every script needs `gh` signed in and `jq` on the PATH.
