{{/*
One rule = one ValidatingAdmissionPolicy and two bindings:
  <prefix><rule>-audit    auditActions (Warn, Audit) in every evaluated
                          namespace that has not opted in;
  <prefix><rule>-enforce  Deny in namespaces carrying the enforce label.

Call: include "homelab-policies.rule" (dict "context" $ "name" "image-digest"
        "validations" (list (dict "expression" "..." "messageExpression" "...")))
*/}}
{{- define "homelab-policies.rule" -}}
{{- $ctx := .context -}}
{{- $v := $ctx.Values -}}
{{- $name := printf "%s%s" $v.namePrefix .name -}}
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: {{ $name }}
  labels:
    {{- include "homelab-policies.labels" $ctx | nindent 4 }}
spec:
  failurePolicy: {{ $v.failurePolicy }}
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        resources: ["pods"]
        operations: ["CREATE", "UPDATE"]
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
        operations: ["CREATE", "UPDATE"]
      - apiGroups: ["batch"]
        apiVersions: ["v1"]
        resources: ["jobs", "cronjobs"]
        operations: ["CREATE", "UPDATE"]
  variables:
    # The pod template, wherever the kind keeps it.
    - name: podSpec
      expression: >-
        object.kind == 'Pod' ? object.spec :
        object.kind == 'CronJob' ? object.spec.jobTemplate.spec.template.spec :
        object.spec.template.spec
    # Images of every container kind. Each list is mapped to strings first:
    # Container and EphemeralContainer are distinct types and cannot be
    # concatenated.
    - name: images
      expression: >-
        variables.podSpec.containers.map(c, c.image) +
        (has(variables.podSpec.initContainers) ? variables.podSpec.initContainers.map(c, c.image) : []) +
        (has(variables.podSpec.ephemeralContainers) ? variables.podSpec.ephemeralContainers.map(c, c.image) : [])
  validations:
    {{- range .validations }}
    - expression: {{ .expression | quote }}
      messageExpression: {{ .messageExpression | quote }}
      reason: Forbidden
    {{- end }}
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: {{ $name }}-audit
  labels:
    {{- include "homelab-policies.labels" $ctx | nindent 4 }}
spec:
  policyName: {{ $name }}
  validationActions:
    {{- toYaml $v.auditActions | nindent 4 }}
  matchResources:
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values:
            {{- toYaml $v.excludedNamespaces | nindent 12 }}
        # Absent label included: NotIn matches namespaces without it.
        - key: {{ $v.enforceLabel.key }}
          operator: NotIn
          values: [{{ $v.enforceLabel.value | quote }}]
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: {{ $name }}-enforce
  labels:
    {{- include "homelab-policies.labels" $ctx | nindent 4 }}
spec:
  policyName: {{ $name }}
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        {{ $v.enforceLabel.key }}: {{ $v.enforceLabel.value | quote }}
{{- end -}}

{{- define "homelab-policies.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.Version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}
