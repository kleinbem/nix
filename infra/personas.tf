# Personas manifest — the Nix ⇄ OpenTofu bridge. personas.json is generated
# from nix-config/personas.nix ⊕ kleinbem-secrets/personas/contact.nix by
# `../tools/gen-iac-data.sh` (projection logic: nix-config/iac/data.nix).
# Re-run that script after editing personas.nix; `../tools/check-iac-data.sh`
# (and the `iac-data` flake check in nix-config) fail on drift.
#
# Used by cloudflare-dns.tf (per-persona DKIM CNAMEs) and aws-ses.tf
# (per-persona SES identity if you want isolated reputation tracking).

locals {
  personas_json_path = "${path.module}/personas.json"
  personas           = jsondecode(file(local.personas_json_path))
  # Convenience: just the email-local-part keys (michael, thomas, …).
  persona_names = keys(local.personas)
  # Convenience: just the email-domain (deduped — should be a single domain).
  persona_domains = distinct([for p in local.personas : split("@", p.email)[1]])
  primary_domain  = local.persona_domains[0]
}

output "persona_names" {
  value = local.persona_names
}
