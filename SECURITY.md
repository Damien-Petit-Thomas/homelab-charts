# Security policy

## Reporting a vulnerability

Report vulnerabilities **privately** through GitHub:
<https://github.com/Damien-Petit-Thomas/homelab-charts/security/advisories/new>
(Security tab, *Report a vulnerability*). Do not open a public issue.
You will receive an initial response within 7 days.

Include the affected chart and version, reproduction steps or rendered
manifests, the potential impact, and a suggested fix if you have one.

## Supported versions

Only the latest release of each chart receives fixes.

## Supply chain

- Third-party actions are pinned to commit SHAs; our own reusable workflows
  follow an immutable major tag (`.github/zizmor.yml`).
- Development and CI tools are pinned in `mise.toml`; `mise.lock` records
  their checksums, and their build provenance where upstream publishes it.
- Dependency updates wait 7 days after an upstream release (Dependabot
  cooldown, mise `install_before`).

## OpenSSF Scorecard: accepted exceptions

| Check | Rationale |
|---|---|
| Code-Review | Single maintainer. Every change goes through a pull request gated by required status checks (`ci-ok`, `zizmor`) and an automatic Copilot review. Human approval becomes mandatory when a second maintainer joins ([ADR 0004](docs/adr/0004-solo-maintainer-branch-protection.md)). |
| Branch-Protection | Pull request required, required status checks, no bypass, force pushes and deletions blocked. Required approvers, code-owner review and last-push approval need a second person. |
| Fuzzing | No fuzzable code: templates are covered by unit, schema and installation tests, including negative cases. |
