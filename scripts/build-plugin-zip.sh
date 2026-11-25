#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$repo_root/dist/willie-skills.zip}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/.claude-plugin" "$(dirname "$out")"
cp "$repo_root/scripts/plugin.json" "$stage/.claude-plugin/plugin.json"
cp -R "$repo_root/skills" "$repo_root/README.md" "$repo_root/LICENSE" "$stage/"

rm -f "$out"
(cd "$stage" && zip -qr "$out" . -x '*.DS_Store')
echo "$out"
