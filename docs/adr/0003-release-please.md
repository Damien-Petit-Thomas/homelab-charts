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
