# 0003. Per-chart releases with release-please

**Status:** Accepted

## Context
The repository holds several charts with independent lifecycles: a library
chart (`homelab-common`) and application charts depending on it. Each needs
its own SemVer version, changelog and tag, and a library release must reach
its dependents.

## Decision
- release-please, in manifest mode, with one package per chart. Commits
  follow Conventional Commits with the chart as scope
  (`feat(vaultwarden): ...`).
- release-please opens one release pull request per chart: it bumps `version`
  in `Chart.yaml` and updates the chart's `CHANGELOG.md`. Merging it creates
  the tag `<chart>-v<version>` and the GitHub release.
- The release workflow then packages the chart, pushes it to GHCR as an OCI
  artifact, signs it with cosign (keyless, GitHub OIDC) and attests its
  provenance.
- The action is pinned to a commit SHA, like every third-party action.

## Implementation
- release-please runs with a token of a dedicated GitHub App, scoped to this
  repository with `contents` and `pull-requests` write: a pull request opened
  with `GITHUB_TOKEN` triggers no workflow, so a release PR would never get
  its required checks. The App's credentials live in the `release`
  environment, which deploys from `main` only.
- An application chart vendors `homelab-common` into its package (`charts/`):
  consumers never resolve the `file://` dependency. The dependency is a range
  (`>=0.1.0 <1.0.0`), without a lock: the packaged library is the one in the
  released commit. Shipping a library change in an application chart takes a
  commit scoped to that chart.
- Release tags `<chart>-vX.Y.Z` are immutable (ruleset `release-tags`).

## Consequences
- Versions follow the commit history: a `feat!` or `BREAKING CHANGE` footer
  is required for a major bump, so commit messages are reviewed like code.
- Release tags are immutable (ruleset), and so are published chart versions.

## Rejected alternatives
- **A script like `homelab-ci-templates/scripts/release.sh`**: fine for one
  versioned unit, but per-chart tags, changelogs and dependency bumps would
  have to be rewritten by hand.
- **chart-releaser**: publishes to a GitHub Pages index, not to an OCI
  registry, and does not manage versions or changelogs.
