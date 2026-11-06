# Mail DNS for kleinbem.dev (Stalwart). The apex CNAME points at the tunnel
# (main.tf), so the MX points at mail.kleinbem.dev instead.

# --- A: mail.kleinbem.dev → host running Stalwart ---
# Not managed here: the mail host has a dynamic WAN IP, which would fight every
# apply. services.cloudflare-dyndns on mac-mini (nix-config) owns this record.

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
# For per-persona keys, add `dkim_pubkey_b64` to each persona in personas.nix
# and uncomment the block below. The domain-level key is enough for now.
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
# Covers every subdomain; needed for the Security Issues report and Safe
# Browsing reviews. If the property is removed and re-added, Google issues a
# new token and this value must change.
resource "cloudflare_record" "google_search_console" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  type    = "TXT"
  content = "google-site-verification=iDaMsHoHqNYGf1kciCOV-ZwKs7CkQkFY4RtzetTZVuU"
  comment = "Google Search Console domain-property verification (kleinbem.dev)"
}
