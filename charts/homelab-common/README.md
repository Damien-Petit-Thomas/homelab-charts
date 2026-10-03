# homelab-common

Library chart shared by the application charts of this repository. It renders
nothing by itself; every helper fails at render time on invalid input, so a
mistake shows in `helm template` or the ArgoCD diff, not at admission or as a
pull error.

```yaml
# Chart.yaml of a consuming chart
dependencies:
  - name: homelab-common
    version: 0.1.0
    repository: oci://ghcr.io/damien-petit-thomas/charts
```

## Calling convention

Naming helpers take the root context; every other helper takes a dict.

```yaml
name: {{ include "homelab-common.fullname" . }}
labels:
  {{- include "homelab-common.labels" (dict "context" $ "component" "server") | nindent 4 }}
```

## Helpers

| Helper | Argument | Renders | Fails when |
|---|---|---|---|
| `name` | `.` | chart name or `nameOverride`, 63 chars | |
| `fullname` | `.` | `fullnameOverride`, else the release name if it is or ends with `-<name>`, else `<release>-<name>` | the result is not a DNS-1035 label |
| `chart` | `.` | `<name>-<version>`, label-safe | |
| `serviceAccountName` | `.` | from `serviceAccount.create` / `serviceAccount.name` | |
| `selectorLabels` | `context`, `component`? | name, instance, component | |
| `labels` | `context`, `component`? | selector labels, chart, version, managed-by, `commonLabels` | a common label redefines a standard one |
| `image` | `image`, `path`? | `repository[:tag]@digest` | no digest, malformed digest, `latest`, digest inside tag or repository |
| `podSecurityContext` | `securityContext`, `path`? | defaults: `runAsNonRoot`, `seccompProfile: RuntimeDefault` | any Pod Security `restricted` violation |
| `containerSecurityContext` | `securityContext`, `path`? | defaults: no privilege escalation, read-only root filesystem, `drop: [ALL]` | any Pod Security `restricted` violation |
| `externalSecrets` | `context` | one ExternalSecret per entry of `.Values.externalSecrets` | missing store, data, `secretKey` or `remoteRef.key`; invalid key or store kind |
| `caTrust.initContainer`, `caTrust.volumes`, `caTrust.volumeMounts`, `caTrust.env` | `caTrust` | `ca-updater` init container, bundle mounted read-only, `SSL_CERT_FILE` | `configMap` or image digest missing |

## Design notes

- **Selector labels are a separate, minimal set.** A Deployment selector is
  immutable: adding a label to it breaks every upgrade. In a chart with
  several workloads, each one sets a `component`, otherwise the main
  selector also matches the other workloads' pods.
- **`fullname` does not use the scaffold's `contains`.** A substring match
  turns chart `app` in release `happy` into `happy`.
- **Security contexts are merged with `mergeOverwrite`**, so an explicit
  `false` wins and nested maps merge (`capabilities.add` keeps the default
  `drop: [ALL]`). `merge $values $defaults` would silently restore defaults
  over an explicit `false`: a unit test guards against that swap.
- **Restricted rules are checked in the template** as well as by the
  namespace's Pod Security admission: the error then names the values key,
  instead of surfacing in ReplicaSet events.
- **ExternalSecrets default to `creationPolicy: Owner`**: the Secret is
  garbage-collected with its ExternalSecret. `deletionPolicy: Retain` only
  covers a deletion on the provider side.
- **CA trust needs no network and no root** at startup, unlike an init
  container running `apk add ca-certificates`. Node.js ignores
  `SSL_CERT_FILE`: Node-based charts set `NODE_EXTRA_CA_CERTS`.

## Tests

`test/common-consumer` is a fixture chart that calls every helper; its
helm-unittest suites cover each rendering rule and each failure message.
Every guard was mutation-tested: disabling it makes at least one test fail.

```bash
mise run charts:test
```
