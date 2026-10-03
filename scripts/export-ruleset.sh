#!/usr/bin/env bash
# Export a repository ruleset as a reviewed JSON snapshot (policy fields only,
# no instance-specific ids or timestamps).
# Usage: scripts/export-ruleset.sh [ruleset-name] [output-file]
set -euo pipefail

NAME="${1:-main-protection}"
OUT="${2:-.github/rulesets/${NAME}.json}"
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

rulesets="$(gh api "repos/${REPO}/rulesets")"
id="$(jq -r --arg n "$NAME" '.[] | select(.name == $n) | .id' <<<"$rulesets")"
if [[ -z "$id" ]]; then
  echo "ruleset '$NAME' not found in $REPO. Available rulesets:" >&2
  jq -r '.[].name' <<<"$rulesets" >&2
  exit 1
fi

gh api "repos/${REPO}/rulesets/${id}" \
  | jq -S '{name, target, enforcement, conditions, bypass_actors, rules}' > "$OUT"

jq -e '[.name, .target, .enforcement, .conditions, .rules] | all(. != null)' "$OUT" >/dev/null \
  || { echo "incomplete export: null fields in $OUT" >&2; exit 1; }

echo "exported ruleset '$NAME' (id $id) from $REPO to $OUT"
