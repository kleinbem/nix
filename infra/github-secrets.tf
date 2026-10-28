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
# github-config additionally gets APP_INSTALLATION_ID: its tofu provider uses
# `app_auth {}` directly (no create-github-app-token step) and that needs the
# installation ID explicitly.
# ---------------------------------------------------------------------------

locals {
  # repo -> secrets it receives.
  ci_secrets = {
    # The Attic cache is mesh-only (nix-config#137), so every nix-config job
    # that uses it joins NetBird with the EPHEMERAL key: runner peers land in
    # ci-runners (cache-only policy) and auto-expire ~10 min after the run.
    # ATTIC_PULL_TOKEN (pull only) is for jobs that only read, PR builds
    # included; ATTIC_PUSH_TOKEN only for build-all's non-PR runs.
    "nix-config" = ["ATTIC_PUSH_TOKEN", "ATTIC_PULL_TOKEN", "APP_ID", "APP_PRIVATE_KEY", "NETBIRD_SETUP_KEY_EPHEMERAL", "NTFY_DEPLOY_TOPIC", "NTFY_ALERT_TOPIC", "NTFY_CI_TOKEN"]
    # The sub-flake CIs read the cache too, through kleinbem/actions/nix-setup:
    # pull token + ephemeral NetBird key, same ci-runners (cache-only) policy
    # as nix-config. Without them the action just builds without the cache.
    # APP_ID + APP_PRIVATE_KEY for each sub-flake's maintain.yaml (lock
    # updates committed via the Contents API).
    "nix-packages"  = ["APP_ID", "APP_PRIVATE_KEY", "ATTIC_PULL_TOKEN", "NETBIRD_SETUP_KEY_EPHEMERAL"]
    "nix-devshells" = ["APP_ID", "APP_PRIVATE_KEY", "ATTIC_PULL_TOKEN", "NETBIRD_SETUP_KEY_EPHEMERAL"]
    "nix-hardware"  = ["APP_ID", "APP_PRIVATE_KEY", "ATTIC_PULL_TOKEN", "NETBIRD_SETUP_KEY_EPHEMERAL"]
    "nix-templates" = ["APP_ID", "APP_PRIVATE_KEY", "ATTIC_PULL_TOKEN", "NETBIRD_SETUP_KEY_EPHEMERAL"]
    "nix-presets"   = ["APP_ID", "APP_PRIVATE_KEY", "ATTIC_PULL_TOKEN", "NETBIRD_SETUP_KEY_EPHEMERAL"]
    # The weekly release workflow opens PRs (App token) and alerts via ntfy.
    "nix-holds"  = ["APP_ID", "APP_PRIVATE_KEY", "NTFY_ALERT_TOPIC"]
    "nix-gantry" = ["ATTIC_PULL_TOKEN", "NETBIRD_SETUP_KEY_EPHEMERAL"]
    # NTFY_ALERT_TOPIC: the scheduled drift-detection plan (terraform-plan.yaml)
    # pings this human topic when GitHub config no longer matches Terraform.
    "github-config" = ["APP_ID", "APP_PRIVATE_KEY", "APP_INSTALLATION_ID", "NTFY_ALERT_TOPIC", "CLOUDFLARE_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"]
    # wrangler pages deploy — see cloudflare-pages.tf for the project/domain
    # resources and why this token is deliberately narrower than the one
    # this whole Terraform root itself uses.
    #
    # AUTHENTIK_CLIENT_SECRET/AUTH_SESSION_SECRET/TURNSTILE_SECRET_KEY: NOT
    # injected via cloudflare_pages_project's deployment_configs (see
    # cloudflare-pages.tf's header comment for why that stopped working once
    # kleinbem-site started shipping a wrangler.jsonc). Consumed instead by
    # a `wrangler pages secret put` step in kleinbem-site's own ci.yaml, run
    # every deploy, right before `wrangler pages deploy` — that's the only
    # reliable delivery path for a Wrangler-config-managed Pages project.
    #
    # RESEND_API_KEY deliberately NOT included — the contact form's email
    # send is going out unconfigured for now (fails gracefully, returns a
    # JSON error, doesn't break anything else); add it here + to ci.yaml's
    # secret-put step if/when a Resend (or replacement) key exists.
    "kleinbem-site" = [
      "CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_PAGES_DEPLOY_TOKEN",
      "AUTHENTIK_CLIENT_SECRET", "AUTH_SESSION_SECRET", "TURNSTILE_SECRET_KEY",
    ]
  }

  # Whether the token is set is not itself secret; for_each needs it plain.
  cachix_enabled             = nonsensitive(var.cachix_auth_token != "")
  mesh_agents_cachix_enabled = nonsensitive(var.mesh_agents_cachix_auth_token != "")

  secret_values = {
    "ATTIC_PUSH_TOKEN"              = var.attic_push_token
    "ATTIC_PULL_TOKEN"              = var.attic_pull_token
    "APP_ID"                        = var.github_app_id
    "APP_PRIVATE_KEY"               = var.github_app_private_key
    "APP_INSTALLATION_ID"           = var.github_app_installation_id
    "NETBIRD_SETUP_KEY"             = var.netbird_setup_key
    "NETBIRD_SETUP_KEY_EPHEMERAL"   = var.netbird_setup_key_ephemeral
    "NTFY_DEPLOY_TOPIC"             = var.ntfy_deploy_topic
    "NTFY_ALERT_TOPIC"              = var.ntfy_alert_topic
    "NTFY_CI_TOKEN"                 = var.ntfy_ci_token
    "CLOUDFLARE_ACCOUNT_ID"         = var.cloudflare_account_id
    "CLOUDFLARE_PAGES_DEPLOY_TOKEN" = var.cloudflare_pages_deploy_token
    "R2_ACCESS_KEY_ID"              = var.r2_state_access_key_id
    "R2_SECRET_ACCESS_KEY"          = var.r2_state_secret_access_key
    # kleinbem-site's Pages secrets (see ci_secrets comment above).
    "AUTHENTIK_CLIENT_SECRET" = authentik_provider_oauth2.kleinbem_site.client_secret
    "AUTH_SESSION_SECRET"     = var.kleinbem_site_session_secret
    "TURNSTILE_SECRET_KEY"    = cloudflare_turnstile_widget.kleinbem_site.secret
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

# Runs that Dependabot triggers only see Dependabot secrets, never Actions
# secrets, so each repo's dependabot-auto-merge.yaml gets the app credentials
# here. It arms auto-merge with an app token rather than GITHUB_TOKEN because
# a merge made by GITHUB_TOKEN triggers no push workflows on main, and
# kleinbem-site deploys from exactly that push. Direct var references, not
# secret_values, so a targeted apply stays clear of the Authentik provider.
locals {
  dependabot_app_secrets = {
    "APP_ID"          = var.github_app_id
    "APP_PRIVATE_KEY" = var.github_app_private_key
  }
  dependabot_secret_pairs = merge([
    # nix-config: its required `check` (ci.yml), sync-docs and build-all mint
    # an app token on pull_request, so Dependabot PRs fail without these.
    for repo in ["kleinbem-auth", "kleinbem-site", "nix-packages", "nix-config"] : {
      for n in keys(local.dependabot_app_secrets) : "${repo}/${n}" => { repo = repo, secret = n }
    }
  ]...)
}

resource "github_dependabot_secret" "app" {
  for_each = local.dependabot_secret_pairs

  repository  = each.value.repo
  secret_name = each.value.secret
  value       = local.dependabot_app_secrets[each.value.secret]
}

# kleinbem/nixpkgs-review-gha (fork of Defelo/nixpkgs-review-gha) builds
# nixpkgs PRs on GitHub runners and pushes the results to the public
# kleinbem-nixpkgs-review Cachix cache (Cachix-managed signing, separate from
# the kleinbem cache), so testers of those PRs can substitute instead of
# building. Only once the token exists in sops (see cachix_enabled).
#
# Its own resource rather than an entry in ci_secrets: secret_values also
# holds Authentik outputs, so going through it would make this secret depend
# on the Authentik provider.
resource "github_actions_secret" "nixpkgs_review_gha_cachix_token" {
  count = local.cachix_enabled ? 1 : 0

  repository  = "nixpkgs-review-gha"
  secret_name = "CACHIX_AUTH_TOKEN"
  value       = var.cachix_auth_token
}

# nixpkgs-review-gha reads the cache name from a variable, not a secret.
resource "github_actions_variable" "nixpkgs_review_gha_cachix_cache" {
  count = local.cachix_enabled ? 1 : 0

  repository    = "nixpkgs-review-gha"
  variable_name = "CACHIX_CACHE"
  value         = "kleinbem-nixpkgs-review"
}

# kleinbem/mesh-agents pushes its packages to the public mesh-agents Cachix
# cache from main, so users substitute instead of compiling mesh-llm. Only
# once the token exists in sops (see mesh_agents_cachix_enabled).
resource "github_actions_secret" "mesh_agents_cachix_token" {
  count = local.mesh_agents_cachix_enabled ? 1 : 0

  repository  = "mesh-agents"
  secret_name = "CACHIX_AUTH_TOKEN"
  value       = var.mesh_agents_cachix_auth_token
}

# Extra Nix configuration for the nixpkgs-review-gha runners: the CUDA team's
# binary cache, so CUDA reviews substitute NCCL and the CUDA libraries instead
# of compiling them. Public key from nixos-cuda/infra (hosts/hydra/cache.nix).
resource "github_actions_variable" "nixpkgs_review_gha_extra_nix_config" {
  repository    = "nixpkgs-review-gha"
  variable_name = "EXTRA_NIX_CONFIG"
  value         = <<-EOT
    extra-substituters = https://cache.nixos-cuda.org
    extra-trusted-public-keys = cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=
  EOT
}
