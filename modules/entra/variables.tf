variable "cluster_name" {
  description = "ARO HCP cluster name. Used for the Entra app display name."
  type        = string
}

variable "cluster_id" {
  description = "Azure resource ID of the HCP cluster (parent of externalAuths)."
  type        = string
}

variable "console_url" {
  description = "OpenShift console URL from the HCP cluster (properties.console.url)."
  type        = string
}

variable "dns_base_domain" {
  description = "HCP-assigned DNS base domain (properties.dns.baseDomain), e.g. 3lzd.uksouth.aroapp-hcp.io."
  type        = string
}

variable "dns_base_domain_prefix" {
  description = "DNS prefix (properties.dns.baseDomainPrefix), usually the cluster name."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant ID for the OIDC issuer URL."
  type        = string
}

variable "key_vault_id" {
  description = "Customer Key Vault ID. Stores the confidential client secret for kube/GitOps."
  type        = string
}

variable "external_auth_name" {
  description = "Name of the HCP externalAuths child resource."
  type        = string
  default     = "entra"
}

variable "app_display_name" {
  description = "Entra app registration display name. Defaults to <cluster_name>-auth."
  type        = string
  default     = null
  nullable    = true
}

variable "oidc_web_redirects" {
  description = <<-EOT
    Extra Web redirect URIs beyond console, GitOps, and http://localhost:8000.
    Each value is host (first label(s) of the apps route) plus path.
    Console, GitOps, and PKCE (public-client http://localhost) are always registered.
    Override with {} to register none of these extras, or a subset (e.g. only gitops is N/A — GitOps is always-on).
    Default includes RHOAI's data-science gateway when GitOps pins subdomain rh-ai.
  EOT
  type = map(object({
    host = string
    path = string
  }))
  default = {
    rhoai = {
      host = "rh-ai"
      path = "/oauth2/callback"
    }
  }

  validation {
    condition = alltrue([
      for spec in values(var.oidc_web_redirects) :
      length(spec.host) > 0 && startswith(spec.path, "/")
    ])
    error_message = "Each oidc_web_redirects entry must have a non-empty host and a path starting with /."
  }
}

variable "client_secret_key_vault_secret_name" {
  description = "Key Vault secret name for the Entra confidential client secret."
  type        = string
  default     = "entra-console-client-secret"

  validation {
    condition     = can(regex("^[0-9a-zA-Z-]{1,127}$", var.client_secret_key_vault_secret_name))
    error_message = "client_secret_key_vault_secret_name must be 1-127 alphanumeric characters or hyphens."
  }
}

variable "hcp_api_version" {
  description = "ARO HCP ARM API version for externalAuths."
  type        = string
  default     = "2026-06-30-preview"
}
