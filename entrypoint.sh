#!/usr/bin/env bash

set -o errexit
set -o errtrace
set -o pipefail

if [ -z "${AWS_REGION}" ]; then
  AWS_REGION=eu-west-1
fi

if [ -n "${INPUT_NAME}" ]; then
  CLUSTER_NAME=${INPUT_NAME}
else
  NOW=$(date '+%s')
  CLUSTER_NAME=$GITHUB_ACTOR-$NOW
fi

# test if a cluster already exists
if eksctl get cluster $CLUSTER_NAME --region $AWS_REGION &>/dev/null; then
  echo "Existing Fargate cluster $CLUSTER_NAME in $AWS_REGION"
else
  echo "Provisioning EKS on Fargate cluster $CLUSTER_NAME in $AWS_REGION"

  # create EKS on Fargate cluster:
  tmpdir=$(mktemp -d)
  cat <<EOF >> ${tmpdir}/fg-cluster-spec.yaml
  apiVersion: eksctl.io/v1alpha5
  kind: ClusterConfig
  metadata:
    name: $CLUSTER_NAME
    version: "$INPUT_VERSION"
    region: $AWS_REGION
  iam:
    withOIDC: true
  fargateProfiles:
    - name: defaultfp
      selectors:
        - namespace: serverless
        - namespace: kube-system
  cloudWatch:
    clusterLogging:
      enableTypes: ["*"]
EOF

  eksctl create cluster -f ${tmpdir}/fg-cluster-spec.yaml

  # check if cluster if available
  echo "Waiting for cluster $CLUSTER_NAME in $AWS_REGION to become available"
  sleep 10
  cluster_status="UNKNOWN"
  until [ "$cluster_status" == "ACTIVE" ]
  do 
      cluster_status=$(eksctl get cluster $CLUSTER_NAME --region $AWS_REGION -o json | jq -r '.[0].Status')
      sleep 3
  done
fi

# create serverless namespace for Fargate pods, make it the active namespace:
echo "EKS on Fargate cluster $CLUSTER_NAME is ready, configuring it:"
kubectl create namespace serverless || true
kubectl config set-context $(kubectl config current-context) --namespace=serverless

if [ -n "${INPUT_ADD-SYSTEM-MASTERS-ARN}" ]; then
  echo "Configuring role for system:masters"

  eksctl create iamidentitymapping --cluster $CLUSTER_NAME \
  --region=$AWS_REGION \
  --arn ${INPUT_ADD-SYSTEM-MASTERS-ARN} \
  --group system:masters \
  --no-duplicate-arns
fi

