# Setup keys, managed as code.
#
# TWO keys, because hosts and CI have opposite lifecycles and must not share one:
#   - HOSTS are long-lived; their key must be persistent (a host offline for a
#     weekend must NOT be deleted).
#   - CI RUNNERS are throwaway; their key must be EPHEMERAL so each run's peer is
#     auto-removed ~10 min after it ends. This is the fix for the peer-count leak
#     (a reusable non-ephemeral key + no teardown is what pushed us past 100).
#
# Attributes reconciled against provider schema v0.0.9 — re-verify `ephemeral`
# with `just schema` before first apply (the field is API-confirmed but the
# provider is pre-1.0).

# --- CI runners: EPHEMERAL key -------------------------------------------------
# Enrolled peers auto-delete after ~10 min offline, so the fleet of one-shot
# GitHub Actions runners never accumulates. Auto-assigned to ci-runners so policy
# can scope them to ONLY the Attic cache peer (never personal-devices).
resource "netbird_setup_key" "ci_ephemeral" {
  name           = "ci-runners-ephemeral"
  type           = "reusable" # many runners reuse the one key
  ephemeral      = true       # peers removed ~10 min after going offline
  expiry_seconds = 31536000   # 365d key validity (schema uses seconds)
  auto_groups    = [netbird_group.ci_runners.id]
}

# Read with `tofu output -raw ci_ephemeral_setup_key`, then fan it out:
#   1. nix-secrets/secrets.yaml -> `netbird_setup_key_ephemeral` (sops updatekeys)
#   2. that flows to the NETBIRD_SETUP_KEY_EPHEMERAL Actions secret via infra/
#      (github-secrets.tf), which the CI workflows now prefer over the old key.
output "ci_ephemeral_setup_key" {
  value     = netbird_setup_key.ci_ephemeral.key
  sensitive = true
}

# --- Hosts: PERSISTENT key (migration target, not in the first apply) ----------
# Hosts work fine on the existing hand-made `netbird_setup_key` in nix-secrets,
# so adopting a TF-managed host key is a SEPARATE, later step — flipping it
# carelessly orphans the working netbird-autojoin. When ready:
#   1. uncomment, `just apply`, read `tofu output -raw hosts_setup_key`.
#   2. write it into nix-secrets/secrets.yaml as `netbird_setup_key` (sops
#      updatekeys) so autojoin + the NETBIRD_SETUP_KEY Actions secret keep working.
#   3. retire the hand-made console key.
#
# resource "netbird_setup_key" "hosts" {
#   name           = "infra-hosts"
#   type           = "reusable"
#   ephemeral      = false                              # hosts must persist
#   expiry_seconds = 31536000
#   auto_groups    = [netbird_group.personal_devices.id]
# }
#
# output "hosts_setup_key" {
#   value     = netbird_setup_key.hosts.key
#   sensitive = true
# }
