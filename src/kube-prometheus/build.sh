#!/usr/bin/env bash

# This script uses arg $1 (name of *.jsonnet file to use) to generate the manifests/*.yaml files.
set -euo pipefail
set -x

rm -rf manifests
mkdir manifests

# go jsonnet does not support fmt
# jsonnet fmt -i *.jsonnet

CLUSTER=$1
jsonnet -J vendor -m manifests "cluster-$CLUSTER.jsonnet" | xargs -I{} sh -c 'cat {} | gojsontoyaml > {}.yaml; rm -f {}' -- {}
rm -rf "../../clusters/$CLUSTER/monitoring/kube-prometheus"
mv manifests "../../clusters/$CLUSTER/monitoring/kube-prometheus"

