# 0002. Charts target Helm 4 only

**Status:** Accepted

## Context
The consumer of these charts is ArgoCD, whose repo-server embeds Helm
v4.2.1. Helm 3 receives security fixes only, until 2026-11-11.

## Decision
- Charts are developed and tested with Helm 4 only. The version used locally
  and in CI is pinned in `mise.toml`, on the same minor as ArgoCD.
- Chart API `v2`; `kubeVersion` constraints are declared in each `Chart.yaml`.

## Consequences
- One Helm version in the test matrix.
- Helm 3 may work, but is neither tested nor supported; the READMEs say so.

## Rejected alternatives
- **Helm 3 and Helm 4 in a CI matrix**: tests a version that reaches end of
  life within weeks, for consumers this project does not have.
