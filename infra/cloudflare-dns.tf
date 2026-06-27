# Mail-routing DNS for `kleinbem.dev` (the primary persona email domain).
#
# Apex CNAME (`@`) already points at the cloudflared tunnel (main.tf:65).
# Cloudflare's CNAME flattening means we can serve mail off the same apex
# by declaring an MX that points at `mail.kleinbem.dev` (a separate
# A record below).
#
# These records support the Stalwart container + AWS SES outbound relay
# established in nix-presets/containers/stalwart.nix.

# --- A: mail.kleinbem.dev → host running Stalwart ---
# Replace var.mail_host_ip with the WAN IP of the host (or use a CNAME
# to the cloudflared tunnel if you front Stalwart via Cloudflare Spectrum).
resource "cloudflare_record" "mail_a" {
  # Only create the record once a real Stalwart host IP is set — same gating
  # pattern as stalwart_dkim below. Empty mail_host_ip = no record, so the root
  # applies cleanly (and without prompting) before Stalwart is deployed.
  count   = var.mail_host_ip == "" ? 0 : 1
  zone_id = data.cloudflare_zone.main.id
  name    = "mail"
  content = var.mail_host_ip
  type    = "A"
  proxied = false # SMTP can't be Cloudflare-proxied
  comment = "Stalwart mail server — see nix-presets/containers/stalwart.nix"
}

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
