# 🔐 Kubernetes Kubeconfig Generator for Namespaced User Access

This repository provides an automated script to **generate Kubernetes `kubeconfig` files** for multiple users, each restricted to specific **namespaces** using Kubernetes **RBAC** and **client certificate authentication**.

---

## 📌 Table of Contents

- [📖 Introduction](#-introduction)
- [✨ Features](#-features)
- [⚙️ Requirements](#️-requirements)
- [🚀 Usage](#-usage)
- [🧩 Script Breakdown](#-script-breakdown)
- [📁 Kubeconfig Output](#-kubeconfig-output)
- [❗ Important Notes](#-important-notes)
- [📤 Undo Script](#-undo-script)
- [📚 License](#-license)

---

## 📖 Introduction

This tool is designed for Kubernetes administrators who need to:

- **Provision secure access** for users across multiple Kubernetes namespaces.
- Use **certificate-based authentication** (non-AWS).
- Enforce access using **Kubernetes-native RBAC**.
- Automate the generation of valid, ready-to-use `kubeconfig` files for clients.

Each user will receive:
- A unique private key and client certificate.
- RBAC role and binding in the target namespaces.
- A kubeconfig scoped to those namespaces.

---

## ✨ Features

✅ Create users with:
- Auto-generated RSA private key and CSR
- CSR approval and client certificate extraction  
- Namespaced Role + RoleBinding

✅ Generates a kubeconfig file with:
- Multiple contexts (1 per namespace)
- Default context set to the first namespace

✅ Works with:
- Client certificate authentication
- Any standard Kubernetes cluster (not specific to AWS or EKS)

---

## ⚙️ Requirements

Make sure the following are installed and available in your environment:

- `bash`
- `kubectl` (configured to access the target cluster)
- `openssl`
- `jq`
- `base64`
- `envsubst` (part of `gettext`)
- Kubernetes access with admin permissions

---

## 🚀 Usage

1. **Clone the repo** and modify variables:
   ```bash
   USERS=("dave" "alice")
   NAMESPACES=("namespace1" "namespace2" ...)
   CLUSTER_NAME="default"


2. Run the script:

   ```
   chmod +x eks-users.sh
   ./eks-users.sh
   ```