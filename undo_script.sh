#!/bin/bash
set -euo pipefail

# === Configuration ===
USERS=("kubeconfig-client")
NAMESPACES=(
  "dev-thematic-service-agri"
  "dev-thematic-service-forest"
  "dev-thematic-service-land"
  "dev-thematic-service-security"
  "dev-thematic-service-water"
)
KUBECONFIG_DIR="./kubeconfigs"

echo "🔁 Deleting CertificateSigningRequests..."
for user in "${USERS[@]}"; do
  kubectl delete csr "${user}-csr" --ignore-not-found
done

echo "🧽 Cleaning up Roles and RoleBindings in namespaces..."
for user in "${USERS[@]}"; do
  for ns in "${NAMESPACES[@]}"; do
    kubectl delete role "${user}-access" -n "$ns" --ignore-not-found
    kubectl delete rolebinding "${user}-access-binding" -n "$ns" --ignore-not-found
  done
done

# Uncomment below if you want to delete the namespaces too (DANGEROUS: all resources will be deleted!)
# echo "⚠️ Deleting namespaces..."
# for ns in "${NAMESPACES[@]}"; do
#   kubectl delete namespace "$ns" --ignore-not-found
# done

echo "🗑️ Deleting local certs, keys, CSRs, configs..."
rm -f ./*.key ./*.crt ./*.csr ./*.cnf

echo "🗃️ Deleting kubeconfig directory..."
rm -rf "$KUBECONFIG_DIR"

echo "✅ Cleanup complete."
