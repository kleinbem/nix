variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API Token with Zero Trust and DNS permissions"
  sensitive   = true
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID"
  sensitive   = true
}

variable "cloudflare_tunnel_secret" {
  type        = string
  description = "A 32-byte base64-encoded secret key for the tunnel"
  sensitive   = true
}

# --- GitHub (secret distribution only; repo config lives in github-config) ---

variable "github_tf_token" {
  type        = string
  sensitive   = true
  description = "Fine-grained PAT for distributing Actions secrets to the nix CI repos (Secrets R/W + Metadata R on nix, nix-config, nix-packages)."
}

variable "github_app_id" {
  type        = string
  sensitive   = true
  description = "GitHub App ID, distributed as the APP_ID Actions secret. Workflows mint a short-lived installation token via actions/create-github-app-token instead of using a long-lived PAT. Required App permissions: Contents R/W + Pull requests R/W on kleinbem/nix-config and kleinbem/nix-packages."
}

variable "github_app_private_key" {
  type        = string
  sensitive   = true
  description = "GitHub App private key (PEM), distributed as the APP_PRIVATE_KEY Actions secret. Used by actions/create-github-app-token to mint installation tokens at workflow runtime."
}

variable "attic_push_token" {
  type        = string
  sensitive   = true
  description = "Attic cache push token, distributed as the ATTIC_PUSH_TOKEN Actions secret."
}

variable "netbird_setup_key" {
  type        = string
  sensitive   = true
  description = "NetBird setup key, distributed as the NETBIRD_SETUP_KEY Actions secret. Used by hosted CI runners to bring up the NetBird WireGuard tunnel and push large NARs to Attic without hitting Cloudflare's 100 MiB upload limit. Being retired in favour of netbird_setup_key_ephemeral (kept as a fallback until CI is confirmed green on the ephemeral key)."
}

variable "netbird_setup_key_ephemeral" {
  type        = string
  sensitive   = true
  default     = ""
  description = "EPHEMERAL NetBird setup key (peers auto-deleted ~10 min after going offline), distributed as the NETBIRD_SETUP_KEY_EPHEMERAL Actions secret. Minted by infra/netbird/ (setup-keys.tf) and fanned here via sops. CI workflows prefer it over netbird_setup_key so one-shot runners stop accumulating against the peer cap. Empty default keeps apply working before the key is minted."
}

variable "ntfy_deploy_topic" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Secret ntfy topic name (sops: ntfy_deploy_topic), distributed as the NTFY_DEPLOY_TOPIC Actions secret. promote-production publishes 'production → SHA' to it after advancing the tag; hosts running my.deploy.autoUpgrade.ntfy long-poll it and upgrade immediately. The unguessable name is the access control on the public ntfy.kleinbem.dev vhost. Empty default keeps apply working before the topic is minted (the publish step in CI skips when the secret is empty)."
}

# --- Persona-fleet mail infrastructure ---

variable "mail_host_ip" {
  type        = string
  default     = ""
  description = "Public IPv4 of the host serving Stalwart (referenced by the mail.kleinbem.dev A record). Empty = no A record (the record is gated on this in cloudflare-dns.tf), so the root applies before Stalwart is deployed. Set it when Stalwart goes live. Stalwart's SMTP port can't be Cloudflare-proxied."
}
