# ---------------------------------------------------------------------------
# Actions-secret distribution for the nix CI repos. This is the ONLY GitHub
# resource managed from the nix workspace — the values come from sops (exported
# as TF_VAR_* by scripts/tf-apply.sh), which is why it lives here rather than in
# the github-config repo. Secrets are write-only (no drift detection needed).
#
# All repo *settings/rulesets/labels* are owned by the github-config repo.
#
# Auth strategy: workflows that need to write back to GitHub (PRs, Contents
# API pushes, auto-merge) mint a short-lived installation token via
# actions/create-github-app-token using APP_ID + APP_PRIVATE_KEY. The long-lived
# GH_PAT has been retired — see git history if you need to resurrect it.
# ---------------------------------------------------------------------------

locals {
  # repo -> secrets it receives.
  ci_secrets = {
    # NETBIRD_SETUP_KEY: build-all workflows need the tunnel for the heavy
    # closure NARs (>100 MiB) that would otherwise 413 via Cloudflare.
    "nix"          = ["ATTIC_PUSH_TOKEN", "NETBIRD_SETUP_KEY"]
    "nix-config"   = ["ATTIC_PUSH_TOKEN", "APP_ID", "APP_PRIVATE_KEY", "NETBIRD_SETUP_KEY"]
    "nix-packages" = ["ATTIC_PUSH_TOKEN", "APP_ID", "APP_PRIVATE_KEY"]
    # APP_ID + APP_PRIVATE_KEY needed by each sub-flake's maintain.yaml
    # workflow (auto-updates flake.lock + commits via Contents API).
    "nix-devshells" = ["APP_ID", "APP_PRIVATE_KEY"]
    "nix-hardware"  = ["APP_ID", "APP_PRIVATE_KEY"]
    "nix-templates" = ["APP_ID", "APP_PRIVATE_KEY"]
    "nix-presets"   = ["APP_ID", "APP_PRIVATE_KEY"]
  }

  secret_values = {
    "ATTIC_PUSH_TOKEN"  = var.attic_push_token
    "APP_ID"            = var.github_app_id
    "APP_PRIVATE_KEY"   = var.github_app_private_key
    "NETBIRD_SETUP_KEY" = var.netbird_setup_key
  }

  ci_secret_pairs = merge([
    for repo, names in local.ci_secrets : {
      for n in names : "${repo}/${n}" => { repo = repo, secret = n }
    }
  ]...)
}

resource "github_actions_secret" "ci" {
  for_each = local.ci_secret_pairs

  repository  = each.value.repo
  secret_name = each.value.secret
  # `value` replaces the deprecated `plaintext_value` argument (provider v6.x).
  value = local.secret_values[each.value.secret]
}
