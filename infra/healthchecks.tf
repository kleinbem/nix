# ---------------------------------------------------------------------------
# External dead-man's switch (healthchecks.io). Local alerting (ntfy, gatus,
# the backup freshness watchdog) all runs on core-pi or on the watched host
# itself — a dead core-pi goes silent. These checks alert from OUTSIDE the
# fleet when a host stops pinging.
#
# Data bridge: infra/heartbeats.json is generated from nix-config
# (flake output `heartbeats` ← each host's `my.heartbeat.checks`, see
# nix-config/modules/nixos/heartbeat.nix) by tools/gen-iac-data.sh, which
# tf-apply.sh runs first. One check per slug; the API (v1, which this
# provider uses) derives the check's slug from its name, and hosts ping
# https://hc-ping.com/<project ping key>/<slug>.
#
# Manual bootstrap (first credential only): healthchecks.io account + project,
# a read-write API key → `healthchecks_api_key` in kleinbem-secrets
# infra/terraform.yaml, the project's ping key → `healthchecks_ping_key` in
# nix/shared.yaml, and the notification integrations named in
# `healthchecks_channel_kinds` (email exists by default; never route through
# ntfy.kleinbem.dev, which lives on core-pi).
# ---------------------------------------------------------------------------

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
  # exists, so an apply before the bootstrap doesn't try to call the API.
  # nonsensitive() on the *boolean* only ("is a key configured") — the key
  # itself never reaches for_each.
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
