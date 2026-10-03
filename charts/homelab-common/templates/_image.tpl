{{/*
Image reference pinned by digest: "<repository>[:<tag>]@<digest>".

  image: {{ include "homelab-common.image" (dict "image" .Values.image "path" "image") }}

  image:
    repository: docker.io/vaultwarden/server
    tag: 1.37.3          # optional, for humans: the digest decides
    digest: sha256:...   # required

A tag alone is mutable: the same values could deploy different code. The
digest is therefore required, and checked here so that the error shows at
render time (helm template, ArgoCD diff) instead of as a pull failure.
"path" names the values key in error messages.
*/}}
{{- define "homelab-common.image" -}}
{{- $path := .path | default "image" -}}
{{- $image := .image | default dict -}}
{{- $repository := required (printf "homelab-common: %s.repository is required" $path) $image.repository -}}
{{- $digest := required (printf "homelab-common: %s.digest is required: images are pinned by digest" $path) $image.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" $digest) -}}
  {{- fail (printf "homelab-common: %s.digest %q is not a sha256 digest (sha256:<64 hex>)" $path $digest) -}}
{{- end -}}
{{- if contains "@" $repository -}}
  {{- fail (printf "homelab-common: %s.repository %q contains a digest: set it in %s.digest" $path $repository $path) -}}
{{- end -}}
{{- with $image.tag -}}
  {{- $tag := toString . -}}
  {{- if contains "@" $tag -}}
    {{- fail (printf "homelab-common: %s.tag %q contains a digest: set it in %s.digest" $path $tag $path) -}}
  {{- end -}}
  {{- if eq $tag "latest" -}}
    {{- fail (printf "homelab-common: %s.tag \"latest\" is not allowed" $path) -}}
  {{- end -}}
  {{- printf "%s:%s@%s" $repository $tag $digest -}}
{{- else -}}
  {{- printf "%s@%s" $repository $digest -}}
{{- end -}}
{{- end -}}
