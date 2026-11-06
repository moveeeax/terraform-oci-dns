output "id" {
  description = "OCID of the DNS zone."
  value       = oci_dns_zone.this.id
}

output "name" {
  description = "Fully qualified domain name of the zone."
  value       = oci_dns_zone.this.name
}

output "nameservers" {
  description = "Authoritative nameservers for the zone."
  value       = oci_dns_zone.this.nameservers
}

output "serial" {
  description = "Current SOA serial of the zone."
  value       = oci_dns_zone.this.serial
}

output "self" {
  description = "Canonical absolute URL of the zone."
  value       = oci_dns_zone.this.self
}

output "scope" {
  description = "Scope the zone was created in (GLOBAL or PRIVATE)."
  value       = oci_dns_zone.this.scope
}

output "view_id" {
  description = "OCID of the private DNS view containing the zone; null for GLOBAL zones."
  value       = oci_dns_zone.this.view_id
}

output "dnssec_state" {
  description = "State of DNSSEC on the zone."
  value       = oci_dns_zone.this.dnssec_state
}

output "dnssec_config" {
  description = "DNSSEC key versions for the zone. The ds_data of the active key-signing key must be published as a DS record in the parent zone, otherwise enabling DNSSEC has no effect."
  value       = oci_dns_zone.this.dnssec_config
}

output "record_fqdns" {
  description = "Fully qualified domain name of each managed record set, keyed like var.records."
  value       = { for k, r in oci_dns_rrset.this : k => r.domain }
}
