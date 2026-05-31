# ---------------------------------------------------------------------------
# Actions-secret distribution for the nix CI repos. This is the ONLY GitHub
# resource managed from the nix workspace — the values come from sops (exported
# as TF_VAR_* by scripts/tf-apply.sh), which is why it lives here rather than in
# the github-config repo. Secrets are write-only (no drift detection needed).
#
# All repo *settings/rulesets/labels* are owned by the github-config repo.
# ---------------------------------------------------------------------------

locals {
  # repo -> secrets it receives.
  ci_secrets = {
    "nix"          = ["ATTIC_PUSH_TOKEN", "GH_PAT"]
    "nix-config"   = ["ATTIC_PUSH_TOKEN", "GH_PAT"]
    "nix-packages" = ["ATTIC_PUSH_TOKEN", "GH_PAT"]
  }

  secret_values = {
    "ATTIC_PUSH_TOKEN" = var.attic_push_token
    "GH_PAT"           = var.github_ci_pat
  }

  ci_secret_pairs = merge([
    for repo, names in local.ci_secrets : {
      for n in names : "${repo}/${n}" => { repo = repo, secret = n }
    }
  ]...)
}

resource "github_actions_secret" "ci" {
  for_each = local.ci_secret_pairs

  repository      = each.value.repo
  secret_name     = each.value.secret
  plaintext_value = local.secret_values[each.value.secret]
}
