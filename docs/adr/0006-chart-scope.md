# 0006. Which applications get a chart from this repository

**Status:** Accepted

## Context
The homelab runs about fifteen applications. Generic ones (one image, one
port, one volume: Actual, the media stack, jellyseerr, flaresolverr) are
deployed with bjw-s `app-template`; Immich and Keycloak use their upstream
charts. The legacy deployments break the homelab's conventions: `latest` or
`nightly` tags, no digests, containers running as root. The two applications
already migrated (Actual, Vaultwarden) repeat about sixty lines of values
(security contexts, probes, the step-issuer Ingress).

The goal is for this repository to serve as many applications as possible.
Two ways to get there were weighed: a generic chart of our own for every
application, or enforcing the conventions independently of the chart.

## Decision
- **Generic applications keep `app-template`.** It is mature and
  community-maintained.
- **The conventions are enforced by admission policies**, shipped by a
  `homelab-policies` chart in this repository: `ValidatingAdmissionPolicy`
  objects (CEL, built into the API server since Kubernetes 1.30, no operator
  to run). They apply to every workload of the targeted namespaces, whatever
  chart rendered it, upstream charts included. First rules: image pinned by
  digest, no `latest` tag, allowed registries.
- **Duplicated values move to a shared values file** in
  `homelab-argocd-overlay`, merged before each application's own values.
- **A dedicated chart only when an application needs logic that
  `app-template` cannot express.** `vaultwarden` qualifies (consistent SQLite
  backups, SSO that survives an identity provider outage); others will be
  judged on the same criterion.
- `homelab-common` stays the library of the dedicated charts.

## Consequences
- This repository governs every application through `homelab-policies`,
  while maintaining only the charts that carry real logic.
- A violation is rejected at admission, then reported by ArgoCD as a sync
  error: the policies are also run in CI against rendered manifests, so most
  violations fail before reaching the cluster.
- An admission policy sees one object at a time. It cannot require a
  NetworkPolicy to exist: the default-deny policy is created per namespace in
  the overlay's `addons/`.
- Pod Security levels stay enforced by the namespace labels (Pod Security
  admission), not duplicated in the policies.
- Policies are rolled out in `Warn` and `Audit` first, then `Deny` once no
  workload violates them: the legacy applications would otherwise be blocked
  before they are migrated.

## Rejected alternatives
- **A generic `homelab-app` chart replacing `app-template`**: it would
  enforce the conventions at render time, but only for the applications using
  it (not Immich or Keycloak), and it means maintaining alone a generic chart
  that already exists upstream.
- **A dedicated chart per application**: as many charts to keep up with
  upstream releases, for applications that need no specific logic.
- **Kyverno or Gatekeeper**: more expressive (mutation, cross-object rules),
  but an extra controller in the admission path, to run and upgrade. The
  built-in mechanism covers the first rules; revisit if a rule needs more.
