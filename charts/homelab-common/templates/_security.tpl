{{/*
Security contexts that satisfy Pod Security "restricted".

  securityContext:
    {{- include "homelab-common.podSecurityContext" (dict "securityContext" .Values.podSecurityContext) | nindent 4 }}
  ...
      securityContext:
        {{- include "homelab-common.containerSecurityContext" (dict "securityContext" .Values.securityContext "path" "securityContext") | nindent 8 }}

Caller values are deep-merged over the defaults with mergeOverwrite: an
explicit `false` wins, and `capabilities: {add: [NET_BIND_SERVICE]}` keeps the
default `drop: [ALL]`. Never swap it for `merge $values $defaults`: merge treats
`false` as empty and silently restores the default.

The "restricted" rules are then checked, so a violation fails at render time
(helm template, ArgoCD diff) rather than at admission, when the namespace
rejects the pod and only the ReplicaSet events tell why.
*/}}

{{- define "homelab-common.podSecurityContext" -}}
{{- $path := .path | default "podSecurityContext" -}}
{{- $defaults := dict
      "runAsNonRoot" true
      "seccompProfile" (dict "type" "RuntimeDefault") -}}
{{- $sc := mergeOverwrite $defaults (deepCopy (.securityContext | default dict)) -}}
{{- include "homelab-common.validateRestricted" (dict "securityContext" $sc "path" $path) -}}
{{- toYaml $sc -}}
{{- end -}}

{{- define "homelab-common.containerSecurityContext" -}}
{{- $path := .path | default "securityContext" -}}
{{- $defaults := dict
      "allowPrivilegeEscalation" false
      "readOnlyRootFilesystem" true
      "capabilities" (dict "drop" (list "ALL")) -}}
{{- $sc := mergeOverwrite $defaults (deepCopy (.securityContext | default dict)) -}}
{{- include "homelab-common.validateRestricted" (dict "securityContext" $sc "path" $path "container" true) -}}
{{- toYaml $sc -}}
{{- end -}}

{{/*
Internal: fails on any setting that Pod Security "restricted" (or "baseline",
which it includes) rejects. Renders nothing.
*/}}
{{- define "homelab-common.validateRestricted" -}}
{{- $sc := .securityContext -}}
{{- $path := .path -}}
{{- if .container -}}
  {{- if and (hasKey $sc "runAsNonRoot") (ne (toString $sc.runAsNonRoot) "true") -}}
    {{- fail (printf "homelab-common: %s.runAsNonRoot must not be false (Pod Security restricted)" $path) -}}
  {{- end -}}
{{- else if ne (toString $sc.runAsNonRoot) "true" -}}
  {{- fail (printf "homelab-common: %s.runAsNonRoot must be true (Pod Security restricted)" $path) -}}
{{- end -}}
{{- if and (hasKey $sc "runAsUser") (not (kindIs "invalid" $sc.runAsUser)) (eq (int $sc.runAsUser) 0) -}}
  {{- fail (printf "homelab-common: %s.runAsUser must not be 0 (Pod Security restricted)" $path) -}}
{{- end -}}
{{- with $sc.seccompProfile -}}
  {{- if not (has .type (list "RuntimeDefault" "Localhost")) -}}
    {{- fail (printf "homelab-common: %s.seccompProfile.type must be RuntimeDefault or Localhost, got %q (Pod Security restricted)" $path (toString .type)) -}}
  {{- end -}}
{{- end -}}
{{- if .container -}}
  {{- if $sc.privileged -}}
    {{- fail (printf "homelab-common: %s.privileged must not be true (Pod Security baseline)" $path) -}}
  {{- end -}}
  {{- if ne (toString $sc.allowPrivilegeEscalation) "false" -}}
    {{- fail (printf "homelab-common: %s.allowPrivilegeEscalation must be false (Pod Security restricted)" $path) -}}
  {{- end -}}
  {{- $caps := $sc.capabilities | default dict -}}
  {{- if not (has "ALL" ($caps.drop | default list)) -}}
    {{- fail (printf "homelab-common: %s.capabilities.drop must contain ALL (Pod Security restricted)" $path) -}}
  {{- end -}}
  {{- range ($caps.add | default list) -}}
    {{- if ne . "NET_BIND_SERVICE" -}}
      {{- fail (printf "homelab-common: %s.capabilities.add may only contain NET_BIND_SERVICE, got %q (Pod Security restricted)" $path .) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
