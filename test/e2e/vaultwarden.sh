#!/usr/bin/env bash
# Installation test of the vaultwarden chart on a throwaway kind cluster
# (`mise run e2e` creates it). Proves on a real API server what unit tests
# cannot: admission under Pod Security "restricted", the helm test, the
# NetworkPolicy, a backup, a restore after data loss following the README
# procedure as written, and the data claim surviving `helm uninstall`.
set -euo pipefail

NS=vaultwarden
RELEASE=vaultwarden            # release = chart name: resources are named "vaultwarden"
CHART=charts/vaultwarden
HERE="$(cd "$(dirname "$0")" && pwd)"
IMAGE="$(yq -r '.image.repository + ":" + .image.tag + "@" + .image.digest' "$CHART/values.yaml")"
EMAIL=e2e@example.org
# The server never sees the master password, only a client-side hash: any
# base64 string works for the test.
PASSWORD_HASH=ZTJlLWhhc2g=

step() { printf '\n== [%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# Never run against anything but a kind cluster.
context="$(kubectl config current-context)"
[[ "$context" == kind-* ]] || fail "current context '$context' is not a kind cluster"

diagnostics() {
  echo "--- diagnostics" >&2
  kubectl -n "$NS" get all,pvc,networkpolicy,jobs -o wide >&2 || true
  kubectl -n "$NS" get events --sort-by=.lastTimestamp >&2 | tail -n 30 || true
  kubectl -n "$NS" logs deployment/"$RELEASE" --tail=50 >&2 || true
}
on_exit() {
  local rc=$?
  [[ "$rc" -eq 0 ]] || diagnostics
  exit "$rc"
}
trap on_exit EXIT

# Runs a one-shot pod (restricted security context, Vaultwarden image for
# its curl) and prints its logs; returns the container's exit code.
# $1: pod name, $2: "client" to carry the label the NetworkPolicy admits,
# then the command.
run_pod() {
  local name="$1" kind="$2"; shift 2
  local labels='{}' command
  # `--` stops jq's option parsing: curl flags such as --max-time would
  # otherwise be read as jq options, leaving the pod without a command.
  command="$(jq -cn '$ARGS.positional' --args -- "$@")" || fail "cannot encode the command of pod $name"
  [[ "$kind" == client ]] && labels="{\"vaultwarden-client\": \"$RELEASE\"}"
  kubectl -n "$NS" delete pod "$name" --ignore-not-found --wait >/dev/null
  kubectl -n "$NS" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $name
  labels: $labels
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: main
      image: $IMAGE
      command: $command
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: {drop: [ALL]}
EOF
  # Wait for either end state: `kubectl wait` takes a single condition.
  local phase="" deadline=$((SECONDS + 120))
  while [[ "$phase" != Succeeded && "$phase" != Failed ]]; do
    ((SECONDS < deadline)) || fail "pod $name did not finish within 120s (phase: ${phase:-none})"
    sleep 2
    phase="$(kubectl -n "$NS" get pod "$name" -o jsonpath='{.status.phase}')"
  done
  # Logs go to stdout: callers capture them (e.g. an HTTP status code).
  # The trailing newline keeps the next message (curl output often has none)
  # on its own line.
  kubectl -n "$NS" logs "$name"
  echo
  local code
  code="$(kubectl -n "$NS" get pod "$name" -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}')"
  kubectl -n "$NS" delete pod "$name" --wait=false >/dev/null
  return "${code:-1}"
}

url="http://$RELEASE:8080"
login() {
  run_pod "$1" client curl -sS -o /dev/null -w '%{http_code}' \
    -d grant_type=password -d "username=$EMAIL" -d "password=$PASSWORD_HASH" \
    -d 'scope=api offline_access' -d client_id=web -d deviceType=10 \
    -d deviceIdentifier=00000000-0000-4000-8000-000000000001 -d deviceName=e2e \
    "$url/identity/connect/token"
}

step "namespace enforcing Pod Security restricted"
kubectl create namespace "$NS"
kubectl label namespace "$NS" \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted

step "backup claim, provided by the operator (the chart never creates it)"
kubectl -n "$NS" apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: vaultwarden-backup
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
EOF

step "install"
helm install "$RELEASE" "$CHART" -n "$NS" -f "$HERE/vaultwarden-values.yaml" --wait --timeout 5m

step "helm test"
helm test "$RELEASE" -n "$NS" --logs

step "NetworkPolicy: a labelled client is admitted"
run_pod np-allowed client curl -fsS --max-time 10 "$url/alive" \
  || fail "the client pod could not reach Vaultwarden"

step "NetworkPolicy: any other pod is refused"
if run_pod np-denied none curl -fsS --max-time 10 "$url/alive"; then
  fail "an unlabelled pod reached Vaultwarden: the NetworkPolicy is not enforced"
fi

step "create an account"
code="$(run_pod register client curl -sS -o /dev/null -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"name\":\"e2e\",\"masterPasswordHash\":\"$PASSWORD_HASH\",\"key\":\"2.dGVzdA==|dGVzdA==|dGVzdA==\",\"kdf\":0,\"kdfIterations\":600000,\"keys\":{\"publicKey\":\"dGVzdA==\",\"encryptedPrivateKey\":\"2.dGVzdA==|dGVzdA==|dGVzdA==\"}}" \
  "$url/identity/accounts/register")"
