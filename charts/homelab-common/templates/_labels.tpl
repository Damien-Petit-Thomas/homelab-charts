{{/*
Label helpers. They take a dict:
  include "homelab-common.labels" (dict "context" $ "component" "server")

"component" is optional, but in a chart with several workloads every workload
must set one: without it, the selector of the main workload (name + instance)
would also match the pods of the others.
*/}}

{{/*
Selector labels: the immutable subset used in spec.selector and Service
selectors. Never add a label here in a minor release: Deployment selectors
cannot change, the upgrade would fail.
*/}}
{{- define "homelab-common.selectorLabels" -}}
{{- include "homelab-common.selectorLabelsDict" . -}}
{{- end -}}

{{/* Internal: selector labels as YAML, parsed back by homelab-common.labels. */}}
{{- define "homelab-common.selectorLabelsDict" -}}
{{- $ctx := required "homelab-common.selectorLabels: \"context\" is required" .context -}}
{{- $labels := dict
      "app.kubernetes.io/name" (include "homelab-common.name" $ctx)
      "app.kubernetes.io/instance" $ctx.Release.Name -}}
{{- with .component -}}
  {{- $_ := set $labels "app.kubernetes.io/component" . -}}
{{- end -}}
{{- toYaml $labels -}}
{{- end -}}

{{/*
Standard labels: selector labels, chart, version and manager, then
.Values.commonLabels. A common label may not redefine a standard one: the
chart fails instead of silently dropping either value.
*/}}
{{- define "homelab-common.labels" -}}
{{- $ctx := required "homelab-common.labels: \"context\" is required" .context -}}
{{- $labels := include "homelab-common.selectorLabelsDict" . | fromYaml -}}
{{- $_ := set $labels "helm.sh/chart" (include "homelab-common.chart" $ctx) -}}
{{- $_ := set $labels "app.kubernetes.io/managed-by" $ctx.Release.Service -}}
{{- with $ctx.Chart.AppVersion -}}
  {{- $version := regexReplaceAll "[^-A-Za-z0-9_.]" (toString .) "_" | trunc 63 -}}
  {{- $version = regexReplaceAll "^[^A-Za-z0-9]+|[^A-Za-z0-9]+$" $version "" -}}
  {{- $_ := set $labels "app.kubernetes.io/version" $version -}}
{{- end -}}
{{- range $key, $value := $ctx.Values.commonLabels -}}
  {{- if hasKey $labels $key -}}
    {{- fail (printf "homelab-common: commonLabels may not redefine the standard label %q" $key) -}}
  {{- end -}}
  {{- $_ := set $labels $key (toString $value) -}}
{{- end -}}
{{- toYaml $labels -}}
{{- end -}}
