# Personas manifest — loaded from nix-config/personas.nix via the export
# script (`scripts/export-personas.sh`). Re-run the script before
# `tofu apply` if personas.nix changes; the JSON is the bridge between
# Nix-the-config-language and Terraform-the-config-language.
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
