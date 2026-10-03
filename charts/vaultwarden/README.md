# vaultwarden

[Vaultwarden](https://github.com/dani-garcia/vaultwarden), a Bitwarden-compatible
server, packaged to run under Pod Security `restricted` with its data backed up
and restorable.

Requires Helm 4 and Kubernetes 1.34+. Every value is documented in
[values.yaml](values.yaml) and validated by [values.schema.json](values.schema.json):
an unknown key or a malformed URL fails the render.

## What the chart enforces

| Concern | Choice | Why |
|---|---|---|
| Database | SQLite only, one replica, `Recreate` | two pods must never open the same database file ([ADR 0001](../../docs/adr/0001-vaultwarden-sqlite-only.md)) |
| Pod security | non-root (uid 1000), no capabilities, read-only root filesystem, `RuntimeDefault` seccomp | `restricted` admission; violations fail at render time |
| Image | pinned by digest | a tag can be moved |
| API access | no service account token, no service links | Vaultwarden never calls the API; service links would inject `<SERVICE>_PORT` variables next to Rocket's `ROCKET_*` |
| Upstream defaults | sign-ups, invitations and password hints off | an instance for known users |
| Network | ingress from the ingress controller only, egress to DNS plus explicit rules; backup job isolated | least privilege |
| Data | claims kept on uninstall (`helm.sh/resource-policy: keep`, ArgoCD `Prune=false,Delete=false`) | a password vault outlives its release |

## Minimal values

```yaml
domain: https://vaultwarden.example.org
ingress:
  enabled: true
  className: traefik
  host: vaultwarden.example.org
  tls:
    secretName: vaultwarden-tls
backup:
  enabled: true
```

## Single sign-on (OpenID Connect)

```yaml
sso:
  enabled: true
  authority: https://sso.example.org/realms/home
  clientSecret:
    existingSecret: vaultwarden-oidc     # e.g. rendered by externalSecrets
externalSecrets:
  oidc:
    secretStoreRef:
      name: vault-backend
    target:
      name: vaultwarden-oidc
    data:
      - secretKey: client-secret
        remoteRef:
          key: homelab/vaultwarden-oidc
          property: client-secret
```

The defaults keep the vault usable when the identity provider is down
(behaviour checked in Vaultwarden 1.37.3, `src/auth.rs`):

| Setting | Default | Effect during an identity provider outage |
|---|---|---|
| `sso.only` | `false` | email + master password login still works |
| `sso.authOnlyNotSession` | `true` | Vaultwarden issues its own session tokens: open sessions survive; with `false`, every token refresh calls the provider |
| `sso.signupsAllowed` | `false` | an SSO login cannot create a vault; it links to the existing account with the same verified email |

The master password stays the encryption key: SSO authenticates, it does not
decrypt. Since the password path bypasses the provider's MFA, enable
Vaultwarden's own two-factor authentication on every account.

If the provider's certificate comes from a private CA, enable `caTrust`
(homelab-common's ca-updater init container, `SSL_CERT_FILE`).

## Network policy and the identity provider

Egress is closed except DNS. The rule that lets Vaultwarden reach the
identity provider depends on the CNI and on how the provider is exposed: an
`ipBlock` on node addresses, for instance, does not match under Cilium's
default `policy-cidr-match-mode`. Add it to `networkPolicy.extraEgress` and
verify it on the cluster (`kubectl exec` a request to the discovery URL).

## Backup

With `backup.enabled`, a CronJob runs [files/backup.sh](files/backup.sh) in the
Vaultwarden image itself:

1. `vaultwarden backup` snapshots the live database with `VACUUM INTO` over a
   read-only connection: a consistent copy, unlike copying `db.sqlite3` while
   its WAL is written.
2. The snapshot (as `db.sqlite3`), `rsa_key.pem`, attachments, sends and
   `config.json` go into `vaultwarden-<UTC timestamp>.tar.gz`, mode 0600.
   The archive is written under a temporary name, its content checked, then
   renamed: a failed run never leaves a partial archive under a valid name.
3. Archives beyond `backup.retention` are deleted, oldest first.

The job needs no network (its NetworkPolicy denies everything) and runs with
the server's uid and restrictions. The data volume is `ReadWriteOnce`: the
job must run on the node that mounts it. A `local` volume pins it there
through its node affinity; other storage needs `affinity` to keep both pods
together.

Run a backup now:

```bash
kubectl -n vaultwarden create job --from=cronjob/vaultwarden-backup vaultwarden-backup-manual
```

## Restore

[files/restore.sh](files/restore.sh) is shipped in the `<fullname>-scripts`
ConfigMap. It verifies the archive, moves the current files to
`/data/.pre-restore-<timestamp>/` (nothing is deleted), then extracts.

```bash
NS=vaultwarden; NAME=vaultwarden
kubectl -n "$NS" scale deployment "$NAME" --replicas=0
kubectl -n "$NS" wait --for=delete pod -l app.kubernetes.io/instance="$NAME",app.kubernetes.io/component=server --timeout=120s
# Start a one-off pod from the backup job template, running restore.sh:
kubectl -n "$NS" create job --from=cronjob/"$NAME"-backup "$NAME"-restore --dry-run=client -o json \
  | jq '.spec.template.spec.containers[0].command = ["/bin/sh", "/scripts/restore.sh"]' \
  | kubectl -n "$NS" apply -f -
kubectl -n "$NS" wait --for=condition=complete job/"$NAME"-restore --timeout=300s
kubectl -n "$NS" logs job/"$NAME"-restore
kubectl -n "$NS" scale deployment "$NAME" --replicas=1
```

Pass an archive name to restore an older one:
`["/bin/sh", "/scripts/restore.sh", "/backup/vaultwarden-20261003T031700Z.tar.gz"]`.
With ArgoCD self-heal on, pause it first: it would scale the Deployment back.

The backup, the retention and the restore after total data loss were run
against the Vaultwarden 1.37.3 image under the same restrictions as the pods
(uid 1000, read-only root filesystem, no capabilities, no network): the
restored instance starts, its RSA key is identical and the account created
before the backup is present.

## Tests

```bash
mise run charts:test       # unit tests and snapshot
mise run charts:mutation   # each tested behaviour, weakened in turn, must fail its tests
helm test <release>        # GET /alive through the Service, from a pod the NetworkPolicy admits
```
