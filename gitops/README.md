# In-cluster GitOps

OLM Classic `Subscription`s + Kustomize. Install OpenShift GitOps, then Argo CD syncs this directory.

```bash
make cluster.<profile>.kubeconfig
# private API: make cluster.<profile>.sshuttle.connect first
# copy dockerconfigjson to tmp/pull-secret.txt (example pull_secret_path)
make cluster.<profile>.apply   # Key Vault redhat-pull-secret
make cluster.<profile>.bootstrap
```

Guide: [GitOps bootstrap](../docs/guides/gitops.md). Org customizations (group `cluster-admin`, extra apps) go in a [cluster-config repo](../docs/guides/gitops.md#cluster-config-repo), not this tree.
