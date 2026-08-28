variable "location" {
  description = "Azure region to list HCP OpenShift versions for."
  type        = string
  default     = "uksouth"
}

variable "api_version" {
  description = "ARO HCP ARM API version."
  type        = string
  default     = "2026-06-30-preview"
}
