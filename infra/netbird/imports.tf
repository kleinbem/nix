# Adopt the existing NetBird console objects into state instead of duplicating
# them. The `personal-devices` / `smart-home` groups and the
# `ssh-personal-to-smart-home` policy were created by hand in the console before
# this root existed; these import blocks bind those live objects to the
# resources declared in groups.tf / policies.tf so the FIRST apply ADOPTS them
# (no duplicate "personal-devices" group, no second SSH policy).
#
# Workflow:
#   1. `just ids`  -> prints the live group/policy ids as ready-to-paste tfvars.
#   2. Save the output into `imports.auto.tfvars` (gitignored — the ids aren't
#      secret but are tenant-specific and would churn the repo).
#   3. `just plan` -> expect "N to import, 0 to add". If you see anything "to
#      add", an id is wrong or empty and Tofu would DUPLICATE the object — stop
#      and fix the tfvars before applying.
#
# Leaving an id empty disables that import (the resource is created fresh on
# apply). The for_each toggle requires OpenTofu >= 1.7 (for_each in import
# blocks); the workspace ships a newer tofu, but pin awareness here in case the
# bootstrap shell lags.

variable "personal_devices_group_id" {
  type        = string
  default     = ""
  description = "Live id of the existing 'personal-devices' NetBird group (from `just ids`). Empty = create fresh."
}

variable "smart_home_group_id" {
  type        = string
  default     = ""
  description = "Live id of the existing 'smart-home' NetBird group (from `just ids`). Empty = create fresh."
}

variable "ssh_policy_id" {
  type        = string
  default     = ""
  description = "Live id of the existing 'ssh-personal-to-smart-home' NetBird policy (from `just ids`). Empty = create fresh."
}

import {
  for_each = var.personal_devices_group_id == "" ? toset([]) : toset([var.personal_devices_group_id])
  to       = netbird_group.personal_devices
  id       = each.value
}

import {
  for_each = var.smart_home_group_id == "" ? toset([]) : toset([var.smart_home_group_id])
  to       = netbird_group.smart_home
  id       = each.value
}

import {
  for_each = var.ssh_policy_id == "" ? toset([]) : toset([var.ssh_policy_id])
  to       = netbird_policy.ssh_personal_to_smart_home
  id       = each.value
}
