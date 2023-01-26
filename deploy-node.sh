#!/bin/bash

set -o pipefail

if [ "$1" = "" ]
then
  echo "Usage: $0 <please enter your cluster name>"
  exit
fi

NAME_SPACE=$1

# override the env vars
OLDIFS=$IFS
IFS='
'
export $(< ./.env)
IFS=$OLDIFS

# create the namespace
nsStatus=`kubectl get namespace ${NAME_SPACE} --no-headers --output=go-template={{.metadata.name}} 2>/dev/null`
if [ -z "$nsStatus" ]; then
    echo "Cluster (${NAME_SPACE}) not found, creating a new one."
    kubectl create namespace ${NAME_SPACE} --dry-run=client -o yaml | kubectl apply -f -
fi

# set current namespace
kubectl config set-context --current --namespace=${NAME_SPACE}

# create validators keys k8s secrets
files=""
for secret in ./.charon/validator_keys/*; do
    files="$files --from-file=./.charon/validator_keys/$(basename $secret)"
done
kubectl -n $NAME_SPACE create secret generic validator-keys $files --dry-run=client -o yaml | kubectl apply -f -
kubectl -n $NAME_SPACE create secret generic charon-enr-private-key --from-file=charon-enr-private-key=./.charon/charon-enr-private-key --dry-run=client -o yaml | kubectl apply -f -
kubectl -n $NAME_SPACE create secret generic cluster-lock --from-file=cluster-lock.json=./.charon/cluster-lock.json --dry-run=client -o yaml | kubectl apply -f -

export NAME_SPACE=$NAME_SPACE
export CHARON_VERSION=$CHARON_VERSION
export TEKU_VERSION=$TEKU_VERSION
export BEACON_NODE_ENDPOINTS=$BEACON_NODE_ENDPOINTS
export MONITORING_TOKEN=$MONITORING_TOKEN

# deploy charon node
eval "cat <<EOF
$(<./manifests/charon.yaml)
EOF
" | kubectl apply -f -

# deploy teku vc
eval "cat <<EOF
$(<./manifests/teku.yaml)
EOF
" | kubectl apply -f -

# deploy prometheus agent
eval "cat <<EOF
$(<./manifests/prometheus.yaml)
EOF
" | kubectl apply -f -
