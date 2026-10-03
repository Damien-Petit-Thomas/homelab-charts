#!/usr/bin/env bash
# Mutation testing of the chart unit tests.
#
# Each entry of the mutations file weakens one behaviour with an exact
# find/replace in one file; the chart's targeted suites (tests/*_test.yaml)
# must then fail. Snapshot suites are excluded: they catch every change, so
# they would kill every mutation and prove nothing about the assertions.
#
# A mutation that only breaks rendering ("errored", no "failed") is reported
# as invalid: it would be killed for the wrong reason.
#
# Originals are backed up outside the repository: Helm renders every file
# under templates/, so a backup copy left there would be rendered as well.
#
# Usage: scripts/mutation-test.sh <mutations.yaml>
set -euo pipefail

mutations="${1:?usage: mutation-test.sh <mutations.yaml>}"
backup_dir="$(mktemp -d)"
current=""

restore() {
  if [[ -n "$current" ]]; then
    cp "$backup_dir/original" "$current"
    current=""
  fi
}
trap 'restore; rm -rf "$backup_dir"' EXIT

run_tests() {
  untt --strict -f 'tests/*_test.yaml' "$1"
}

# A chart vendors its file:// dependencies: a mutation outside the chart
# (in the library) only takes effect once they are rebuilt.
rebuild_deps() { helm dependency build --skip-refresh "$1" >/dev/null; }

field() { yq -r ".[$1].$2" "$mutations"; }

for chart in $(yq -r '.[].chart' "$mutations" | sort -u); do
  rebuild_deps "$chart"
  run_tests "$chart" >/dev/null || { echo "baseline: $chart tests fail before any mutation" >&2; exit 1; }
done

count="$(yq 'length' "$mutations")"
killed=0
bad=0
for ((i = 0; i < count; i++)); do
  desc="$(field "$i" description)"
  chart="$(field "$i" chart)"
  target="$(field "$i" file)"

  cp "$target" "$backup_dir/original"
  current="$target"
  FIND="$(field "$i" find)" REPLACE="$(field "$i" replace)" python3 - "$target" <<'EOF'
import os, sys
path, find, replace = sys.argv[1], os.environ["FIND"], os.environ["REPLACE"]
text = open(path).read()
n = text.count(find)
if n != 1:
    sys.exit(f"'find' occurs {n} times in {path}, expected exactly once")
open(path, "w").write(text.replace(find, replace))
EOF

  outside=false
  [[ "$target" == "${chart%/}/"* ]] || outside=true
  if $outside; then rebuild_deps "$chart"; fi

  rc=0
  out="$(run_tests "$chart" 2>&1)" || rc=$?
  summary="$(grep -E '^Tests:' <<<"$out" | tr -s ' ' || true)"
  restore
  if $outside; then rebuild_deps "$chart"; fi

  if [[ "$rc" -eq 0 ]]; then
    echo "SURVIVED  $desc"
    bad=$((bad + 1))
  elif [[ "$summary" != *" failed"* ]]; then
    echo "INVALID   $desc (${summary:-no summary}: the mutation breaks rendering)"
    bad=$((bad + 1))
  else
    echo "killed    $desc (${summary#Tests: })"
    killed=$((killed + 1))
  fi
done

echo "mutations: $count, killed: $killed, survived or invalid: $bad"
[[ "$bad" -eq 0 ]]
