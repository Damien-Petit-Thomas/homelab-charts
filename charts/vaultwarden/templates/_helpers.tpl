{{/*
Fails on what values.schema.json cannot express: values required only in
some configurations. URL formats are checked by the schema alone.
*/}}
{{- define "vaultwarden.validate" -}}
{{- $_ := required "vaultwarden: domain is required (e.g. https://vaultwarden.example.org)" .Values.domain -}}
{{- if .Values.sso.enabled -}}
  {{- $authority := required "vaultwarden: sso.authority is required when sso.enabled is true" .Values.sso.authority -}}
  {{- if contains "/.well-known/" $authority -}}
    {{- fail "vaultwarden: sso.authority must not include /.well-known/openid-configuration: discovery appends it" -}}
  {{- end -}}
  {{- $_ := required "vaultwarden: sso.clientSecret.existingSecret is required when sso.enabled is true" .Values.sso.clientSecret.existingSecret -}}
{{- end -}}
{{- end -}}

{{/*
Environment of the Vaultwarden container. extraEnv may not redefine a
variable set here: two entries with the same name are not an error for the
API server, the last one silently wins.
*/}}
{{- define "vaultwarden.env" -}}
{{- $env := list
      (dict "name" "DOMAIN" "value" .Values.domain)
      (dict "name" "ROCKET_PORT" "value" "8080")
      (dict "name" "DATA_FOLDER" "value" "/data")
      (dict "name" "TMP_FOLDER" "value" "/tmp")
      (dict "name" "SIGNUPS_ALLOWED" "value" (toString .Values.signupsAllowed))
      (dict "name" "INVITATIONS_ALLOWED" "value" (toString .Values.invitationsAllowed))
      (dict "name" "PASSWORD_HINTS_ALLOWED" "value" (toString .Values.passwordHintsAllowed))
      (dict "name" "IP_HEADER" "value" .Values.ipHeader)
      (dict "name" "LOG_LEVEL" "value" .Values.logLevel) -}}
{{- with .Values.admin.existingSecret -}}
  {{- $env = append $env (dict "name" "ADMIN_TOKEN" "valueFrom" (dict "secretKeyRef" (dict "name" . "key" $.Values.admin.key))) -}}
{{- end -}}
{{- if .Values.sso.enabled -}}
  {{- $sso := .Values.sso -}}
  {{- $env = concat $env (list
        (dict "name" "SSO_ENABLED" "value" "true")
        (dict "name" "SSO_ONLY" "value" (toString $sso.only))
        (dict "name" "SSO_AUTH_ONLY_NOT_SESSION" "value" (toString $sso.authOnlyNotSession))
        (dict "name" "SSO_SIGNUPS_ALLOWED" "value" (toString $sso.signupsAllowed))
        (dict "name" "SSO_SIGNUPS_MATCH_EMAIL" "value" (toString $sso.signupsMatchEmail))
        (dict "name" "SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION" "value" "false")
        (dict "name" "SSO_AUTHORITY" "value" $sso.authority)
        (dict "name" "SSO_CLIENT_ID" "value" $sso.clientId)
        (dict "name" "SSO_CLIENT_SECRET" "valueFrom" (dict "secretKeyRef" (dict "name" $sso.clientSecret.existingSecret "key" $sso.clientSecret.key)))
        (dict "name" "SSO_SCOPES" "value" $sso.scopes)
        (dict "name" "SSO_PKCE" "value" (toString $sso.pkce))) -}}
{{- end -}}
{{- with include "homelab-common.caTrust.env" (dict "caTrust" .Values.caTrust) -}}
  {{- $env = concat $env (fromYamlArray .) -}}
{{- end -}}
{{- $managed := list -}}
{{- range $env -}}
  {{- $managed = append $managed .name -}}
{{- end -}}
{{- range .Values.extraEnv -}}
  {{- if has .name $managed -}}
    {{- fail (printf "vaultwarden: extraEnv may not redefine %s, which the chart manages" .name) -}}
  {{- end -}}
{{- end -}}
{{- $env = concat $env .Values.extraEnv -}}
{{- toYaml $env -}}
{{- end -}}

{{/*
Volume holding /data.
*/}}
{{- define "vaultwarden.dataClaim" -}}
{{- .Values.persistence.existingClaim | default (printf "%s-data" (include "homelab-common.fullname" .)) -}}
{{- end -}}

{{- define "vaultwarden.backupClaim" -}}
{{- .Values.backup.persistence.existingClaim | default (printf "%s-backup" (include "homelab-common.fullname" .)) -}}
{{- end -}}

{{/*
Label that lets a pod reach Vaultwarden through the NetworkPolicy (used by
the helm test pod). The key stays under the 63-character limit of a label
name; the value scopes it to this release.
*/}}
{{- define "vaultwarden.clientLabel" -}}
{{ include "homelab-common.name" . | trunc 56 | trimSuffix "-" }}-client: {{ include "homelab-common.fullname" . }}
{{- end -}}
