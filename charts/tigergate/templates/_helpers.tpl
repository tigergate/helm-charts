{{- define "tigergate.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "tigergate.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "tigergate.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "tigergate.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: tigergate
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "tigergate.serviceAccountName" -}}
{{ include "tigergate.fullname" . }}
{{- end -}}

{{- define "tigergate.image" -}}
{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end -}}

{{- define "tigergate.sensorImage" -}}
{{ .Values.sensor.image.repository }}:{{ .Values.sensor.image.tag }}
{{- end -}}

{{/*
tigergate.sensorIngestAddr: where the sensor ships runtime EVENTS. Defaults
to the platform's public ingest address (same value the operator itself
uses, backend.ingestGrpcAddr) — the sensor talks to the platform directly.
sensor.ingestGrpcAddr overrides this if you'd rather route events through
the operator relay instead.
*/}}
{{- define "tigergate.sensorIngestAddr" -}}
{{- if .Values.sensor.ingestGrpcAddr -}}
{{ .Values.sensor.ingestGrpcAddr }}
{{- else -}}
{{ .Values.backend.ingestGrpcAddr }}
{{- end -}}
{{- end -}}

{{/*
tigergate.sensorOperatorAddr: this cluster's KSPM operator relay Service —
the sensor's POLICY sync transport when TIGEREYE_OPERATOR_ADDR is set
(tigereye/pkg/tigereye/control.go's beatViaOperator, served by
tigergate-operator's GetPolicy RPC, workers/kspm/internal/relay/policy.go).
*/}}
{{- define "tigergate.sensorOperatorAddr" -}}
{{ include "tigergate.fullname" . }}-operator-relay.{{ .Release.Namespace }}.svc.cluster.local:{{ .Values.relay.port }}
{{- end -}}

{{- define "tigergate.backendSecretName" -}}
{{ include "tigergate.fullname" . }}-backend
{{- end -}}

{{- define "tigergate.remediatorServiceAccountName" -}}
{{ include "tigergate.fullname" . }}-remediator
{{- end -}}

{{- define "tigergate.secretRef" -}}
{{ .Values.backend.existingSecret | default (include "tigergate.backendSecretName" .) }}
{{- end -}}

{{- define "tigergate.imagePullSecrets" -}}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
