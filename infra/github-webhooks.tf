# Revue PR review webhooks across kleinbem and kleinbem-dev. Lives here rather
# than in github-config because github_repository_webhook stores its HMAC secret
# in the plan and state, and github-config's tfplan is a public artifact.

locals {
  revue_webhooks_enabled = nonsensitive(var.revue_webhook_secret != "")
  revue_webhook_url      = "https://revue.kleinbem.dev/webhook"
  revue_webhook_events = [
    "issue_comment",
    "pull_request",
    "pull_request_review_comment",
  ]

  # Every owned kleinbem repo except kleinbem-secrets (private vault with
  # unencrypted initrd material; keep its diffs off external LLM providers).
  revue_repos = toset([
    "actions",
    "android-config",
    "aur-packages",
    "chrome-open-in-app",
    "coderabbit",
    "github-config",
    "hf-bench",
    "jj-toolbox",
    "kleinbem",
    "kleinbem-site",
    "mesh-llm-ci",
    "mesh-llm-gpu",
    "nix",
    "nix-config",
    "nix-detour-fleet",
    "nix-devshells",
    "nix-hardware",
    "nix-omarchy",
    "nix-packages",
    "nix-presets",
    "nix-templates",
    "nix-toolbox",
    "openwrt",
    "openwrt-builder",
    "openwrt-config",
    "skills",
    "web-config",
  ])

  revue_org_repos = toset([
    ".github",
    "attic-ui",
    "cadre",
    "coderabbit",
    "foyer",
    "nix-detour",
    "nix-gantry",
    "revue",
  ])
}

resource "github_repository_webhook" "revue" {
  for_each = local.revue_webhooks_enabled ? local.revue_repos : toset([])

  repository = each.key
  active     = true
  events     = local.revue_webhook_events

  configuration {
    url          = local.revue_webhook_url
    content_type = "json"
    insecure_ssl = false
    secret       = var.revue_webhook_secret
  }
}

resource "github_repository_webhook" "org_revue" {
  for_each = local.revue_webhooks_enabled ? local.revue_org_repos : toset([])
  provider = github.org

  repository = each.key
  active     = true
  events     = local.revue_webhook_events

  configuration {
    url          = local.revue_webhook_url
    content_type = "json"
    insecure_ssl = false
    secret       = var.revue_webhook_secret
  }
}
