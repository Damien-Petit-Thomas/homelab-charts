{{/*
ExternalSecrets (external-secrets.io/v1) rendered from a map in values, so
that no chart ever needs a Secret manifest or a secret value in values.

  {{- include "homelab-common.externalSecrets" (dict "context" $) }}

  externalSecrets:
    oidc:                                  # map key: suffix of the default name
      secretStoreRef:
        name: vault-backend                # required
        kind: ClusterSecretStore           # default
      refreshInterval: 1h                  # default
      target:
        name: my-app-oidc                  # default: <fullname>-<key>
        creationPolicy: Owner              # default
        deletionPolicy: Retain             # default
        template: {}                       # optional, passed through
      data:                                # data and/or dataFrom required
        - secretKey: CLIENT_SECRET
          remoteRef:
            key: homelab/my-app-oidc
            property: client-secret
      dataFrom: []                         # optional, passed through
    other:
      enabled: false                       # skips this entry

With creationPolicy Owner the Secret carries an ownerReference to its
ExternalSecret: deleting the ExternalSecret garbage-collects the Secret.
deletionPolicy only covers a secret deleted on the provider side.
*/}}

{{- define "homelab-common.externalSecrets" -}}
{{- $ctx := required "homelab-common.externalSecrets: \"context\" is required" .context -}}
{{- range $key, $spec := $ctx.Values.externalSecrets -}}
  {{- if ne (toString (dig "enabled" true ($spec | default dict))) "false" }}
---
{{ include "homelab-common.externalSecret" (dict "context" $ctx "key" $key "spec" $spec) }}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- define "homelab-common.externalSecret" -}}
{{- $ctx := required "homelab-common.externalSecret: \"context\" is required" .context -}}
{{- $key := required "homelab-common.externalSecret: \"key\" is required" .key -}}
{{- $spec := .spec | default dict -}}
{{- $path := printf "externalSecrets.%s" $key -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $key) -}}
  {{- fail (printf "homelab-common: %s: the key must be a DNS-1123 label, it becomes part of a resource name" $path) -}}
{{- end -}}
{{- $store := $spec.secretStoreRef | default dict -}}
{{- $storeName := required (printf "homelab-common: %s.secretStoreRef.name is required" $path) $store.name -}}
{{- $storeKind := $store.kind | default "ClusterSecretStore" -}}
{{- if not (has $storeKind (list "SecretStore" "ClusterSecretStore")) -}}
  {{- fail (printf "homelab-common: %s.secretStoreRef.kind must be SecretStore or ClusterSecretStore, got %q" $path $storeKind) -}}
{{- end -}}
{{- if not (or $spec.data $spec.dataFrom) -}}
  {{- fail (printf "homelab-common: %s needs data or dataFrom" $path) -}}
{{- end -}}
{{- range $i, $item := $spec.data -}}
  {{- $_ := required (printf "homelab-common: %s.data[%d].secretKey is required" $path $i) $item.secretKey -}}
  {{- $_ := required (printf "homelab-common: %s.data[%d].remoteRef.key is required" $path $i) (dig "remoteRef" "key" "" $item) -}}
{{- end -}}
{{- $target := $spec.target | default dict -}}
{{- $targetName := $target.name | default (printf "%s-%s" (include "homelab-common.fullname" $ctx) $key | trunc 63 | trimSuffix "-") -}}
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ $targetName }}
  namespace: {{ $ctx.Release.Namespace }}
  labels:
    {{- include "homelab-common.labels" (dict "context" $ctx) | nindent 4 }}
  {{- with $spec.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  refreshInterval: {{ $spec.refreshInterval | default "1h" }}
  secretStoreRef:
    name: {{ $storeName }}
    kind: {{ $storeKind }}
  target:
    name: {{ $targetName }}
    creationPolicy: {{ $target.creationPolicy | default "Owner" }}
    deletionPolicy: {{ $target.deletionPolicy | default "Retain" }}
    {{- with $target.template }}
    template:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  {{- with $spec.data }}
  data:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $spec.dataFrom }}
  dataFrom:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
