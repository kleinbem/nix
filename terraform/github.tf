# ---------------------------------------------------------------------------
# GitHub IaC — declaratively manage repository Actions secrets (and, optionally,
# branch protection) the same way Cloudflare is managed in this directory.
#
# Token model (GitHub has NO API to mint user PATs, so values are created by
# hand once and stored in sops — Terraform only DISTRIBUTES them):
#   * var.github_tf_token  — admin PAT the provider authenticates with
#                            (classic: repo + workflow). May be the same
#                            physical PAT as github_ci_pat if scoped widely.
#   * var.attic_push_token — Attic push token → ATTIC_PUSH_TOKEN secret
#   * var.github_ci_pat    — CI automation PAT → GH_PAT secret
#
# sops (nix-secrets/secrets.yaml) is the single source of truth: rotate there,
# re-run scripts/tf-apply.sh, and every repo's secret updates in lockstep.
# ---------------------------------------------------------------------------

provider "github" {
  owner = "kleinbem"
  token = var.github_tf_token
}

locals {
  # Repos whose CI consumes the shared Attic + automation secrets.
  managed_repos = [
    "nix",
    "nix-config",
  ]
}

# --- Shared Actions secrets, fanned out to every managed repo --------------
# SECURITY: plaintext_value is persisted in tfstate. State here is local and
# gitignored (same as cloudflare_tunnel_secret) — never commit terraform.tfstate
# and do not move to a remote backend without encryption.

resource "github_actions_secret" "attic_push_token" {
  for_each        = toset(local.managed_repos)
  repository      = each.value
  secret_name     = "ATTIC_PUSH_TOKEN"
  plaintext_value = var.attic_push_token
}

resource "github_actions_secret" "gh_pat" {
  for_each        = toset(local.managed_repos)
  repository      = each.value
  secret_name     = "GH_PAT"
  plaintext_value = var.github_ci_pat
}

# --- Branch protection (OPTIONAL) ------------------------------------------
# Disabled by default so the first apply cannot disrupt your direct push-to-main
# workflow. `enforce_admins` defaults to false, so even when enabled the repo
# OWNER bypasses these rules — they apply to other collaborators / the automated
# flake-update PRs. Status-check `contexts` are the CI *job display names*.
# Uncomment to enable:
#
# resource "github_branch_protection" "nix_main" {
#   repository_id = "nix"
#   pattern       = "main"
#   enforce_admins = false
#   required_status_checks {
#     strict   = true
#     contexts = [
#       "Lint & Format Audit",
#       "Nix Flake Evaluation & Checks",
#     ]
#   }
# }
#
# resource "github_branch_protection" "nix_config_main" {
#   repository_id = "nix-config"
#   pattern       = "main"
#   enforce_admins = false
#   required_status_checks {
#     strict   = true
#     contexts = ["check"]
#   }
# }
