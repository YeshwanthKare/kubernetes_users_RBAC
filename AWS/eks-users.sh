#!/bin/bash
set -euo pipefail

# === Configuration ===
USER_NAME="kubeconfig-client"
USER_IAM_ARN="arn:aws:iam::891612549689:user/${USER_NAME}"
CLUSTER_NAME="eks-1"
CLUSTER_REGION="eu-central-1"
KUBECONFIG_DIR="./kubeconfigs"
KUBECONFIG_PATH="${KUBECONFIG_DIR}/${USER_NAME}-kubeconfig.yaml"
NAMESPACES=(
  "dev-thematic-service-agri"
  "dev-thematic-service-forest"
  "dev-thematic-service-land"
  "dev-thematic-service-security"
  "dev-thematic-service-water"
)

mkdir -p "$KUBECONFIG_DIR"

# === 1. Add user to aws-auth ConfigMap ===
echo "🔐 Adding $USER_NAME to aws-auth ConfigMap..."

TMP_AUTH=$(mktemp)
kubectl -n kube-system get configmap aws-auth -o yaml > "$TMP_AUTH"

if grep -q "$USER_IAM_ARN" "$TMP_AUTH"; then
  echo "✅ $USER_NAME already exists in aws-auth"
else
  echo "Adding user entry..."
  yq eval ".data.mapUsers += \"- userarn: ${USER_IAM_ARN}\\n  username: ${USER_NAME}\\n  groups:\\n    - system:developers\"" -i "$TMP_AUTH"
  kubectl apply -f "$TMP_AUTH"
  echo "✅ aws-auth updated"
fi
rm "$TMP_AUTH"

# === 2. Create namespaces and RBAC ===
for NS in "${NAMESPACES[@]}"; do
  echo "🔧 Setting up namespace and RBAC for: $NS"

  kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

  # Creating Role for the user in each namespace
  cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${USER_NAME}-access
  namespace: ${NS}
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "create", "update", "delete", "patch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "create", "update", "delete", "patch"]
EOF

  # Creating RoleBinding to bind the user to the Role
  cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${USER_NAME}-access-binding
  namespace: ${NS}
subjects:
- kind: User
  name: ${USER_NAME}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${USER_NAME}-access
  apiGroup: rbac.authorization.k8s.io
EOF
done

# === 3. Create kubeconfig file with correct exec plugin config ===
echo "⚙️  Generating kubeconfig for ${USER_NAME}..."

# Step 1: Get cluster data
CLUSTER_ENDPOINT=$(aws eks describe-cluster --region "$CLUSTER_REGION" --name "$CLUSTER_NAME" --query "cluster.endpoint" --output text)
CLUSTER_CA=$(aws eks describe-cluster --region "$CLUSTER_REGION" --name "$CLUSTER_NAME" --query "cluster.certificateAuthority.data" --output text)

# Step 2: Build kubeconfig manually
kubectl config --kubeconfig="$KUBECONFIG_PATH" set-cluster "$CLUSTER_NAME" \
  --server="$CLUSTER_ENDPOINT" \
  --certificate-authority=<(echo "$CLUSTER_CA" | base64 -d) \
  --embed-certs=true

kubectl config --kubeconfig="$KUBECONFIG_PATH" set-credentials "$USER_NAME" \
  --exec-command aws \
  --exec-arg "eks" \
  --exec-arg "get-token" \
  --exec-arg "--region" \
  --exec-arg "$CLUSTER_REGION" \
  --exec-arg "--cluster-name" \
  --exec-arg "$CLUSTER_NAME" \
  --exec-arg "--profile" \
  --exec-arg "$USER_NAME"

# Step 3: Patch in required fields for exec plugin
echo "🛠️  Patching kubeconfig with exec plugin fields..."
yq eval '
  (.users[] | select(.name == "'"$USER_NAME"'") | .user.exec.apiVersion) = "client.authentication.k8s.io/v1beta1" |
  (.users[] | select(.name == "'"$USER_NAME"'") | .user.exec.interactiveMode) = "IfAvailable"
' -i "$KUBECONFIG_PATH"

# Step 4: Set default context
CONTEXT_NAME="${USER_NAME}-${NAMESPACES[0]}"
kubectl config --kubeconfig="$KUBECONFIG_PATH" set-context "$CONTEXT_NAME" \
  --cluster "$CLUSTER_NAME" \
  --user "$USER_NAME" \
  --namespace "${NAMESPACES[0]}"
kubectl config --kubeconfig="$KUBECONFIG_PATH" use-context "$CONTEXT_NAME"

echo "✅ Done. Kubeconfig created at: $KUBECONFIG_PATH"
