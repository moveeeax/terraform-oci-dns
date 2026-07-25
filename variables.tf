variable "compartment_id" {
  description = "OCID of the compartment in which to create the DNS zone."
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.(compartment|tenancy)\\.", var.compartment_id))
    error_message = "compartment_id must be a compartment or tenancy OCID (starting with \"ocid1.compartment.\" or \"ocid1.tenancy.\")."
  }
}

variable "name" {
  description = "Fully qualified domain name of the zone (e.g. example.com), without a trailing dot."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$", var.name))
    error_message = "name must be a fully qualified domain name of at least two labels with no trailing dot, e.g. \"example.com\"."
  }
}

variable "zone_type" {
  description = "Type of the zone. SECONDARY is only supported for GLOBAL zones and requires external_masters."
  type        = string
  default     = "PRIMARY"

  validation {
    condition     = contains(["PRIMARY", "SECONDARY"], var.zone_type)
    error_message = "zone_type must be PRIMARY or SECONDARY."
  }
}

variable "scope" {
  description = "Scope of the zone. GLOBAL zones are publicly resolvable on the internet; PRIVATE zones resolve only for the VCNs whose resolver attaches view_id."
  type        = string
  default     = "GLOBAL"

  validation {
    condition     = contains(["GLOBAL", "PRIVATE"], var.scope)
    error_message = "scope must be GLOBAL or PRIVATE."
  }
}

variable "view_id" {
  description = "OCID of the private DNS view that will contain the zone. Required when scope is PRIVATE, and must be null for GLOBAL zones."
  type        = string
  default     = null

  validation {
    condition     = var.view_id == null || can(regex("^ocid1\\.", var.view_id))
    error_message = "view_id must be an OCID (starting with \"ocid1.\") or null."
  }
}

variable "dnssec_state" {
  description = "State of DNSSEC on the zone: ENABLED or DISABLED. Null leaves the OCI default (DISABLED) in place. Only supported on GLOBAL zones. After enabling it you must publish the DS record exposed by the dnssec_config output in the parent zone."
  type        = string
  default     = null

  validation {
    condition     = var.dnssec_state == null || contains(["ENABLED", "DISABLED"], var.dnssec_state)
    error_message = "dnssec_state must be ENABLED, DISABLED, or null."
  }
}

variable "external_masters" {
  description = "List of external master nameservers for SECONDARY zones. Required when zone_type is SECONDARY and must be empty otherwise. OCI only accepts port 53; leave port null to use the default."
  type = list(object({
    address     = string
    port        = optional(number)
    tsig_key_id = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for m in var.external_masters : trimspace(m.address) != ""])
    error_message = "Every external_masters entry needs a non-empty address (the master server's IPv4 or IPv6 address)."
  }

  validation {
    condition     = alltrue([for m in var.external_masters : m.port == null || m.port == 53])
    error_message = "OCI only accepts port 53 for an external master. Set port = 53 or leave it null."
  }

  validation {
    condition     = alltrue([for m in var.external_masters : m.tsig_key_id == null || can(regex("^ocid1\\.", m.tsig_key_id))])
    error_message = "external_masters[*].tsig_key_id must be an OCID (starting with \"ocid1.\") or null."
  }
}

variable "freeform_tags" {
  description = "Free-form tags applied to the DNS zone."
  type        = map(string)
  default     = {}
}

variable "defined_tags" {
  description = "Defined tags applied to the DNS zone, keyed as \"namespace.key\"."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.defined_tags) : can(regex("^[^.]+\\.[^.]+$", k))])
    error_message = "defined_tags keys must be of the form \"namespace.key\" (exactly one dot), e.g. \"Operations.CostCenter\"."
  }
}
