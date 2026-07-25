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
