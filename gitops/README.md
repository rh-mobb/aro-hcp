# In-cluster GitOps

OLM Classic `Subscription`s + Kustomize. Install OpenShift GitOps, then Argo CD syncs this directory.

```bash
make cluster.<profile>.kubeconfig
# private API: make cluster.<profile>.sshuttle.connect first
# PULL_SECRET_PATH=~/pull-secret.txt make cluster.<profile>.apply   # once: Key Vault
make cluster.<profile>.bootstrap
```

Guide: [GitOps bootstrap](../docs/guides/gitops.md).
