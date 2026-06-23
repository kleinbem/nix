# Access policies. `netbird ssh` rides these access rules — a source group can
# reach a destination group only if a policy permits it — so this is the SSH
# gate for the keyless `netbird ssh hass-pi` path (server enabled host-side via
# my.services.netbird.allowServerSsh).
#
# IMPORTANT: NetBird ships a default "All → All" policy. Codify its removal /
# narrowing here (or in the console) — otherwise every peer, including the
# persona fleet, can already reach hass-pi regardless of the rule below.
#
# Schema reconciled against provider v0.0.9: `rule` is a list-nested block with
# sources/destinations (group-id lists), protocol, ports, bidirectional, action.

resource "netbird_policy" "ssh_personal_to_smart_home" {
  name        = "ssh-personal-to-smart-home"
  description = "Allow SSH from personal devices to smart-home nodes (e.g. netbird ssh hass-pi)."
  enabled     = true

  rule {
    name          = "ssh"
    sources       = [netbird_group.personal_devices.id]
    destinations  = [netbird_group.smart_home.id]
    bidirectional = false
    protocol      = "tcp"
    ports         = ["22"]
    action        = "accept"
  }
}
