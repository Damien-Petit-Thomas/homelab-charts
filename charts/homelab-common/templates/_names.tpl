{{/*
Naming helpers. They take the root context: include "homelab-common.fullname" .
*/}}

{{/*
Chart name, or .Values.nameOverride.
*/}}
{{- define "homelab-common.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Name of the release's resources: .Values.fullnameOverride, the release name
when it equals the chart name or already ends with "-<name>", otherwise
"<release>-<name>". The usual scaffold tests `contains $name .Release.Name`,
a substring match: chart "app" in release "happy" would yield "happy".
Fails when the result is not a valid DNS-1035 label, which Services require.
*/}}
{{- define "homelab-common.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- $fullname := "" -}}
{{- if .Values.fullnameOverride -}}
  {{- $fullname = .Values.fullnameOverride -}}
{{- else if or (eq .Release.Name $name) (hasSuffix (printf "-%s" $name) .Release.Name) -}}
  {{- $fullname = .Release.Name -}}
{{- else -}}
  {{- $fullname = printf "%s-%s" .Release.Name $name -}}
{{- end -}}
{{- $fullname = $fullname | trunc 63 | trimSuffix "-" -}}
{{- if not (regexMatch "^[a-z]([-a-z0-9]*[a-z0-9])?$" $fullname) -}}
  {{- fail (printf "homelab-common: resource name %q is not a valid DNS-1035 label (lowercase alphanumerics and '-', starting with a letter)" $fullname) -}}
{{- end -}}
{{- $fullname -}}
{{- end -}}

{{/*
Value of the helm.sh/chart label: "<name>-<version>", "+" replaced because
label values do not allow it.
*/}}
{{- define "homelab-common.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Service account name: the one given in .Values.serviceAccount.name, else the
fullname when the chart creates it, else "default".
*/}}
{{- define "homelab-common.serviceAccountName" -}}
{{- $sa := .Values.serviceAccount | default dict -}}
{{- if $sa.create -}}
{{- default (include "homelab-common.fullname" .) $sa.name -}}
{{- else -}}
{{- default "default" $sa.name -}}
{{- end -}}
{{- end -}}
