#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$repo_root/dist/willie-skills.zip}"

mkdir -p "$(dirname "$out")"
rm -f "$out"
cd "$repo_root"
zip -qr "$out" .claude-plugin/plugin.json skills README.md LICENSE -x '*.DS_Store'
echo "$out"
