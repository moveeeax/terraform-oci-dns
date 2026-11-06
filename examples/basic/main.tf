provider "oci" {}

module "dns_zone" {
  source = "../.."

  compartment_id = var.compartment_id
  name           = "example.com"
  zone_type      = "PRIMARY"
  scope          = "GLOBAL"

  # Each entry owns every record of its type at its name.
  records = {
    "www/A" = {
      rtype = "A"
      ttl   = 300
      rdata = ["192.0.2.10"]
    }
    "@/MX" = {
      rtype = "MX"
      rdata = ["10 mx1.example.net."]
    }
  }

  freeform_tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

variable "compartment_id" {
  description = "Compartment OCID to deploy the example DNS zone into."
  type        = string
}

output "dns_zone_id" {
  value = module.dns_zone.id
}

output "record_fqdns" {
  value = module.dns_zone.record_fqdns
}
