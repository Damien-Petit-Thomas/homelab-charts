#!/usr/bin/env bash
# Installation test of the homelab-policies chart on a throwaway kind cluster
# (`mise run e2e`). The CEL expressions are evaluated by the API server
# itself: each case is a server-side dry run (admission runs, nothing is
# persisted), checked for acceptance or for the expected refusal message.
set -euo pipefail

CHART=charts/homelab-policies
RELEASE=homelab-policies
DENY_NS=policies-enforce
WARN_NS=policies-warn
D=sha256:5f34faf7cbbdd13963fd2aba914e39d2987e341508beda9f771ec3ecfe96759b

step() { printf '\n== [%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

context="$(kubectl config current-context)"
[[ "$context" == kind-* ]] || fail "current context '$context' is not a kind cluster"

cleanup() {
  helm uninstall "$RELEASE" --wait >/dev/null 2>&1 || true
  kubectl delete namespace "$DENY_NS" "$WARN_NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Manifest of a workload of kind $1 whose pod runs image $2, in namespace $3.
# A Job also gets an init container running $4 (default: a compliant image).
manifest() {
  local kind="$1" image="$2" ns="$3" init="${4:-docker.io/library/busybox:1.37.0@$D}"
  local pod="containers: [{name: main, image: \"$image\"}]"
  case "$kind" in
    Deployment) cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: case, namespace: $ns}
spec:
  selector: {matchLabels: {app: case}}
  template:
    metadata: {labels: {app: case}}
    spec: {$pod}
EOF
    ;;
    CronJob) cat <<EOF
apiVersion: batch/v1
kind: CronJob
metadata: {name: case, namespace: $ns}
spec:
  schedule: "0 0 1 1 *"
  jobTemplate:
    spec:
      template:
        spec: {restartPolicy: Never, $pod}
EOF
    ;;
    Job) cat <<EOF
apiVersion: batch/v1
kind: Job
metadata: {name: case, namespace: $ns}
spec:
  template:
    spec:
      restartPolicy: Never
      initContainers: [{name: init, image: "$init"}]
      $pod
EOF
    ;;
    Pod) cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: case, namespace: $ns}
spec: {$pod}
EOF
    ;;
  esac
}

# expect accept|deny|warn <description> <expected message (bash regex) or -> <manifest args...>
expect() {
  local want="$1" desc="$2" msg="$3"; shift 3
  local out rc=0
  out="$(manifest "$@" | kubectl apply --dry-run=server -f - 2>&1)" || rc=$?
  case "$want" in
    accept) [[ $rc -eq 0 && "$out" != *Warning* ]] || fail "$desc: expected a clean accept, got rc=$rc: $out" ;;
    deny)   [[ $rc -ne 0 && "$out" =~ $msg ]] || fail "$desc: expected a denial matching '$msg', got rc=$rc: $out" ;;
    warn)   [[ $rc -eq 0 && "$out" == *Warning* && "$out" =~ $msg ]] || fail "$desc: expected an accept with a warning matching '$msg', got rc=$rc: $out" ;;
  esac
  printf '  ok  %-6s %s\n' "$want" "$desc"
}

step "namespaces: one opted in to Deny, one left in Warn"
kubectl create namespace "$DENY_NS" >/dev/null
kubectl label namespace "$DENY_NS" homelab.internal/policies=enforce >/dev/null
kubectl create namespace "$WARN_NS" >/dev/null

step "install"
helm install "$RELEASE" "$CHART" --wait
kubectl get validatingadmissionpolicies,validatingadmissionpolicybindings -l app.kubernetes.io/instance="$RELEASE"

step "type checking reported by the API server"
kubectl get validatingadmissionpolicies -l app.kubernetes.io/instance="$RELEASE" -o json \
  | jq -r '.items[] | "\(.metadata.name): \((.status.typeChecking.expressionWarnings // []) | length) warning(s)"'

# Bindings take effect asynchronously: wait until a known-bad object is refused.
for _ in $(seq 30); do
  if ! manifest Pod "busybox:1.37.0" "$DENY_NS" | kubectl apply --dry-run=server -f - >/dev/null 2>&1; then break; fi
  sleep 2
