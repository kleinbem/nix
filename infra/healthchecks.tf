# External dead-man's switch (healthchecks.io): local alerting runs inside the
# fleet, so these alert from outside it. Checks come from each host's
# my.heartbeat.checks (heartbeats.json via tools/gen-iac-data.sh); hosts ping
# https://hc-ping.com/<ping key>/<slug>, the slug derived from the check name.
# Bootstrap: create account + project, put the API key in infra/terraform.yaml
# (healthchecks_api_key), the ping key in nix/shared.yaml (healthchecks_ping_key).

variable "healthchecks_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "healthchecks.io project read-write API key (sops: infra/terraform.yaml healthchecks_api_key). Empty → no checks are managed."
}

variable "healthchecks_channel_kinds" {
  type        = list(string)
  default     = ["email"]
  description = "Integration kinds (one per kind, set up once in the healthchecks.io UI) every check notifies. A new account starts with an email integration; add e.g. \"ntfy\" (public ntfy.sh — never ntfy.kleinbem.dev, it lives on core-pi) or \"telegram\" here after creating it."
}

provider "healthchecksio" {
  api_key = var.healthchecks_api_key
}

locals {
  heartbeats = jsondecode(file("${path.module}/heartbeats.json"))

  # host → { slug → spec }  ⇒  slug → spec + host. Empty until the API key
  # exists. nonsensitive() only unwraps the "is a key set" boolean.
  heartbeat_checks = nonsensitive(var.healthchecks_api_key == "") ? {} : merge([
    for host, checks in local.heartbeats : {
      for slug, c in checks : slug => merge(c, { host = host })
    }
  ]...)
}

data "healthchecksio_channel" "notify" {
  for_each = nonsensitive(var.healthchecks_api_key == "") ? toset([]) : toset(var.healthchecks_channel_kinds)
  kind     = each.value
}

resource "healthchecksio_check" "fleet" {
  for_each = local.heartbeat_checks

  name     = each.key
  desc     = "${each.value.kind} heartbeat from ${each.value.host} — managed by nix/infra/healthchecks.tf"
  tags     = ["kleinbem", each.value.host, each.value.kind]
  timeout  = each.value.timeout
  grace    = each.value.grace
  channels = [for c in data.healthchecksio_channel.notify : c.id]
}
