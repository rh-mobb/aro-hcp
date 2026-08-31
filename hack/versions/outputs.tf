output "location" {
  value = var.location
}

output "streams" {
  description = "Enabled X.Y cluster streams keyed by channelGroup."
  value       = local.streams
}

output "patches" {
  description = "Enabled X.Y.Z patches keyed by channelGroup."
  value       = local.patches
}