done

step "opted-in namespace: Deny"
expect accept "digest-pinned image from an allowed registry"   - Deployment "docker.io/library/busybox:1.37.0@$D" "$DENY_NS"
expect accept "implicit docker.io, normalized"                  - Deployment "busybox:1.37.0@$D" "$DENY_NS"
expect accept "digest without tag"                              - Deployment "ghcr.io/example/app@$D" "$DENY_NS"
expect deny   "tag without digest"            "must be pinned by digest" Deployment "ghcr.io/example/app:1.2.3" "$DENY_NS"
expect deny   "latest tag even with a digest" "latest tag is not allowed" Deployment "ghcr.io/example/app:latest@$D" "$DENY_NS"
# Breaks two rules: the API server reports the first refusal only.
expect deny   "no tag and no digest"          "pinned by digest|need a tag or a digest" Deployment "ghcr.io/example/app" "$DENY_NS"
expect deny   "registry not allowed"          "must come from" Deployment "registry.evil.example/app:1@$D" "$DENY_NS"
expect deny   "look-alike registry"           "must come from" Deployment "ghcr.io.evil.example/app:1@$D" "$DENY_NS"
expect deny   "registry with a port"          "must come from" Deployment "localhost:5000/app:1@$D" "$DENY_NS"
expect deny   "CronJob pod template"          "must be pinned by digest" CronJob "ghcr.io/example/app:1.2.3" "$DENY_NS"
expect deny   "Job init container"            "must be pinned by digest" Job "ghcr.io/example/app:1@$D" "$DENY_NS" "ghcr.io/example/init:1.0"
expect deny   "bare Pod"                      "must be pinned by digest" Pod "ghcr.io/example/app:1.2.3" "$DENY_NS"

step "no-latest on its own (digest and registry rules disabled)"
helm upgrade "$RELEASE" "$CHART" --set rules.imageDigest.enabled=false --set rules.allowedRegistries.enabled=false --wait >/dev/null
for _ in $(seq 30); do
  out="$(manifest Pod "ghcr.io/example/app:1.2.3" "$DENY_NS" | kubectl apply --dry-run=server -f - 2>&1)" && break
  sleep 2
done
expect accept "tag without digest, digest rule off"   - Deployment "ghcr.io/example/app:1.2.3" "$DENY_NS"
expect deny   "latest tag without digest"     "latest tag is not allowed" Deployment "ghcr.io/example/app:latest" "$DENY_NS"
expect deny   "no tag and no digest"          "need a tag or a digest" Deployment "ghcr.io/example/app" "$DENY_NS"
expect deny   "registry port is not a tag"    "need a tag or a digest" Deployment "localhost:5000/app" "$DENY_NS"
expect accept "registry port and a tag"       - Deployment "localhost:5000/app:1.0" "$DENY_NS"
# --reset-values: without values, helm upgrade reuses the previous release's
# (the rules would stay disabled).
helm upgrade "$RELEASE" "$CHART" --reset-values --wait >/dev/null
for _ in $(seq 30); do
  out="$(manifest Pod "ghcr.io/example/app:1.2.3" "$DENY_NS" | kubectl apply --dry-run=server -f - 2>&1)" || true
  [[ "$out" == *"homelab-image-digest-enforce"* ]] && break
  sleep 2
done

step "other namespaces: Warn, nothing blocked"
# The audit bindings were recreated by the upgrade: wait until they warn.
for i in $(seq 30); do
  out="$(manifest Pod "ghcr.io/example/app:1.2.3" "$WARN_NS" | kubectl apply --dry-run=server -f - 2>&1)" || true
  [[ "$out" == *Warning* ]] && { echo "  audit bindings active after ${i} attempt(s)"; break; }
  sleep 2
done
expect warn   "tag without digest"            "must be pinned by digest" Deployment "ghcr.io/example/app:1.2.3" "$WARN_NS"
expect accept "compliant image, no warning"   - Deployment "docker.io/library/busybox:1.37.0@$D" "$WARN_NS"

step "excluded namespace: not evaluated"
expect accept "kube-system, non-compliant image" - Pod "ghcr.io/example/app:latest" kube-system

step "all policy tests passed"
