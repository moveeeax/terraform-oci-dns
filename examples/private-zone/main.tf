provider "oci" {}

# A private zone is only resolvable through a private DNS view, and a view is
# only consulted for a VCN whose resolver attaches it. Creating the zone alone
# is not enough -- the view has to exist and be attached, or the zone resolves
# for nobody. This example wires the whole path up.
resource "oci_dns_view" "internal" {
  compartment_id = var.compartment_id
  display_name   = "internal"
  scope          = "PRIVATE"

  freeform_tags = {
    ManagedBy = "terraform"
  }
}

module "dns_zone" {
  source = "../.."

  compartment_id = var.compartment_id
  name           = "internal.example.com"
  zone_type      = "PRIMARY" # private zones must be PRIMARY
  scope          = "PRIVATE"
  view_id        = oci_dns_view.internal.id

  freeform_tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

# Attach the view to the VCN's resolver so that instances in the VCN resolve
# names from the zone. Without this step the zone exists but answers no queries.
data "oci_core_vcn_dns_resolver_association" "this" {
  vcn_id = var.vcn_id
}

resource "oci_dns_resolver" "vcn" {
  resolver_id    = data.oci_core_vcn_dns_resolver_association.this.dns_resolver_id
  compartment_id = var.compartment_id
  scope          = "PRIVATE"

  attached_views {
    view_id = oci_dns_view.internal.id
  }
}

variable "compartment_id" {
  description = "Compartment OCID to deploy the example private DNS view and zone into."
  type        = string
}

variable "vcn_id" {
  description = "OCID of the VCN whose resolver should attach the private view."
  type        = string
}

output "dns_zone_id" {
  description = "OCID of the private DNS zone."
  value       = module.dns_zone.id
}

output "dns_view_id" {
  description = "OCID of the private DNS view containing the zone."
  value       = module.dns_zone.view_id
}
