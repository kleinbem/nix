# Actions/Dependabot secrets for the CI repos. Here rather than in github-config
# because the values come from sops via TF_VAR_* in tools/tf-apply.sh. Workflows
# that write to GitHub mint an App token from APP_ID + APP_PRIVATE_KEY.

locals {
  # repo -> secrets it receives.
  ci_secrets = {
    # Attic is mesh-only, so cache jobs join NetBird with the ephemeral key
    # (ci-runners group, cache-only). Push token only for build-all's non-PR runs.
    "nix-config" = ["ATTIC_PUSH_TOKEN", "ATTIC_PULL_TOKEN", "APP_ID", "APP_PRIVATE_KEY", "NETBIRD_SETUP_KEY_EPHEMERAL", "NTFY_DEPLOY_TOPIC", "NTFY_ALERT_TOPIC", "NTFY_CI_TOKEN"]
    # Sub-flakes read the cache through kleinbem/actions/nix-setup (builds
    # without it if the secrets are missing); the App creds are for maintain.yaml.
    "nix-packages"  = ["APP_ID", "APP_PRIVATE_KEY", "ATTIC_PULL_TOKEN", "NETBIRD_SETUP_KEY_EPHEMERAL"]
    "nix-devshells" = ["APP_ID", "APP_PRIVATE_KEY", "ATTIC_PULL_TOKEN", "NETBIRD_SETUP_KEY_EPHEMERAL"]
    "nix-hardware"  = ["APP_ID", "APP_PRIVATE_KEY", "ATTIC_PULL_TOKEN", "NETBIRD_SETUP_KEY_EPHEMERAL"]
    "nix-templates" = ["APP_ID", "APP_PRIVATE_KEY", "ATTIC_PULL_TOKEN", "NETBIRD_SETUP_KEY_EPHEMERAL"]
    "nix-presets"   = ["APP_ID", "APP_PRIVATE_KEY", "ATTIC_PULL_TOKEN", "NETBIRD_SETUP_KEY_EPHEMERAL"]
    # The fleet's own holds list: release PRs (App token), ntfy alert, and
    # Attic for the release checks of our own packages.
    "nix-detour-fleet" = ["APP_ID", "APP_PRIVATE_KEY", "NTFY_ALERT_TOPIC", "ATTIC_PULL_TOKEN", "NETBIRD_SETUP_KEY_EPHEMERAL"]
    # sync-org.yaml copies the central config to kleinbem-dev/coderabbit
    # through the App's org installation.
    "coderabbit" = ["APP_ID", "APP_PRIVATE_KEY"]
    # The r2-budget workflow (R2_BUDGET_TOKEN is its own resource below).
    "nix" = ["CLOUDFLARE_ACCOUNT_ID", "NTFY_ALERT_TOPIC"]
    # NTFY_ALERT_TOPIC: the scheduled drift-detection plan (terraform-plan.yaml)
    # pings this human topic when GitHub config no longer matches Terraform.
    "github-config" = ["APP_ID", "APP_PRIVATE_KEY", "APP_INSTALLATION_ID", "APP_ORG_INSTALLATION_ID", "NTFY_ALERT_TOPIC", "CLOUDFLARE_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"]
    # Deploy token plus the Pages secrets kleinbem-site's ci.yaml sets with
    # `wrangler pages secret put` before each deploy (see cloudflare-pages.tf).
    # No RESEND_API_KEY yet: the contact form's mail send fails gracefully.
    "kleinbem-site" = [
      "CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_PAGES_DEPLOY_TOKEN",
      "AUTHENTIK_CLIENT_SECRET", "AUTH_SESSION_SECRET", "TURNSTILE_SECRET_KEY",
    ]
  }

  # Repos under the kleinbem-dev organization (github-config's org_repos):
  # same secrets, written through the `org` provider alias. nix-gantry's CI
  # reads the cache through kleinbem/actions/nix-setup like the sub-flakes;
  # the App creds are for its lock-bump dispatch to nix-config.
  org_ci_secrets = {
    "nix-gantry" = ["APP_ID", "APP_PRIVATE_KEY", "ATTIC_PULL_TOKEN", "NETBIRD_SETUP_KEY_EPHEMERAL"]
  }

  # Whether the token is set is not itself secret; for_each needs it plain.
  cachix_enabled = nonsensitive(var.cachix_auth_token != "")
  public_cache_enabled = nonsensitive(
    var.public_cache_access_key_id != "" &&
    var.public_cache_secret_access_key != "" &&
    var.public_cache_signing_key != ""
  )
  # Projects whose CI pushes to the public cache (public-cache.tf).
  public_cache_repos     = []
  org_public_cache_repos = ["cadre"]
  public_cache_secrets = {
    CACHE_ACCESS_KEY_ID     = var.public_cache_access_key_id
    CACHE_SECRET_ACCESS_KEY = var.public_cache_secret_access_key
    CACHE_SIGNING_KEY       = var.public_cache_signing_key
  }

  secret_values = {
    "ATTIC_PUSH_TOKEN"              = var.attic_push_token
    "ATTIC_PULL_TOKEN"              = var.attic_pull_token
    "APP_ID"                        = var.github_app_id
    "APP_PRIVATE_KEY"               = var.github_app_private_key
    "APP_INSTALLATION_ID"           = var.github_app_installation_id
    "APP_ORG_INSTALLATION_ID"       = var.github_app_org_installation_id
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
  org_ci_secret_pairs = merge([
    for repo, names in local.org_ci_secrets : {
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

resource "github_actions_secret" "org_ci" {
  for_each = local.org_ci_secret_pairs
  provider = github.org

  repository  = each.value.repo
  secret_name = each.value.secret
  value       = local.secret_values[each.value.secret]
}

# nix-gantry moved to the org; its secrets travelled with the
# repo, so the state entries move too instead of being recreated.
moved {
  from = github_actions_secret.ci["nix-gantry/ATTIC_PULL_TOKEN"]
  to   = github_actions_secret.org_ci["nix-gantry/ATTIC_PULL_TOKEN"]
}
moved {
  from = github_actions_secret.ci["nix-gantry/NETBIRD_SETUP_KEY_EPHEMERAL"]
  to   = github_actions_secret.org_ci["nix-gantry/NETBIRD_SETUP_KEY_EPHEMERAL"]
}

# A repo rename: moved, so the replacement deletes the old secret before
# creating the new one. As two separate resources, the delete (through
# GitHub's redirect from the old name) could remove the new secret.
moved {
  from = github_actions_secret.ci["nix-holds-fleet/APP_ID"]
  to   = github_actions_secret.ci["nix-detour-fleet/APP_ID"]
}
moved {
  from = github_actions_secret.ci["nix-holds-fleet/APP_PRIVATE_KEY"]
  to   = github_actions_secret.ci["nix-detour-fleet/APP_PRIVATE_KEY"]
}
moved {
  from = github_actions_secret.ci["nix-holds-fleet/NTFY_ALERT_TOPIC"]
  to   = github_actions_secret.ci["nix-detour-fleet/NTFY_ALERT_TOPIC"]
}
moved {
  from = github_actions_secret.ci["nix-holds-fleet/ATTIC_PULL_TOKEN"]
  to   = github_actions_secret.ci["nix-detour-fleet/ATTIC_PULL_TOKEN"]
}
moved {
  from = github_actions_secret.ci["nix-holds-fleet/NETBIRD_SETUP_KEY_EPHEMERAL"]
  to   = github_actions_secret.ci["nix-detour-fleet/NETBIRD_SETUP_KEY_EPHEMERAL"]
}

# Dependabot-triggered runs only see Dependabot secrets. They need an App token
# because a GITHUB_TOKEN merge triggers no push workflows on main (kleinbem-site
# deploys from that push). Direct var refs, not secret_values, keep a targeted
# apply clear of the Authentik provider.
locals {
  dependabot_app_secrets = {
    "APP_ID"          = var.github_app_id
    "APP_PRIVATE_KEY" = var.github_app_private_key
  }
  dependabot_secret_pairs = merge([
    # nix-config: its required `check` (ci.yml), sync-docs and build-all mint
    # an app token on pull_request, so Dependabot PRs fail without these.
    # kleinbem-site: kleinbem/actions dependabot-auto-merge.
    for repo in ["kleinbem-site", "nix-packages", "nix-config"] : {
      for n in keys(local.dependabot_app_secrets) : "${repo}/${n}" => { repo = repo, secret = n }
    }
  ]...)
  # The same for kleinbem-dev repos, written through the `org` provider.
  org_dependabot_secret_pairs = merge([
    for repo in ["revue", "nix-detour"] : {
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

resource "github_dependabot_secret" "org_app" {
  for_each = local.org_dependabot_secret_pairs
  provider = github.org

  repository  = each.value.repo
  secret_name = each.value.secret
  value       = local.dependabot_app_secrets[each.value.secret]
}

# nixpkgs-review-gha pushes nixpkgs PR builds to the public kleinbem-nixpkgs-review
# Cachix cache so testers can substitute. Not in ci_secrets: secret_values holds
# Authentik outputs, which would make this depend on the Authentik provider.
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

# public_cache_repos (and org_public_cache_repos) push their main build to
# the public cache (public-cache.tf). S3 creds come from r2-tokens/, the signing
# key is made by hand; nothing is distributed until all three are in sops.
resource "github_actions_secret" "public_cache" {
  for_each = local.public_cache_enabled ? {
    for pair in setproduct(local.public_cache_repos, keys(local.public_cache_secrets)) :
    "${pair[0]}/${pair[1]}" => { repo = pair[0], name = pair[1] }
  } : {}

  repository  = each.value.repo
  secret_name = each.value.name
  value       = local.public_cache_secrets[each.value.name]
}

resource "github_actions_secret" "org_public_cache" {
  for_each = local.public_cache_enabled ? {
    for pair in setproduct(local.org_public_cache_repos, keys(local.public_cache_secrets)) :
    "${pair[0]}/${pair[1]}" => { repo = pair[0], name = pair[1] }
  } : {}
  provider = github.org

  repository  = each.value.repo
  secret_name = each.value.name
  value       = local.public_cache_secrets[each.value.name]
}

# mesh-agents was renamed to cadre and moved to the kleinbem-dev organization.
moved {
  from = github_actions_secret.public_cache["mesh-agents/CACHE_ACCESS_KEY_ID"]
  to   = github_actions_secret.org_public_cache["cadre/CACHE_ACCESS_KEY_ID"]
}
moved {
  from = github_actions_secret.public_cache["mesh-agents/CACHE_SECRET_ACCESS_KEY"]
  to   = github_actions_secret.org_public_cache["cadre/CACHE_SECRET_ACCESS_KEY"]
}
moved {
  from = github_actions_secret.public_cache["mesh-agents/CACHE_SIGNING_KEY"]
  to   = github_actions_secret.org_public_cache["cadre/CACHE_SIGNING_KEY"]
}

# kleinbem/nix's r2-budget workflow (tools/r2-budget.sh): R2 has no spending
# cap, so it estimates the bill and takes the public cache offline past the
# budget. CLOUDFLARE_ACCOUNT_ID and NTFY_ALERT_TOPIC come from ci_secrets.
resource "github_actions_secret" "r2_budget_token" {
  count = nonsensitive(var.r2_budget_token != "") ? 1 : 0

  repository  = "nix"
  secret_name = "R2_BUDGET_TOKEN"
  value       = var.r2_budget_token
}

# Where CI pushes: the bucket through R2's S3 endpoint. Not secret (the
# account id is in every R2 URL), so a variable the workflow can show.
resource "github_actions_variable" "public_cache_store" {
  for_each = local.public_cache_enabled ? toset(local.public_cache_repos) : []

  repository    = each.key
  variable_name = "CACHE_STORE"
  value         = "s3://${cloudflare_r2_bucket.public_cache.name}?endpoint=https://${nonsensitive(var.cloudflare_account_id)}.r2.cloudflarestorage.com&region=auto"
}

resource "github_actions_variable" "org_public_cache_store" {
  for_each = local.public_cache_enabled ? toset(local.org_public_cache_repos) : []
  provider = github.org

  repository    = each.key
  variable_name = "CACHE_STORE"
  value         = "s3://${cloudflare_r2_bucket.public_cache.name}?endpoint=https://${nonsensitive(var.cloudflare_account_id)}.r2.cloudflarestorage.com&region=auto"
}

moved {
  from = github_actions_variable.public_cache_store["mesh-agents"]
  to   = github_actions_variable.org_public_cache_store["cadre"]
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

# github-config's terraform-apply.yaml reads its credentials from this
# environment, which only main can deploy to. GitHub enforces that outside the
# workflow file, so a dispatch on a branch with an older workflow gets nothing.
# The repo-level copies in ci_secrets stay until the workflow uses the
# environment; the PR plan (terraform-plan.yaml) still reads those. Direct var
# refs, not secret_values, keep a targeted apply clear of Authentik.
locals {
  github_config_apply_secrets = {
    "APP_ID"                  = var.github_app_id
    "APP_PRIVATE_KEY"         = var.github_app_private_key
    "APP_INSTALLATION_ID"     = var.github_app_installation_id
    "APP_ORG_INSTALLATION_ID" = var.github_app_org_installation_id
    "CLOUDFLARE_ACCOUNT_ID"   = var.cloudflare_account_id
    "R2_ACCESS_KEY_ID"        = var.r2_state_access_key_id
    "R2_SECRET_ACCESS_KEY"    = var.r2_state_secret_access_key
  }
}

resource "github_repository_environment" "github_config_apply" {
  repository  = "github-config"
  environment = "apply"
  # Admins would otherwise skip the branch policy, and the admin runs every apply.
  can_admins_bypass = false

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "github_config_apply_main" {
  repository     = "github-config"
  environment    = github_repository_environment.github_config_apply.environment
  branch_pattern = "main"
}

resource "github_actions_environment_secret" "github_config_apply" {
  # Names spelled out: for_each can't take keys of a map of sensitive values.
  for_each = toset([
    "APP_ID", "APP_PRIVATE_KEY", "APP_INSTALLATION_ID", "APP_ORG_INSTALLATION_ID",
    "CLOUDFLARE_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY",
  ])

  repository  = "github-config"
  environment = github_repository_environment.github_config_apply.environment
  secret_name = each.key
  value       = local.github_config_apply_secrets[each.key]
}
