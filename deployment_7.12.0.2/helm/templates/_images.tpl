{{/*
Provide the yaml for a given FMS image reference, found in `image_id`
*/}}
{{- define "fms.docker-image" -}}
{{ get ( fromYaml ( include "fms.docker-images" . ) )  .image_id | toYaml  }}
{{- end -}}

{{/*
Provide a yaml map with IDs for all exfo images.
They can be overriden through Values.images
*/}}
{{- define "fms.docker-images" -}}
{{ toYaml ( mustMerge (dict) ( default ( dict ) .Values.images ) ( fromYaml ( include "fms.docker-images-builtin" . ) ) ) }}
{{- end -}}


{{/*
Provide a yaml map with IDs for all exfo images
*/}}
{{- define "fms.docker-images-builtin" -}}
    {{ range $path, $_ :=  $.Files.Glob  "refs/**.yaml" }}
{{ $name := trimSuffix ".yaml" $path }}
{{ $name := mustRegexReplaceAll "^.*/" $name "" }}

{{ $name }}:
{{ $.Files.Get $path | nindent 2}}
    {{ end }}
{{- end -}}


