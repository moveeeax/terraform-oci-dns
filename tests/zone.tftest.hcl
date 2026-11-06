# Runs against a mocked OCI provider, so it needs no credentials and no network.
#
# `mock_provider` requires Terraform >= 1.7 (or OpenTofu >= 1.7). That is a
# requirement of the test suite only -- the module itself still supports
# Terraform >= 1.5, so versions.tf is deliberately left alone.
#
#   terraform init -backend=false && terraform test

mock_provider "oci" {}

variables {
  compartment_id = "ocid1.compartment.oc1..aaaaaaaaexamplecompartment"
  name           = "example.com"
}

# --- happy paths -------------------------------------------------------------

run "global_primary_defaults" {
  assert {
    condition     = oci_dns_zone.this.zone_type == "PRIMARY"
    error_message = "zone_type should default to PRIMARY."
  }

  assert {
    condition     = oci_dns_zone.this.scope == "GLOBAL"
    error_message = "scope should default to GLOBAL."
  }

  assert {
    condition     = oci_dns_zone.this.view_id == null
    error_message = "A GLOBAL zone must not be given a view_id."
  }

  assert {
    condition     = length(oci_dns_zone.this.external_masters) == 0
    error_message = "A PRIMARY zone must not declare external masters."
  }
}

run "private_zone_attaches_the_view" {
  variables {
    scope   = "PRIVATE"
    view_id = "ocid1.dnsview.oc1..aaaaaaaaexampleview"
  }

  # The whole point of a private zone: it is only resolvable through the view
  # that a VCN's resolver attaches. A private zone with no view resolves for
  # nobody, so assert the OCID actually reaches the resource.
  assert {
    condition     = oci_dns_zone.this.view_id == "ocid1.dnsview.oc1..aaaaaaaaexampleview"
    error_message = "view_id was not passed through to the zone; the private zone would not be attached to any view."
  }

  assert {
    condition     = oci_dns_zone.this.scope == "PRIVATE"
    error_message = "scope was not passed through to the zone."
  }
}

run "secondary_zone_passes_external_masters" {
  variables {
    zone_type = "SECONDARY"
    external_masters = [
      {
        address = "192.0.2.10"
        port    = 53
      },
      {
        address = "192.0.2.11"
      },
    ]
  }

  assert {
    condition     = length(oci_dns_zone.this.external_masters) == 2
    error_message = "Both external masters should be rendered onto the zone."
  }

  assert {
    condition = alltrue([
      for m in oci_dns_zone.this.external_masters : contains(["192.0.2.10", "192.0.2.11"], m.address)
    ])
    error_message = "external_masters addresses were not passed through."
  }
}

run "dnssec_can_be_enabled_on_a_global_zone" {
  variables {
    dnssec_state = "ENABLED"
  }

  assert {
    condition     = oci_dns_zone.this.dnssec_state == "ENABLED"
    error_message = "dnssec_state was not passed through to the zone."
  }
}

run "tags_are_passed_through" {
  variables {
    freeform_tags = { Environment = "test" }
    defined_tags  = { "Operations.CostCenter" = "42" }
  }

  assert {
    condition     = oci_dns_zone.this.freeform_tags["Environment"] == "test"
    error_message = "freeform_tags were not passed through."
  }

  assert {
    condition     = oci_dns_zone.this.defined_tags["Operations.CostCenter"] == "42"
    error_message = "defined_tags were not passed through."
  }
}

# --- rejected combinations ---------------------------------------------------

run "private_zone_without_a_view_is_rejected" {
  command = plan

  variables {
    scope = "PRIVATE"
  }

  expect_failures = [oci_dns_zone.this]
}

run "global_zone_with_a_view_is_rejected" {
  command = plan

  variables {
    scope   = "GLOBAL"
    view_id = "ocid1.dnsview.oc1..aaaaaaaaexampleview"
  }

  expect_failures = [oci_dns_zone.this]
}

