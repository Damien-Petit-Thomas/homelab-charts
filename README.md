# homelab-charts

Helm charts for a k3s homelab: a library chart and a hardened reference
chart, OCI-published and signed.

## Charts

| Chart | Type | Purpose | Status |
|---|---|---|---|
| [`homelab-common`](charts/homelab-common) | library | Shared templates: names and labels, image references pinned by digest, restricted security contexts, ExternalSecrets, homelab CA trust | unreleased |
| [`vaultwarden`](charts/vaultwarden) | application | Reference chart: Pod Security `restricted`, read-only root filesystem, SQLite with tested backup and restore, SSO that survives an identity provider outage | unreleased |
| `homelab-policies` | admission policies | ValidatingAdmissionPolicies enforcing the homelab conventions (digest-pinned images, no `latest`, allowed registries) on every workload, whatever its chart ([ADR 0006](docs/adr/0006-chart-scope.md)) | planned |

## Principles

- **Secure by default**: Pod Security `restricted`, non-root, no
  capabilities, read-only root filesystem, no service account token.
- **Reproducible**: images referenced by digest; toolchain pinned in
  `mise.toml` and `mise.lock`; third-party actions pinned to commit SHAs.
- **Tested**: unit tests on rendered manifests, schema validation, policy
  checks, installation tests on a real cluster, including failure cases;
  every tested behaviour is mutation-tested ([ADR 0005](docs/adr/0005-mutation-testing.md)).
- **Verifiable**: charts published to GHCR as OCI artifacts, signed with
  cosign (keyless) and shipped with build provenance.
- **Decisions on record**: [architecture decision records](docs/adr/README.md).

## Requirements

Helm 4 ([ADR 0002](docs/adr/0002-helm-4-only.md)).

## Install

Charts are published to GHCR as OCI artifacts, one release tag per chart
(`vaultwarden-v0.1.0`). Pin a version, and preferably its digest:

```bash
helm install vaultwarden oci://ghcr.io/damien-petit-thomas/charts/vaultwarden \
  --version 0.1.0 -n vaultwarden -f values.yaml
```

## Verify

Every published chart is signed with cosign (keyless: the identity is this
repository's release workflow on `main`) and carries a SLSA build provenance
attestation. The release job runs these same commands on what it just
pushed, and fails if they fail.

```bash
CHART=ghcr.io/damien-petit-thomas/charts/vaultwarden
REF="$CHART@$(crane digest "$CHART:0.1.0")"   # verify the digest, not a movable tag
cosign verify "$REF" \
  --certificate-identity https://github.com/Damien-Petit-Thomas/homelab-charts/.github/workflows/release.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
gh attestation verify "oci://$REF" --repo Damien-Petit-Thomas/homelab-charts \
  --signer-workflow Damien-Petit-Thomas/homelab-charts/.github/workflows/release.yml
```

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache-2.0](LICENSE)
