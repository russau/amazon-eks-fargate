#!/usr/bin/env bash

set -o errexit
set -o errtrace
set -o pipefail

if [ "${INPUT_DELETE_CLUSTER,,}" = "true" ]; then
    echo "Deleting EKS on Fargate cluster $CLUSTER_NAME in $AWS_REGION"
    eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION
fi

