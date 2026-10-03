# homelab-charts

Helm charts for a k3s homelab: a library chart and a hardened reference
chart, OCI-published and signed.

## Charts

| Chart | Type | Purpose | Status |
|---|---|---|---|
| [`homelab-common`](charts/homelab-common) | library | Shared templates: names and labels, image references pinned by digest, restricted security contexts, ExternalSecrets, homelab CA trust | unreleased |
| [`vaultwarden`](charts/vaultwarden) | application | Reference chart: Pod Security `restricted`, read-only root filesystem, SQLite with tested backup and restore, SSO that survives an identity provider outage | unreleased |

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

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache-2.0](LICENSE)
