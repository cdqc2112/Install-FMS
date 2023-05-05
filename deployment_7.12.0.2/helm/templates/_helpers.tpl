{{/*
Expand the name of the chart.
*/}}
{{- define "fms.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "fms.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "fms.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "fms.labels" -}}
helm.sh/chart: {{ include "fms.chart" . }}
{{ include "fms.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "fms.selectorLabels" -}}
app.kubernetes.io/name: {{ include "fms.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "fms.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "fms.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{- define "fms.volumeclaim.data" -}}
spec:
  accessModes: [ "ReadWriteOnce" ]
{{- if .Values.useHostForStorage }}
  storageClassName: manual
  selector:
    matchLabels:
      {{- include "fms.labels" . | nindent 6 }}
      type: local
      name: data-{{ include "fms.fullname" . }}-{{.id}}-0
  resources:
    requests:
      {{/* Is the value used ? */}}
      storage: 10G
{{- else }}
  storageClassName: {{ default "default" .Values.storageClassName }}
  resources:
    requests:
      storage: 10G
{{- end }}
{{- end }}

{{/*
    Satisfy volume claim automatically when using host storage
    Expect:
      Values
      id - unique id for the volume
      path
*/}}
{{- define "fms.volume.data" -}}
{{- if .Values.useHostForStorage }}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-{{ include "fms.fullname" . }}-{{.id}}-0
  labels:
    {{- include "fms.labels" . | nindent 4 }}
    type: local
    name: data-{{ include "fms.fullname" . }}-{{.id}}-0
spec:
  storageClassName: manual
  persistentVolumeReclaimPolicy: Delete
  capacity:
    storage: "10G"
  accessModes: [ "ReadWriteOnce" ]
  hostPath:
    path: "{{.Values.env.ROOT_PATH}}{{.Values.env.PERSISTENT_DATA_DIR}}{{.path}}"
    type: "Directory"
{{- end }}
{{- end }}

{{- define "fms.volume.root" -}}
{{- if .Values.useHostForStorage }}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-{{ include "fms.fullname" . }}-{{.id}}-0
  labels:
    {{- include "fms.labels" . | nindent 4 }}
    type: local
    name: data-{{ include "fms.fullname" . }}-{{.id}}-0
spec:
  storageClassName: manual
  persistentVolumeReclaimPolicy: Delete
  capacity:
    storage: "10G"
  accessModes: [ "ReadWriteOnce" ]
  hostPath:
    path: "{{.Values.env.ROOT_PATH}}"
    type: "Directory"
{{- end }}
{{- end }}



{{/*
    Satisfy volume claim automatically when using host storage
    Expect:
      Values
      id - unique id for the volume
      path
*/}}
{{- define "fms.volume.replication-data" -}}
{{- if .Values.useHostForStorage }}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-{{ include "fms.fullname" . }}-{{.id}}-0
  labels:
    {{- include "fms.labels" . | nindent 4 }}
    type: local
    name: data-{{ include "fms.fullname" . }}-{{.id}}-0
spec:
  storageClassName: manual
  persistentVolumeReclaimPolicy: Delete
  capacity:
    storage: "10G"
  accessModes: [ "ReadWriteOnce" ]
  hostPath:
    path: "{{.Values.env.REPLICATION_ROOT_PATH}}{{.Values.env.REPLICATION_DATA_DIR}}{{.Values.env.PERSISTENT_DATA_DIR}}{{.path}}"
    type: "Directory"
{{- end }}
{{- end }}

{{/*
    Satisfy volume claim automatically when using host storage for replication
    Expect:
      Values
      id - unique id for the volume
*/}}
{{- define "fms.volume.replication-data-root" -}}
{{- if .Values.useHostForStorage }}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-{{ include "fms.fullname" . }}-{{.id}}-0
  labels:
    {{- include "fms.labels" . | nindent 4 }}
    type: local
    name: data-{{ include "fms.fullname" . }}-{{.id}}-0
spec:
  storageClassName: manual
  persistentVolumeReclaimPolicy: Delete
  capacity:
    storage: "10G"
  accessModes: [ "ReadWriteOnce" ]
  hostPath:
    path: "{{.Values.env.REPLICATION_ROOT_PATH}}{{.Values.env.REPLICATION_DATA_DIR}}"
    type: "Directory"
{{- end }}
{{- end }}



{{/*
    Log volume at pod level
    They must be declared in the volume section of container spec
    FIXME: Log is not supported when useHostForStorage is not true.
    The name property must be set by caller
*/}}
{{- define "fms.pod-volume.log" -}}
{{- if .Values.useHostForStorage }}
hostPath:
{{- if not .replica }}
  path: "{{.Values.env.ROOT_PATH}}{{.Values.env.LOG_DIR}}{{.path}}"
{{- else }}
  path: "{{.Values.env.MASTER_ROOT_PATH}}{{.Values.env.LOG_DIR}}{{.path}}"
{{- end }}
  type: "Directory"
{{- else }}
emptyDir: {}
{{- end }}
{{- end }}


{{/*
    Config volume at pod level
    They must be declared in the volume section of container spec
    They will refer either to the host path or to a config map (or empty dir if not set)
    The name property must be set by caller
*/}}
{{- define "fms.pod-volume.config" -}}
{{-   if .Values.useHostForStorage }}
hostPath:
  path: {{.Values.env.ROOT_PATH}}{{.Values.env.CONFIG}}{{(index .Values.env .id)}}
  type: Directory
{{-   else}}
{{-     if (index .Values.configmaps .id) }}
configMap:
  name: {{ (index .Values.configmaps .id) }}
{{-     else }}
emptyDir: {}
{{-     end}}
{{-   end}}
{{- end }}