run "secondary_zone_without_masters_is_rejected" {
  command = plan

  variables {
    zone_type = "SECONDARY"
  }

  expect_failures = [oci_dns_zone.this]
}

run "secondary_private_zone_is_rejected" {
  command = plan

  variables {
    zone_type = "SECONDARY"
    scope     = "PRIVATE"
    view_id   = "ocid1.dnsview.oc1..aaaaaaaaexampleview"
    external_masters = [
      { address = "192.0.2.10" },
    ]
  }

  expect_failures = [oci_dns_zone.this]
}

run "primary_zone_with_masters_is_rejected" {
  command = plan

  variables {
    zone_type = "PRIMARY"
    external_masters = [
      { address = "192.0.2.10" },
    ]
  }

  expect_failures = [oci_dns_zone.this]
}

run "dnssec_on_a_private_zone_is_rejected" {
  command = plan

  variables {
    scope        = "PRIVATE"
    view_id      = "ocid1.dnsview.oc1..aaaaaaaaexampleview"
    dnssec_state = "ENABLED"
  }

  expect_failures = [oci_dns_zone.this]
}

# --- rejected individual values ----------------------------------------------

run "rejects_invalid_zone_type" {
  command = plan

  variables {
    zone_type = "TERTIARY"
  }

  expect_failures = [var.zone_type]
}

run "rejects_invalid_scope" {
  command = plan

  variables {
    scope = "private"
  }

  expect_failures = [var.scope]
}

run "rejects_invalid_dnssec_state" {
  command = plan

  variables {
    dnssec_state = "enabled"
  }

  expect_failures = [var.dnssec_state]
}

run "rejects_zone_name_with_a_trailing_dot" {
  command = plan

  variables {
    name = "example.com."
  }

  expect_failures = [var.name]
}

run "rejects_single_label_zone_name" {
  command = plan

  variables {
    name = "example"
  }

  expect_failures = [var.name]
}

run "rejects_compartment_id_that_is_not_an_ocid" {
  command = plan

  variables {
    compartment_id = "my-compartment"
  }

  expect_failures = [var.compartment_id]
}

run "rejects_view_id_that_is_not_an_ocid" {
  command = plan

  variables {
    scope   = "PRIVATE"
    view_id = "my-view"
  }

  expect_failures = [var.view_id]
}

run "rejects_external_master_port_other_than_53" {
  command = plan

  variables {
    zone_type = "SECONDARY"
    external_masters = [
      {
        address = "192.0.2.10"
        port    = 5353
      },
    ]
  }

  expect_failures = [var.external_masters]
}

run "rejects_empty_external_master_address" {
  command = plan

  variables {
    zone_type = "SECONDARY"
    external_masters = [
      { address = "  " },
    ]
  }

  expect_failures = [var.external_masters]
}

run "rejects_defined_tag_key_without_a_namespace" {
  command = plan

  variables {
    defined_tags = { CostCenter = "42" }
  }

  expect_failures = [var.defined_tags]
}

# --- records -------------------------------------------------------------------

run "no_records_by_default" {
  assert {
    condition     = length(oci_dns_rrset.this) == 0
    error_message = "No rrset may be created unless records are given."
  }

  assert {
    condition     = output.record_fqdns == {}
    error_message = "record_fqdns must be empty when no records are given."
  }
}

