#!/bin/bash
set -euo pipefail

USER_NAME="kubeconfig-client"
USER_IAM_ARN="arn:aws:iam::891612549689:user/${USER_NAME}"
NAMESPACES=(
  "dev-thematic-service-agri"
  "dev-thematic-service-forest"
  "dev-thematic-service-land"
  "dev-thematic-service-security"
  "dev-thematic-service-water"
)
KUBECONFIG_PATH="./kubeconfigs/${USER_NAME}-kubeconfig.yaml"

echo "🔁 Undoing user setup..."

TMP_AUTH=$(mktemp)
kubectl -n kube-system get configmap aws-auth -o yaml > "$TMP_AUTH"

# Remove from aws-auth
yq eval '
  .data.mapUsers |= (
    split("\n") 
    | map(select(. != "")) 
    | map(select(. | test("'"$USER_IAM_ARN"'") | not)) 
    | join("\n")
  )
' -i "$TMP_AUTH"
kubectl apply -f "$TMP_AUTH"
rm "$TMP_AUTH"

# Remove RBAC
for NS in "${NAMESPACES[@]}"; do
  kubectl delete role "${USER_NAME}-access" -n "$NS" --ignore-not-found
  kubectl delete rolebinding "${USER_NAME}-access-binding" -n "$NS" --ignore-not-found
done

# Remove kubeconfig
rm -f "$KUBECONFIG_PATH"
echo "✅ Cleanup completed."
