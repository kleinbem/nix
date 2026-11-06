# State backend: LOCAL (no block = local backend).
#
# This root CREATES the `tofu-state` bucket, so it can't store its own state
# there (chicken-and-egg) — same reason infra/ uses local state to bootstrap the
# R2 bucket. Local state on the LUKS workstation is fine here; the managed set is
# tiny (2 buckets + 2 keys), so re-import is cheap if state is ever lost. State
# lives in ./terraform.tfstate (gitignored).
#
# Once this is applied, OTHER roots (e.g. infra/netbird) can migrate their state
# INTO the `tofu-state` bucket via the s3 backend pointing at Garage over NetBird
# — just not this root's own.