[[ "$code" == 200 ]] || fail "registration returned $code"
[[ "$(login login-before)" == 200 ]] || fail "login failed before the backup"

step "backup"
kubectl -n "$NS" create job --from=cronjob/"$RELEASE"-backup "$RELEASE"-backup-e2e
kubectl -n "$NS" wait --for=condition=complete job/"$RELEASE"-backup-e2e --timeout=300s
kubectl -n "$NS" logs job/"$RELEASE"-backup-e2e | tee /dev/stderr | grep -q '^backup: wrote ' \
  || fail "the backup job did not report an archive"

step "simulate data loss"
kubectl -n "$NS" scale deployment "$RELEASE" --replicas=0
kubectl -n "$NS" wait --for=delete pod -l app.kubernetes.io/instance="$RELEASE",app.kubernetes.io/component=server --timeout=120s || true
kubectl -n "$NS" create job --from=cronjob/"$RELEASE"-backup "$RELEASE"-wipe --dry-run=client -o json \
  | jq '.spec.template.spec.containers[0].command = ["/bin/sh", "-c", "rm -f /data/db.sqlite3* /data/rsa_key.pem && test ! -e /data/db.sqlite3 && test ! -e /data/rsa_key.pem && echo wiped"]' \
  | kubectl -n "$NS" apply -f -
kubectl -n "$NS" wait --for=condition=complete job/"$RELEASE"-wipe --timeout=120s
# Without this, a wipe that silently failed would let the login below pass
# without proving anything about the restore.
kubectl -n "$NS" logs job/"$RELEASE"-wipe | grep -qx wiped || fail "the data was not wiped"

step "restore, running the README procedure as written"
procedure="$(sed -n '/<!-- restore-procedure:begin/,/<!-- restore-procedure:end/p' "$CHART/README.md" | sed '1,2d;$d' | sed '$d')"
[[ -n "$procedure" ]] || fail "restore procedure not found in $CHART/README.md"
printf '%s\n' "$procedure"
bash -euo pipefail -c "$procedure"
kubectl -n "$NS" rollout status deployment "$RELEASE" --timeout=300s

step "the account survived"
[[ "$(login login-after)" == 200 ]] || fail "login failed after the restore: the account was not restored"
helm test "$RELEASE" -n "$NS" --logs

step "uninstall keeps the data claim"
helm uninstall "$RELEASE" -n "$NS" --wait
kubectl -n "$NS" get pvc "$RELEASE"-data >/dev/null || fail "the data claim was deleted with the release"
echo "kept: $RELEASE-data"

step "all installation tests passed"
