resource "oci_dns_zone" "this" {
  compartment_id = var.compartment_id
  name           = var.name
  zone_type      = var.zone_type
  scope          = var.scope
  view_id        = var.view_id
  dnssec_state   = var.dnssec_state

  dynamic "external_masters" {
    for_each = var.external_masters
    content {
      address     = external_masters.value.address
      port        = external_masters.value.port
      tsig_key_id = external_masters.value.tsig_key_id
    }
  }

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags

  # The OCI DNS API enforces these rules at apply time and the provider does not
  # check them, so a bad combination is only reported after Terraform has already
  # started making changes. Expressing them as preconditions surfaces the problem
  # during `terraform plan` instead.
  #
  # They are preconditions rather than `variable` validation blocks because each
  # one spans more than one variable, which variable validation cannot do before
  # Terraform 1.9 -- and this module supports >= 1.5.
  lifecycle {
    precondition {
      condition     = var.scope != "PRIVATE" || var.view_id != null
      error_message = "A PRIVATE zone must live in a private DNS view: set view_id to the OCID of an oci_dns_view. Without it the zone is not attached to any view and therefore resolves for no VCN."
    }

    precondition {
      condition     = var.scope != "GLOBAL" || var.view_id == null
      error_message = "view_id must be null for GLOBAL zones. Global zones are publicly resolvable and are not part of a private view; set scope = \"PRIVATE\" if a private zone was intended."
    }

    precondition {
      condition     = var.zone_type != "SECONDARY" || var.scope == "GLOBAL"
      error_message = "zone_type = \"SECONDARY\" is only supported for GLOBAL zones; private zones must use zone_type = \"PRIMARY\"."
    }

    precondition {
      condition     = var.zone_type != "SECONDARY" || length(var.external_masters) > 0
      error_message = "zone_type = \"SECONDARY\" requires at least one entry in external_masters; a secondary zone has nothing to transfer from otherwise."
    }

    precondition {
      condition     = var.zone_type != "PRIMARY" || length(var.external_masters) == 0
      error_message = "external_masters is only valid for zone_type = \"SECONDARY\"; a PRIMARY zone is authoritative and does not transfer from an external master."
    }

    precondition {
      condition     = var.dnssec_state != "ENABLED" || var.scope == "GLOBAL"
      error_message = "DNSSEC is not supported on private zones; dnssec_state may only be \"ENABLED\" when scope = \"GLOBAL\"."
    }
  }
}

# Records. Each map entry becomes one oci_dns_rrset, which is authoritative for
# its (domain, rtype) pair: it replaces every record of that type at that name,
# including ones added outside Terraform.
locals {
  zone_name = lower(var.name)

  # The part of the key before the first "/" is the record name when domain is
  # not given: "@" (or nothing) is the zone apex, a relative name gets the zone
  # appended, and a name that already ends in the zone is kept as is.
  records = {
    for k, r in var.records : k => {
      domain = lower(r.domain != null ? r.domain : (
        contains(["", "@"], split("/", k)[0]) ? local.zone_name : (
          endswith(lower(split("/", k)[0]), ".${local.zone_name}") || lower(split("/", k)[0]) == local.zone_name
          ? split("/", k)[0]
          : "${split("/", k)[0]}.${local.zone_name}"
        )
      ))
      rtype = upper(r.rtype)
      ttl   = r.ttl
      rdata = r.rdata
    }
  }
}

resource "oci_dns_rrset" "this" {
  for_each = local.records

  # The zone is addressed by OCID. compartment_id and scope are deprecated on
  # this resource and are left unset; view_id is only meaningful for private
  # zones and is null for global ones.
  zone_name_or_id = oci_dns_zone.this.id
  view_id         = var.view_id
  domain          = each.value.domain
  rtype           = each.value.rtype

  dynamic "items" {
    for_each = toset(each.value.rdata)
    content {
      domain = each.value.domain
      rtype  = each.value.rtype
      rdata  = items.value
      ttl    = each.value.ttl
    }
  }

  lifecycle {
    precondition {
      condition     = var.zone_type == "PRIMARY"
      error_message = "records can only be managed in a PRIMARY zone; a SECONDARY zone takes its records from the external masters."
    }

    precondition {
      condition     = each.value.domain == local.zone_name || endswith(each.value.domain, ".${local.zone_name}")
      error_message = "records[\"${each.key}\"] resolves to domain \"${each.value.domain}\", which is outside the zone ${local.zone_name}."
    }

    precondition {
      condition     = length([for k, r in local.records : k if r.domain == each.value.domain && r.rtype == each.value.rtype]) == 1
      error_message = "More than one records entry resolves to ${each.value.domain} ${each.value.rtype}. An rrset is authoritative for a (domain, rtype) pair, so put all values for it in one entry's rdata list."
    }
  }
}
