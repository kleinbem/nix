# Setup keys, managed as code. END STATE: this replaces the manually-created
# key currently in nix-secrets (`netbird_setup_key`). MIGRATION (do later, not
# in the first apply):
#   1. tofu apply this key, read its value from state/output.
#   2. Write it into nix-secrets/secrets.yaml as `netbird_setup_key`
#      (sops updatekeys) so the NixOS netbird-autojoin keeps working, AND
#      it continues to flow to the NETBIRD_SETUP_KEY Actions secret (infra/).
#   3. Retire the hand-made console key.
# Until migrated, leave this commented to avoid creating an orphan key.
#
# ⚠️ Verify attribute names (auto_groups vs autoGroups, ephemeral, etc.) against
#    the provider schema after `just init`.

# resource "netbird_setup_key" "smart_home" {
#   name        = "smart-home-hosts"
#   type        = "reusable"          # multiple hosts (hass-pi + future satellites)
#   expiry_days = 365
#   auto_groups = [netbird_group.smart_home.id]  # enrolled peers → smart-home
# }
#
# output "smart_home_setup_key" {
#   value     = netbird_setup_key.smart_home.key
#   sensitive = true
# }
