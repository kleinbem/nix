# Mail-routing DNS for `kleinbem.dev` (the primary persona email domain).
#
# Apex CNAME (`@`) already points at the cloudflared tunnel (main.tf:65).
# Cloudflare's CNAME flattening means we can serve mail off the same apex
# by declaring an MX that points at `mail.kleinbem.dev` (a separate
# A record, deliberately NOT declared here — see below).
#
# These records support the Stalwart container + AWS SES outbound relay
# established in nix-presets/containers/stalwart.nix.

# --- A: mail.kleinbem.dev → host running Stalwart ---
# NOT Terraform-managed. The mail host sits behind Digiweb's dynamic PPPoE
# IP (confirmed reachable + unblocked on port 25, 2026-09-24), so this
# record's source of truth is live network state, not a Tofu input — a
# value that changes on its own would just fight `tofu apply` on every
# run. `services.cloudflare-dyndns` on mac-mini (nix-config/hosts/mac-mini/
# default.nix) owns this record instead: creates it on first run, keeps it
# current on a 5-minute timer. If the mail host ever moves to a real static
# IP, this is the natural place to bring it back under Terraform.

# --- MX: route inbound mail for kleinbem.dev → mail.kleinbem.dev ---
resource "cloudflare_record" "mail_mx" {
  zone_id  = data.cloudflare_zone.main.id
  name     = "@"
  type     = "MX"
  content  = "mail.${local.primary_domain}"
  priority = 10
}

# --- SPF: authorise AWS SES (outbound relay) + Stalwart itself ---
# `include:amazonses.com` covers all SES sending IPs.
# `mx` allows the MX target to also send (useful for in-cluster mail).
# `-all` = hard fail on unauthorised senders (strict, reject unknown).
resource "cloudflare_record" "mail_spf" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  type    = "TXT"
  content = "v=spf1 mx include:amazonses.com -all"
}

# --- DMARC: reject unauth'd mail, report failures to dmarc@<domain> ---
resource "cloudflare_record" "mail_dmarc" {
  zone_id = data.cloudflare_zone.main.id
  name    = "_dmarc"
  type    = "TXT"
  content = "v=DMARC1; p=reject; rua=mailto:dmarc@${local.primary_domain}; aspf=s; adkim=s"
}

# --- MTA-STS: declare strict TLS expectations for incoming mail ---
# The version is just a serial — bump when you change the policy file
# served at https://mta-sts.<domain>/.well-known/mta-sts.txt
resource "cloudflare_record" "mail_mta_sts" {
  zone_id = data.cloudflare_zone.main.id
  name    = "_mta-sts"
  type    = "TXT"
  content = "v=STSv1; id=20260616000000Z"
}

# --- TLSRPT: where to send TLS-handshake failure reports ---
resource "cloudflare_record" "mail_tlsrpt" {
  zone_id = data.cloudflare_zone.main.id
  name    = "_smtp._tls"
  type    = "TXT"
  content = "v=TLSRPTv1; rua=mailto:tlsrpt@${local.primary_domain}"
}

# --- DKIM (per-persona) ---
# Stalwart generates one DKIM key per domain by default; if you want
# per-persona keys (selective revocation, finer audit), wire each
# persona's `dkim_pubkey_b64` into personas.nix and uncomment the block
# below. For Phase 1 the domain-level DKIM is enough — leave commented.
#
# resource "cloudflare_record" "persona_dkim" {
#   for_each = { for k, v in local.personas : k => v if can(v.dkim_pubkey_b64) }
#   zone_id  = data.cloudflare_zone.main.id
#   name     = "${each.key}._domainkey"
#   type     = "TXT"
#   content  = "v=DKIM1; k=rsa; p=${each.value.dkim_pubkey_b64}"
# }

# --- Domain-level DKIM (Stalwart auto-generated, you paste the pubkey) ---
# Stalwart writes the public key to /var/lib/stalwart/dkim-default.pub on
# first start. Read it, paste here, then run `tofu apply`.
variable "stalwart_dkim_pubkey_b64" {
  type        = string
  default     = ""
  description = "Stalwart-generated DKIM public key (base64, single line). Empty disables the record."
}

resource "cloudflare_record" "stalwart_dkim" {
  count   = var.stalwart_dkim_pubkey_b64 == "" ? 0 : 1
  zone_id = data.cloudflare_zone.main.id
  name    = "default._domainkey"
  type    = "TXT"
  content = "v=DKIM1; k=rsa; p=${var.stalwart_dkim_pubkey_b64}"
}

# --- Google Search Console: domain-property ownership verification ---
# Verifies the `sc-domain:kleinbem.dev` property (covers every subdomain,
# incl. vault.kleinbem.dev). Needed to see the Security Issues report and to
# request faster Safe Browsing reviews when Google false-flags a subdomain.
# Apex TXT; coexists with the SPF TXT above (Cloudflare allows multiple TXT
# at the same name). Value is issued per-property by Search Console — if the
# property is ever removed and re-added, Google mints a new token and this
# must be updated.
resource "cloudflare_record" "google_search_console" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  type    = "TXT"
  content = "google-site-verification=iDaMsHoHqNYGf1kciCOV-ZwKs7CkQkFY4RtzetTZVuU"
  comment = "Google Search Console domain-property verification (kleinbem.dev)"
}
