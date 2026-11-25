#!/usr/bin/env bash
# Usage: pr-facts.sh <pr-number | ticket-id> [repo]   (repo default Comfy-Org/ComfyUI_frontend)
# Prints JSON: number, url, title, repo, draft, head_sha, ticket, ticket_url,
# storybook, files, body_head. Frontend PRs have no app preview; Storybook is
# the only hosted build, read from the github-actions PR report comment.
set -euo pipefail
ref="$1"; repo="${2:-Comfy-Org/ComfyUI_frontend}"
if [[ "$ref" =~ ^[0-9]+$ ]]; then n="$ref"
else
  n=$(gh pr list --repo "$repo" --state open --search "$ref" --json number --jq '.[0].number // empty')
  [ -n "$n" ] || { echo "no open PR in $repo mentions $ref" >&2; exit 1; }
fi
pr=$(gh api "repos/$repo/pulls/$n")
title=$(jq -r .title <<<"$pr")
ticket=$(grep -oE '\b(DES|FE|PM|DPLAT|BE)-[0-9]+' <<<"$title $(jq -r '.body // ""' <<<"$pr")" | head -1 || true)
storybook=$(gh api "repos/$repo/issues/$n/comments?per_page=100" --jq '.[] | select(.user.login=="github-actions[bot]") | .body' 2>/dev/null \
  | grep -oE 'https://[a-z0-9]+\.comfy-storybook\.pages\.dev' | tail -1 || true)
files=$(gh api "repos/$repo/pulls/$n/files?per_page=100" --jq '[.[].filename]')
jq -n --argjson n "$n" --arg repo "$repo" --arg url "$(jq -r .html_url <<<"$pr")" --arg title "$title" \
  --argjson draft "$(jq .draft <<<"$pr")" --arg sha "$(jq -r .head.sha <<<"$pr")" \
  --arg ticket "$ticket" --arg storybook "$storybook" --argjson files "$files" \
  --arg body "$(jq -r '.body // ""' <<<"$pr" | head -c 2500)" \
  '{number:$n, repo:$repo, url:$url, title:$title, draft:$draft, head_sha:$sha, ticket:$ticket,
    ticket_url:(if $ticket=="" then "" else "https://linear.app/comfyorg/issue/\($ticket)" end),
    storybook:$storybook, files:$files, body_head:$body}'
