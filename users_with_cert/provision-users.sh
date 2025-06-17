#!/bin/bash
set -e

# === Configuration ===
USERS=("dave" "alice")  # Add more users here
NAMESPACES=(
  "dev-thematic-service-agri"
  "dev-thematic-service-forest"
  "dev-thematic-service-land"
  "dev-thematic-service-security"
  "dev-thematic-service-water"
)
CLUSTER_NAME="default"
KUBECONFIG_DIR="./kubeconfigs"
TEMPLATE_CSR="./csr.cnf.template"
TEMPLATE_KUBECONFIG="./kubeconfig-template.yaml"

mkdir -p "$KUBECONFIG_DIR"

# === Cluster Info ===
CLUSTER_CA=$(kubectl config view --raw -o json | jq -r ".clusters[] | select(.name == \"$CLUSTER_NAME\") | .cluster.\"certificate-authority-data\"")
CLUSTER_ENDPOINT=$(kubectl config view --raw -o json | jq -r ".clusters[] | select(.name == \"$CLUSTER_NAME\") | .cluster.server")

for USER in "${USERS[@]}"; do
  echo "Processing user: $USER"

  # 1. Generate private key
  openssl genpkey -algorithm RSA -out "${USER}.key" -pkeyopt rsa_keygen_bits:4096

  # 2. Generate CSR config and CSR
  USERNAME=$USER envsubst < "$TEMPLATE_CSR" > "${USER}.cnf"
  openssl req -new -key "${USER}.key" -out "${USER}.csr" -config "${USER}.cnf"

  # 3. Base64 CSR and create CSR YAML
  CSR_BASE64=$(base64 -w 0 < "${USER}.csr")
  cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USER}-csr
spec:
  signerName: kubernetes.io/kube-apiserver-client
  groups:
  - system:authenticated
  request: ${CSR_BASE64}
  usages:
  - client auth
EOF

  # 4. Approve CSR and extract cert
  kubectl certificate approve "${USER}-csr"
  sleep 2  # Wait for CSR to be issued

  kubectl get csr "${USER}-csr" -o jsonpath='{.status.certificate}' | base64 --decode > "${USER}.crt"

  # 5. Base64 encode cert and key for kubeconfig
  CLIENT_CERTIFICATE_DATA=$(base64 -w 0 "${USER}.crt")
  CLIENT_KEY_DATA=$(base64 -w 0 "${USER}.key")

  # 6. Prepare kubeconfig file with multiple contexts
  KUBECONFIG_FILE="${KUBECONFIG_DIR}/${USER}-kubeconfig.yaml"
  echo "apiVersion: v1
kind: Config
clusters:
- name: ${CLUSTER_NAME}
  cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${CLUSTER_ENDPOINT}
users:
- name: ${USER}
  user:
    client-certificate-data: ${CLIENT_CERTIFICATE_DATA}
    client-key-data: ${CLIENT_KEY_DATA}
contexts:" > "$KUBECONFIG_FILE"

  for NS in "${NAMESPACES[@]}"; do
    echo "Creating namespace, Role, RoleBinding: $NS"
    kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

    # Create Role
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${USER}-access
  namespace: ${NS}
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets", "deployments", "replicasets", "namespaces", "endpoints"]
  verbs: ["get", "list", "create", "update", "delete", "patch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "replicasets"]
  verbs: ["get", "list", "create", "update", "delete", "patch"]
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "create", "update", "delete", "patch"]
- apiGroups: ["extensions"]
  resources: ["daemonsets"]
  verbs: ["get", "list", "create", "update", "delete", "patch"]
EOF

    # Create RoleBinding
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${USER}-access-binding
  namespace: ${NS}
subjects:
- kind: User
  name: ${USER}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${USER}-access
  apiGroup: rbac.authorization.k8s.io
EOF

    # Append context to kubeconfig
    CONTEXT_NAME="${USER}-${NS}"
    echo "- name: ${CONTEXT_NAME}
  context:
    cluster: ${CLUSTER_NAME}
    user: ${USER}
    namespace: ${NS}" >> "$KUBECONFIG_FILE"
  done

  # Set default context
  echo "current-context: ${USER}-${NAMESPACES[0]}" >> "$KUBECONFIG_FILE"

  echo "✅ Generated kubeconfig: $KUBECONFIG_FILE"
  echo "--------------------------------------------"
done
