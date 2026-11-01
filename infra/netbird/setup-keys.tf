# Two keys: hosts need a persistent one (a host offline for a weekend must stay),
# CI runners an ephemeral one so their peers are removed after each run instead
# of piling up against the peer limit.

# --- CI runners: EPHEMERAL key -------------------------------------------------
# Lands in ci-runners, which policies limit to the Attic cache peer.
resource "netbird_setup_key" "ci_ephemeral" {
  name           = "ci-runners-ephemeral"
  type           = "reusable" # many runners reuse the one key
  ephemeral      = true       # peers removed ~10 min after going offline
  expiry_seconds = 31536000   # 365d key validity (schema uses seconds)
  auto_groups    = [netbird_group.ci_runners.id]
}

# After a (re)create: copy `tofu output -raw ci_ephemeral_setup_key` into
# kleinbem-secrets/infra/terraform.yaml as `netbird_setup_key_ephemeral`; infra/
# (github-secrets.tf) pushes it to the NETBIRD_SETUP_KEY_EPHEMERAL Actions secret.
output "ci_ephemeral_setup_key" {
  value     = netbird_setup_key.ci_ephemeral.key
  sensitive = true
}

# --- Hosts: PERSISTENT key ------------------------------------------------
# New peers land in unclassified-hosts, which no policy references, so they get
# no access until added to a mesh group (inventory meshGroups, see inventory.tf).
# After a (re)create: copy `tofu output -raw hosts_setup_key` into
# kleinbem-secrets/nix/shared.yaml as `netbird_setup_key` (netbird-autojoin and
# the NETBIRD_SETUP_KEY secret read it). Enrolled hosts are unaffected.
resource "netbird_setup_key" "hosts" {
  name           = "infra-hosts"
  type           = "reusable"
  ephemeral      = false # hosts must persist
  expiry_seconds = 31536000
  auto_groups    = [netbird_group.unclassified_hosts.id]
}

output "hosts_setup_key" {
  value     = netbird_setup_key.hosts.key
  sensitive = true
}