run "records_resolve_names_from_keys" {
  variables {
    records = {
      "@/MX" = {
        rtype = "MX"
        rdata = ["10 mx1.example.net.", "20 mx2.example.net."]
      }
      "www/A" = {
        rtype = "A"
        ttl   = 60
        rdata = ["192.0.2.10"]
      }
      "api.example.com/CNAME" = {
        rtype = "CNAME"
        rdata = ["www.example.com."]
      }
      "spf" = {
        domain = "example.com"
        rtype  = "txt"
        rdata  = ["v=spf1 -all"]
      }
    }
  }

  assert {
    condition = output.record_fqdns == {
      "@/MX"                  = "example.com"
      "www/A"                 = "www.example.com"
      "api.example.com/CNAME" = "api.example.com"
      "spf"                   = "example.com"
    }
    error_message = "Record names were not resolved from the keys as documented."
  }

  assert {
    condition     = length(oci_dns_rrset.this["@/MX"].items) == 2
    error_message = "Each rdata value must become one item of the rrset."
  }

  assert {
    condition     = alltrue([for i in oci_dns_rrset.this["@/MX"].items : i.ttl == 300 && i.rtype == "MX" && i.domain == "example.com"])
    error_message = "Items must carry the rrset's domain and rtype and default to a TTL of 300."
  }

  assert {
    condition     = one(oci_dns_rrset.this["www/A"].items).ttl == 60
    error_message = "ttl must be passed through to the items."
  }

  assert {
    condition     = oci_dns_rrset.this["spf"].rtype == "TXT"
    error_message = "rtype must be upper-cased."
  }

  assert {
    condition     = oci_dns_rrset.this["www/A"].zone_name_or_id == oci_dns_zone.this.id
    error_message = "Records must target this module's zone."
  }

  assert {
    condition     = oci_dns_rrset.this["www/A"].view_id == null
    error_message = "Records in a global zone must not carry a view_id."
  }
}

run "records_in_a_private_zone_carry_the_view" {
  variables {
    name    = "internal.example.com"
    scope   = "PRIVATE"
    view_id = "ocid1.dnsview.oc1..aaaaaaaaexampleview"
    records = {
      "db/A" = {
        rtype = "A"
        rdata = ["10.0.0.5"]
      }
    }
  }

  assert {
    condition     = oci_dns_rrset.this["db/A"].view_id == "ocid1.dnsview.oc1..aaaaaaaaexampleview"
    error_message = "Records in a private zone must carry the zone's view."
  }

  assert {
    condition     = output.record_fqdns["db/A"] == "db.internal.example.com"
    error_message = "A relative name must get the zone appended."
  }
}

run "records_in_a_secondary_zone_are_rejected" {
  command = plan

  variables {
    zone_type        = "SECONDARY"
    external_masters = [{ address = "192.0.2.10" }]
    records = {
      "www/A" = {
        rtype = "A"
        rdata = ["192.0.2.10"]
      }
    }
  }

  expect_failures = [oci_dns_rrset.this]
}

run "record_outside_the_zone_is_rejected" {
  command = plan

  variables {
    records = {
      "other" = {
        domain = "www.example.org"
        rtype  = "A"
        rdata  = ["192.0.2.10"]
      }
    }
  }

  expect_failures = [oci_dns_rrset.this]
}

run "two_entries_for_one_rrset_are_rejected" {
  command = plan

  variables {
    records = {
      "www/A" = {
        rtype = "A"
        rdata = ["192.0.2.10"]
      }
      "www-second" = {
        domain = "www.example.com"
        rtype  = "A"
        rdata  = ["192.0.2.11"]
      }
    }
  }

  expect_failures = [oci_dns_rrset.this]
}

run "rejects_record_without_rdata" {
  command = plan

  variables {
    records = {
      "www/A" = {
        rtype = "A"
        rdata = []
      }
    }
  }

  expect_failures = [var.records]
}

run "rejects_record_with_zero_ttl" {
  command = plan

  variables {
    records = {
      "www/A" = {
        rtype = "A"
        ttl   = 0
        rdata = ["192.0.2.10"]
      }
    }
  }

  expect_failures = [var.records]
}

run "rejects_invalid_record_type" {
  command = plan

  variables {
    records = {
      "www/A" = {
        rtype = "A RECORD"
        rdata = ["192.0.2.10"]
      }
    }
  }

  expect_failures = [var.records]
}

run "rejects_record_domain_with_trailing_dot" {
  command = plan

  variables {
    records = {
      "www" = {
        domain = "www.example.com."
        rtype  = "A"
        rdata  = ["192.0.2.10"]
      }
    }
  }

  expect_failures = [var.records]
}
