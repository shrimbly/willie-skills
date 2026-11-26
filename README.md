# willie-skills

Willie's Claude Code skills for Comfy-Org Developer Platform work, kept in one repo so cloud sessions can load them.

| Skill | What it does |
| --- | --- |
| `superset-implementer` | The contract for an implementation agent: one brief, one branch, one draft PR, then review fixes until merge. |
| `dplat-review` | Get a platform PR reviewed: facts, Cursor pass, the post to Vinh in #epd-comfy-platform-code-reviews, the watch and the re-review bump. |
| `fe-review` | The same for ComfyUI_frontend PRs, to Jaewon in #jaewon-requests. |
| `cursor-review` | Run the Cursor review bot on a PR and work its findings to clean. |
| `feedback-triage` | Turn a burst of raw feedback into a reviewed set of tickets, deduped against the tracker and open PRs. |
| `watch-for-activity` | Watch a PR, its Slack review thread, a CI run or a deploy, and report only real changes. Provides `watch-pr.sh` and `watch-slack.sh`. |

## How Claude Code finds them

The skills live at `skills/<name>/SKILL.md`, the standard plugin layout. `.claude/skills` is a link to `skills/`, because Claude Code loads project skills from `.claude/skills/<name>/SKILL.md` in the repo it is working in.

- **Cloud sessions:** add this repo to the project (Project settings, Repositories). Each new thread clones it, and its skills show up next to the other repos' skills.
- **Your Mac (Claude Code):** install it as a plugin. Claude Code clones the private repo with your existing GitHub sign-in (`gh auth login` or an SSH key).

  ```
  /plugin marketplace add shrimbly/willie-skills
  /plugin install willie-skills@willie-skills
  ```

  The skills then show as `/willie-skills:dplat-review` and so on. Get new versions with `/plugin marketplace update willie-skills`. If you linked the skills into `~/.claude/skills` before, remove those links so each skill loads once.
- **claude.ai and the desktop app:** go to Customize, then Plugins, then Add. Either "Add marketplace" with this repo (the Claude GitHub App needs access to it), or "Upload plugin" with the zip from `scripts/build-plugin-zip.sh`.

## The plugin layout

`.claude-plugin/marketplace.json` makes the repo its own marketplace. It lists one plugin whose source is the repo root, with `strict: false` and each skill folder named under `skills`, the same shape as Anthropic's own skills marketplace. Add a new skill's folder to that list. There is no `plugin.json` at the root.

Skills live in `skills/`, not `.claude/skills`, because claude.ai documents only the standard layout. Keep angle brackets out of skill descriptions and write `allowed-tools` as one space-separated line.

`scripts/build-plugin-zip.sh` writes `dist/willie-skills.zip` for claude.ai's Upload plugin, using `scripts/plugin.json` as the zip's manifest. Bump `version` there when you change a skill. Check changes with `claude plugin validate .`.

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
- **Slack from a shell.** `watch-pr.sh` and `watch-slack.sh` read a Slack thread only with a token in `SLACK_TOKEN`, through the Web API. Cloud threads have no token and their network blocks `slack.com`, so there they check the thread with the Slack connector when they wake instead (see `watch-for-activity`).
- **`gh`, `jq`, `curl`.** Every script needs `gh` signed in and `jq` on the PATH; the Slack watch also needs `curl`.
