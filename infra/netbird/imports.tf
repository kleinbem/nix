# Adopts the hand-made groups and SSH policy instead of creating duplicates.
#   1. `just ids` prints the live ids as tfvars; save them to imports.auto.tfvars.
#   2. `just plan` must show "N to import, 0 to add". Anything "to add" means a
#      wrong or empty id would duplicate an object: fix the tfvars first.
# An empty id skips that import and creates the object fresh.

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
