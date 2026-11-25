#!/usr/bin/env bash
# Usage: pr-facts.sh <pr-number | ticket-id> [repo]   (repo default Comfy-Org/platform)
# Prints JSON: number, url, title, repo, ticket, ticket_url, body_head, files, preview_base.
set -euo pipefail
ref="$1"; repo="${2:-Comfy-Org/platform}"
if [[ "$ref" =~ ^[0-9]+$ ]]; then n="$ref"
else
  n=$(gh pr list --repo "$repo" --state open --search "$ref" --json number --jq '.[0].number // empty')
  [ -n "$n" ] || { echo "no open PR in $repo mentions $ref" >&2; exit 1; }
fi
pr=$(gh api "repos/$repo/pulls/$n")
sha=$(jq -r .head.sha <<<"$pr")
title=$(jq -r .title <<<"$pr")
ticket=$(grep -oE '\b(DPLAT|DES|BE|FE)-[0-9]+' <<<"$title $(jq -r '.body // ""' <<<"$pr")" | head -1 || true)
preview=""
for id in $(gh api "repos/$repo/deployments?sha=$sha&per_page=10" --jq '.[] | select(.environment|test("Preview";"i")) | .id' 2>/dev/null); do
  preview=$(gh api "repos/$repo/deployments/$id/statuses" --jq '[.[] | select(.state=="success")][0].environment_url // empty' 2>/dev/null)
  [ -n "$preview" ] && break
done
if [ -z "$preview" ]; then
  preview=$(gh api "repos/$repo/issues/$n/comments?per_page=60" --jq '.[].body' 2>/dev/null | grep -oE 'https://[a-z0-9-]+\.vercel\.app' | grep -viE 'vercel\.com' | tail -1 || true)
fi
files=$(gh api "repos/$repo/pulls/$n/files?per_page=100" --jq '[.[].filename]')
jq -n --argjson n "$n" --arg repo "$repo" --arg url "$(jq -r .html_url <<<"$pr")" --arg title "$title" \
  --arg ticket "$ticket" --arg preview "$preview" --argjson files "$files" \
  --arg body "$(jq -r '.body // ""' <<<"$pr" | head -c 2500)" \
  '{number:$n, repo:$repo, url:$url, title:$title, ticket:$ticket,
    ticket_url:(if $ticket=="" then "" else "https://linear.app/comfyorg/issue/\($ticket)" end),
    preview_base:$preview, files:$files, body_head:$body}'
