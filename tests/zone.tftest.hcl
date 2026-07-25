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
