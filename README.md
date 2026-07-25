# terraform-oci-dns

Terraform module that manages an [Oracle Cloud Infrastructure](https://www.oracle.com/cloud/)
DNS zone. It supports primary and secondary zones in both the global (internet-facing)
and private DNS scopes.

## Usage

### Global (public) zone

```hcl
module "dns_zone" {
  source = "github.com/moveeeax/terraform-oci-dns"

  compartment_id = var.compartment_id
  name           = "example.com"
  zone_type      = "PRIMARY"
  scope          = "GLOBAL"

  freeform_tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

### Private zone

A private zone is only resolvable through a private DNS **view**, and a view is
only consulted for a VCN whose resolver attaches it. `view_id` is therefore
mandatory when `scope = "PRIVATE"` — a private zone with no view resolves for
nobody. Private zones must also be `PRIMARY`.

```hcl
resource "oci_dns_view" "internal" {
  compartment_id = var.compartment_id
  display_name   = "internal"
  scope          = "PRIVATE"
}

module "private_zone" {
  source = "github.com/moveeeax/terraform-oci-dns"

  compartment_id = var.compartment_id
  name           = "internal.example.com"
  zone_type      = "PRIMARY"
  scope          = "PRIVATE"
  view_id        = oci_dns_view.internal.id
}
```

Creating the zone and the view is still not the whole job: the view has to be
attached to the VCN's resolver before anything in the VCN can resolve the zone.
[`examples/private-zone`](examples/private-zone) wires up the full path.

### Secondary zone

`SECONDARY` is only supported for `GLOBAL` zones, and OCI requires at least one
external master to transfer from. OCI only accepts port `53`.

```hcl
module "secondary_zone" {
  source = "github.com/moveeeax/terraform-oci-dns"

  compartment_id = var.compartment_id
  name           = "example.com"
  zone_type      = "SECONDARY"
  scope          = "GLOBAL"

  external_masters = [
    { address = "192.0.2.10", port = 53 },
    { address = "192.0.2.11" },
  ]
}
```

Runnable examples live in [`examples/`](examples).

## Constraints checked at plan time

The OCI DNS API rejects the combinations below at apply time, and the provider
does not check them, so a mistake is only reported once Terraform has started
making changes. This module enforces them as `precondition`s so `terraform plan`
fails instead:

| Rule | Why |
|------|-----|
| `scope = "PRIVATE"` requires `view_id` | A zone outside a view is attached to no resolver and resolves for nobody. |
| `scope = "GLOBAL"` requires `view_id == null` | Global zones are publicly resolvable and are not part of a private view. |
| `zone_type = "SECONDARY"` requires `scope = "GLOBAL"` | OCI only supports secondary zones in the global DNS; private zones must be `PRIMARY`. |
| `zone_type = "SECONDARY"` requires a non-empty `external_masters` | A secondary zone has nothing to transfer from otherwise. |
| `zone_type = "PRIMARY"` requires an empty `external_masters` | A primary zone is authoritative and does not transfer from an external master. |
| `dnssec_state = "ENABLED"` requires `scope = "GLOBAL"` | DNSSEC is not supported on private zones. |

## DNSSEC

`dnssec_state = "ENABLED"` signs the zone, but signing alone does not create a
chain of trust: the DS record for the active key-signing key must also be
published in the **parent** zone. That data is exposed through the
`dnssec_config` output:

```hcl
output "ds_records" {
  value = flatten([
    for k in module.dns_zone.dnssec_config[0].ksk_dnssec_key_versions : k.ds_data
  ])
}
```

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| oci       | >= 5.0   |

The test suite additionally requires Terraform (or OpenTofu) >= 1.7 for
`mock_provider`. That is a requirement of the tests only, not of the module.

## Inputs

| Name               | Description                                                                                          | Type                | Default     | Required |
|--------------------|------------------------------------------------------------------------------------------------------|---------------------|-------------|:--------:|
| `compartment_id`   | OCID of the compartment in which to create the DNS zone.                                             | `string`            | n/a         |   yes    |
| `name`             | Fully qualified domain name of the zone, without a trailing dot.                                     | `string`            | n/a         |   yes    |
| `zone_type`        | Type of the zone (`PRIMARY` or `SECONDARY`).                                                         | `string`            | `"PRIMARY"` |    no    |
| `scope`            | Scope of the zone (`GLOBAL` or `PRIVATE`).                                                           | `string`            | `"GLOBAL"`  |    no    |
| `view_id`          | OCID of the private DNS view containing the zone. Required for `PRIVATE`, must be null for `GLOBAL`. | `string`            | `null`      |    no    |
| `dnssec_state`     | `ENABLED` or `DISABLED`. Null leaves the OCI default (`DISABLED`). `GLOBAL` zones only.               | `string`            | `null`      |    no    |
| `external_masters` | External master nameservers for `SECONDARY` zones. Only port `53` is accepted.                       | `list(object(...))` | `[]`        |    no    |
| `freeform_tags`    | Free-form tags applied to the DNS zone.                                                              | `map(string)`       | `{}`        |    no    |
| `defined_tags`     | Defined tags applied to the zone, keyed `namespace.key`.                                             | `map(string)`       | `{}`        |    no    |

`external_masters` entries are objects of:

| Field         | Type     | Required | Notes                                     |
|---------------|----------|:--------:|-------------------------------------------|
| `address`     | `string` |   yes    | The master server's IPv4 or IPv6 address. |
| `port`        | `number` |    no    | OCI only accepts `53`; leave null to omit.|
| `tsig_key_id` | `string` |    no    | OCID of the TSIG key.                     |

## Outputs

| Name            | Description                                                                            |
|-----------------|----------------------------------------------------------------------------------------|
| `id`            | OCID of the DNS zone.                                                                  |
| `name`          | Fully qualified domain name of the zone.                                               |
| `nameservers`   | Authoritative nameservers for the zone.                                                |
| `serial`        | Current SOA serial of the zone.                                                        |
| `self`          | Canonical absolute URL of the zone.                                                    |
| `scope`         | Scope the zone was created in (`GLOBAL` or `PRIVATE`).                                 |
| `view_id`       | OCID of the private DNS view containing the zone; null for global zones.               |
| `dnssec_state`  | State of DNSSEC on the zone.                                                           |
| `dnssec_config` | DNSSEC key versions, including the `ds_data` to publish in the parent zone.             |

## Scope

This module manages the zone resource only. Records are managed separately with
`oci_dns_rrset`, which is authoritative for a given (domain, rtype) pair — it
replaces every record of that type at that name, so it is deliberately left
outside this module rather than half-modelled here.

## Development

```sh
tofu fmt -recursive
tofu init -backend=false && tofu validate
tofu test          # mocked provider: no credentials, no network
tflint --recursive
```

## License

[MIT](LICENSE)
