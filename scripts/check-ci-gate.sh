#!/usr/bin/env bash
# Fail when a job of the CI workflow is not listed in ci-ok's needs.
# ci-ok is the only required status check (ADR 0004): a job missing from its
# needs could fail without blocking a merge.
set -euo pipefail

workflow="${1:-.github/workflows/ci.yml}"

missing="$(yq -o=json '.' "$workflow" \
  | jq -r '(.jobs | keys) - ["ci-ok"] - (.jobs["ci-ok"].needs // []) | .[]')"

if [[ -n "$missing" ]]; then
  echo "jobs not gated by ci-ok in $workflow: ${missing//$'\n'/, }" >&2
  exit 1
fi
echo "every job of $workflow is gated by ci-ok"
