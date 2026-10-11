# homelab-policies

ValidatingAdmissionPolicies that enforce the homelab image conventions on
every workload, whatever chart rendered it (upstream charts included):
[ADR 0006](../../docs/adr/0006-chart-scope.md). Built into the API server
(CEL, `admissionregistration.k8s.io/v1`): no controller to run.

## Rules

| Policy | Refuses |
|---|---|
| `homelab-image-digest` | an image without `@sha256:<64 hex>` |
| `homelab-image-no-latest` | the `latest` tag (even with a digest), and an image with neither tag nor digest |
| `homelab-image-registries` | an image outside `rules.allowedRegistries.registries`, after normalizing an image without registry host to `docker.io/<name>` |

Evaluated on create and update of Pods, Deployments, StatefulSets,
DaemonSets, ReplicaSets, Jobs and CronJobs, for containers, init containers
and ephemeral containers. Checking the workload, not only its Pods, puts the
refusal on the object ArgoCD applies instead of in ReplicaSet events.

## Progressive enforcement

Each policy has two bindings:

| Binding | Namespaces | Actions |
|---|---|---|
| `<policy>-audit` | all, except `excludedNamespaces` and opted-in ones | `Warn`, `Audit`: nothing is blocked; kubectl and ArgoCD show the warning |
| `<policy>-enforce` | labelled `homelab.internal/policies: enforce` | `Deny` |

An application opts in once it complies, in its namespace manifest:

```yaml
metadata:
  labels:
    homelab.internal/policies: enforce
```

## Values

```yaml
rules:
  allowedRegistries:
    registries:            # prefixes, each ending with "/"
      - docker.io/
      - ghcr.io/
excludedNamespaces: [kube-system, kube-public, kube-node-lease]
```

Every value is documented in [values.yaml](values.yaml). A registry prefix
must end with `/`: `ghcr.io` would also allow `ghcr.io.evil.example`.

## Notes

- The images of every container kind are mapped to strings before being
  concatenated: `Container` and `EphemeralContainer` are distinct CEL types.
  The API server reports no type-checking warning for these policies.
- `failurePolicy: Fail`: an object the policies cannot evaluate is refused,
  not let through.
- A policy sees one object at a time: it cannot require a NetworkPolicy to
  exist. Default-deny network policies are created per namespace.
- An object that breaks several rules is refused with the first failing
  policy's message only.

## Tests

- Unit tests: rendering of every policy, binding and guard.
- `test/e2e/homelab-policies.sh` (`mise run e2e`): the policies on a real API
  server (kind, Kubernetes 1.34 to 1.36), 24 server-side dry runs: accepted
  and refused images for each rule, each workload kind, init containers,
  registry look-alikes and ports, `Warn` outside opted-in namespaces,
  excluded namespaces untouched.
- Mutation campaign (ADR 0005).
