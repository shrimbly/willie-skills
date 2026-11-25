#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$repo_root/dist/willie-skills.zip}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/willie-skills/.claude-plugin" "$(dirname "$out")"
jq 'del(.skills)' "$repo_root/.claude-plugin/plugin.json" > "$stage/willie-skills/.claude-plugin/plugin.json"
cp -R "$repo_root/.claude/skills" "$stage/willie-skills/skills"
cp "$repo_root/README.md" "$stage/willie-skills/README.md"

rm -f "$out"
(cd "$stage" && zip -qr "$out" willie-skills -x '*.DS_Store')
echo "$out"
