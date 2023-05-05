#!/bin/bash

set -euo pipefail

KUSTOMIZE_PATH="$(dirname "${BASH_SOURCE[0]}" )"

# save incoming YAML to file
cat <&0 > "${KUSTOMIZE_PATH}"/all.yaml

# modify the YAML with kustomize
kubectl kustomize "${KUSTOMIZE_PATH}"

