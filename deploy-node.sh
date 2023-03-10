#!/bin/bash

if [ "$1" = "" ]
then
  echo "Usage: $0 <node name>"
  exit
fi

set -o pipefail

NAMESPACE=$1
NODE_NAME=$1

# download node config from gcp bucket
gcloud storage cp gs://charon-nodes-config/${NODE_NAME}/${NODE_NAME}.env .

# override the env vars
OLDIFS=$IFS
IFS='
'
export $(< ./${NODE_NAME}.env)
IFS=$OLDIFS

# delete node env vars file
rm ./${NODE_NAME}.env

# create the namespace
nsStatus=`kubectl get namespace ${NAMESPACE} --no-headers --output=go-template={{.metadata.name}} 2>/dev/null`
if [ -z "$nsStatus" ]; then
    echo "Namespace (${NAMESPACE}) not found, creating a new one."
    kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
fi

# download node config
mkdir -p ./.charon/
gcloud storage cp -r gs://charon-nodes-config/${NODE_NAME} ./.charon/

# set current namespace
kubectl config set-context --current --namespace=${NAMESPACE}

# create validators keys k8s secrets
files=""
for secret in ./.charon/${NODE_NAME}/validator_keys/*; do
    files="$files --from-file=./.charon/${NODE_NAME}/validator_keys/$(basename $secret)"
done
kubectl -n $NAMESPACE create secret generic validator-keys $files --dry-run=client -o yaml | kubectl apply -f -
kubectl -n $NAMESPACE create secret generic private-key --from-file=private-key=./.charon/${NODE_NAME}/charon-enr-private-key --dry-run=client -o yaml | kubectl apply -f -
kubectl -n $NAMESPACE create secret generic cluster-lock --from-file=cluster-lock.json=./.charon/${NODE_NAME}/cluster-lock.json --dry-run=client -o yaml | kubectl apply -f -

# deploy charon node
eval "cat <<EOF
$(<./templates/charon.yaml)
EOF
" | kubectl apply -f -

# deploy teku vc
eval "cat <<EOF
$(<./templates/teku.yaml)
EOF
" | kubectl apply -f -

# deploy prometheus agent
eval "cat <<EOF
$(<./templates/prometheus.yaml)
EOF
" | kubectl apply -f -

# delete node config before exit
rm -rf ./.charon/${NODE_NAME}
