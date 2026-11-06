# personas.json is generated from nix-config/personas.nix (logic in
# nix-config/iac/data.nix). Re-run ../tools/gen-iac-data.sh after editing it;
# ../tools/check-iac-data.sh fails on drift.

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
