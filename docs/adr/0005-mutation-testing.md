# 0005. Mutation testing of chart unit tests

**Status:** Accepted

## Context
A passing test may test nothing: an assertion on the wrong path, a
`failedTemplate` that matches any error, a check made unreachable by another
one. Twice while building the first charts, a control looked tested and was
not:
- a claim that sprig's `mergeOverwrite` drops an explicit `false` survived
  its mutation: the claim was wrong (`merge` is the culprit) and the code was
  changed;
- an `https` check in a template was dead code, since the values schema
  rejects the same input first.

## Decision
- `test/mutations.yaml` lists mutations: each weakens one behaviour with an
  exact find/replace in one file (`find` must occur exactly once).
- `scripts/mutation-test.sh` applies each in turn and runs the chart's
  targeted suites; they must fail. Snapshot suites are excluded: they catch
  every change and would kill every mutation.
- A mutation that only breaks rendering is reported as invalid, not killed.
- Originals are backed up outside the repository: Helm renders every file
  under `templates/`, so a backup copy there would be rendered too (this
  invalidated a first, ad hoc campaign).
- CI runs the campaign on every pull request (`mutation` job, gated by
  `ci-ok`).

## Consequences
- A new guard or security default comes with its mutation.
- Weakening a test makes CI fail even when the code is unchanged.
- The campaign costs a few minutes of CI per pull request.
