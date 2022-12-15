#!/bin/bash

set -uo pipefail

if [ "$1" = "" ]
then
  echo "Usage: $0 <please enter your cluster name>"
  exit
fi

CLUSTER_NAME=$1

# override the env vars
OLDIFS=$IFS
IFS='
'
export $(< ./.env)
IFS=$OLDIFS

# create the namespace
nsStatus=`kubectl get namespace ${CLUSTER_NAME} --no-headers --output=go-template={{.metadata.name}} 2>/dev/null`
if [ -z "$nsStatus" ]; then
    echo "Cluster (${CLUSTER_NAME}) not found, creating a new one."
    kubectl create namespace ${CLUSTER_NAME} --dry-run=client -o yaml | kubectl apply -f -
fi

# set current namespace
kubectl config set-context --current --namespace=${CLUSTER_NAME}

# create validators keys secrets
files=""
for secret in ./.charon/validator_keys/*; do
    files="$files --from-file=./.charon/validator_keys/$(basename $secret)"
done
kubectl -n $CLUSTER_NAME create secret generic validator-keys $files
kubectl -n $CLUSTER_NAME create secret generic charon-enr-private-key --from-file=charon-enr-private-key=./.charon/charon-enr-private-key
kubectl -n $CLUSTER_NAME create secret generic cluster-lock --from-file=cluster-lock.json=./.charon/cluster-lock.json

export CLUSTER_NAME=$CLUSTER_NAME
export CHARON_VERSION=$CHARON_VERSION
export TEKU_VERSION=$TEKU_VERSION
export BEACON_NODE_ENDPOINTS=$BEACON_NODE_ENDPOINTS
export MONITORING_TOKEN=$MONITORING_TOKEN

# deploy charon node manifests
eval "cat <<EOF
$(<./manifests/charon.yaml)
EOF
" | kubectl apply -f -

eval "cat <<EOF
$(<./manifests/teku.yaml)
EOF
" | kubectl apply -f -

eval "cat <<EOF
$(<./manifests/prometheus.yaml)
EOF
" | kubectl apply -f -

eval "cat <<EOF
$(<./manifests/grafana.yaml)
EOF
" | kubectl apply -f -
