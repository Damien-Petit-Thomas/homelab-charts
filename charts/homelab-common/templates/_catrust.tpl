{{/*
Homelab CA trust: the ca-updater init container merges the system bundle and
the homelab root CA (from a ConfigMap) into a bundle on a shared emptyDir; the
app container mounts it read-only and points SSL_CERT_FILE at it (honoured by
OpenSSL, Go and rustls-native-certs). The init container needs no network
and no root, unlike an `apk add ca-certificates` at startup.

  caTrust:
    enabled: true
    configMap: homelab-ca          # required: ConfigMap holding the CA
    key: ca.crt                    # default
    image: {repository: ..., tag: ..., digest: ...}

  initContainers:
    {{- include "homelab-common.caTrust.initContainer" (dict "caTrust" .Values.caTrust) | nindent 4 }}
  containers:
    - env:
        {{- include "homelab-common.caTrust.env" (dict "caTrust" .Values.caTrust) | nindent 8 }}
      volumeMounts:
        {{- include "homelab-common.caTrust.volumeMounts" (dict "caTrust" .Values.caTrust) | nindent 8 }}
  volumes:
    {{- include "homelab-common.caTrust.volumes" (dict "caTrust" .Values.caTrust) | nindent 4 }}

Each helper renders nothing when caTrust.enabled is false. Node.js ignores
SSL_CERT_FILE: set NODE_EXTRA_CA_CERTS to the CA file in the chart itself.
*/}}

{{- define "homelab-common.caTrust.bundleDir" -}}/etc/ssl/homelab{{- end -}}

{{- define "homelab-common.caTrust.initContainer" -}}
{{- $ca := .caTrust | default dict -}}
{{- if $ca.enabled -}}
{{- $key := $ca.key | default "ca.crt" -}}
- name: ca-trust
  image: {{ include "homelab-common.image" (dict "image" $ca.image "path" "caTrust.image") }}
  imagePullPolicy: IfNotPresent
  env:
    - name: CA_SOURCE
      value: /custom-ca/{{ $key }}
    - name: BUNDLE_OUT
      value: /shared-ca/ca-certificates.crt
  securityContext:
    {{- include "homelab-common.containerSecurityContext" (dict "securityContext" (dict "runAsNonRoot" true) "path" "caTrust.securityContext") | nindent 4 }}
  {{- with $ca.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: ca-trust-source
      mountPath: /custom-ca
      readOnly: true
    - name: ca-trust-bundle
      mountPath: /shared-ca
{{- end -}}
{{- end -}}

{{- define "homelab-common.caTrust.volumes" -}}
{{- $ca := .caTrust | default dict -}}
{{- if $ca.enabled -}}
- name: ca-trust-source
  configMap:
    name: {{ required "homelab-common: caTrust.configMap is required when caTrust.enabled is true" $ca.configMap }}
    items:
      - key: {{ $ca.key | default "ca.crt" }}
        path: {{ $ca.key | default "ca.crt" }}
- name: ca-trust-bundle
  emptyDir:
    sizeLimit: 2Mi
{{- end -}}
{{- end -}}

{{- define "homelab-common.caTrust.volumeMounts" -}}
{{- $ca := .caTrust | default dict -}}
{{- if $ca.enabled -}}
- name: ca-trust-bundle
  mountPath: {{ include "homelab-common.caTrust.bundleDir" . }}
  readOnly: true
{{- end -}}
{{- end -}}

{{- define "homelab-common.caTrust.env" -}}
{{- $ca := .caTrust | default dict -}}
{{- if $ca.enabled -}}
- name: SSL_CERT_FILE
  value: {{ include "homelab-common.caTrust.bundleDir" . }}/ca-certificates.crt
{{- end -}}
{{- end -}}
