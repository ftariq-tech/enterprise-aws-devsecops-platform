#!/usr/bin/env bash
# Manual GitHub release only. Never invoke against an unauthorized AWS account.
set -euo pipefail
IMAGE="${1:?Usage: release_ecs.sh REGISTRY/REPO:TAG}"
: "${ECS_CLUSTER:?Missing ECS_CLUSTER}"
: "${ECS_API_SERVICE:?Missing ECS_API_SERVICE}"
: "${ECS_WORKER_SERVICE:?Missing ECS_WORKER_SERVICE}"
for svc in "$ECS_API_SERVICE" "$ECS_WORKER_SERVICE"; do
  td_arn="$(aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$svc" --query 'services[0].taskDefinition' --output text)"
  if [[ -z "$td_arn" || "$td_arn" == "None" ]]; then
    echo "Service not provisioned: $svc" >&2; exit 1
  fi
  aws ecs describe-task-definition --task-definition "$td_arn"         | jq --arg image "$IMAGE" '.taskDefinition | del(.taskDefinitionArn,.revision,.status,.requiresAttributes,.compatibilities,.registeredAt,.registeredBy,.deregisteredAt) | .containerDefinitions[0].image=$image'         > task-definition.json
  new_td="$(aws ecs register-task-definition --cli-input-json file://task-definition.json --query 'taskDefinition.taskDefinitionArn' --output text)"
  rm -f task-definition.json
  aws ecs update-service --cluster "$ECS_CLUSTER" --service "$svc" --task-definition "$new_td" >/dev/null
  echo "Updated $svc to $new_td"
done
aws ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$ECS_API_SERVICE" "$ECS_WORKER_SERVICE"
echo "Both ECS services reached steady state. Inspect ALB health and DLQ before claiming success."
