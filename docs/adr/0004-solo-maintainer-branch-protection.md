# 0004. Branch protection for a single maintainer

**Status:** Accepted

Same policy as [homelab-ci-templates ADR 0004](https://github.com/Damien-Petit-Thomas/homelab-ci-templates/blob/main/docs/adr/0004-solo-maintainer-branch-protection.md).

## Decision
- Pull request required, **0** approvals (GitHub forbids approving one's own
  pull request), **no** bypass actor.
- Required status checks: `ci-ok` (an aggregator that needs every CI job)
  and `zizmor` (Code Scanning).
- Force pushes and deletions of `main` blocked.
- The ruleset is exported to `.github/rulesets/` with
  `scripts/export-ruleset.sh`.

## Consequences
- New CI jobs join `ci-ok`'s `needs`, never the ruleset; the `ci-gate` hook
  fails when a job is missing.
- The only direct push to `main` was the initial commit, which a pull request
  needs as its base.
- With a second maintainer: 1 approval, `CODEOWNERS`, last-push approval.
