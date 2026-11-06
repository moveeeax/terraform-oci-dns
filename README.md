# terraform-oci-dns

Terraform module that manages an [Oracle Cloud Infrastructure](https://www.oracle.com/cloud/)
DNS zone. It supports primary and secondary zones in both the global (internet-facing)
and private DNS scopes, and can manage the record sets of a primary zone.

## Usage

### Global (public) zone

```hcl
module "dns_zone" {
  source = "github.com/moveeeax/terraform-oci-dns?ref=v1.0.0"

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
  source = "github.com/moveeeax/terraform-oci-dns?ref=v1.0.0"

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
  source = "github.com/moveeeax/terraform-oci-dns?ref=v1.0.0"

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

### Records

```hcl
module "dns_zone" {
  source = "github.com/moveeeax/terraform-oci-dns?ref=v1.0.0"

  compartment_id = var.compartment_id
  name           = "example.com"

  records = {
    "@/MX" = {
      rtype = "MX"
      rdata = ["10 mx1.example.net.", "20 mx2.example.net."]
    }
    "www/A" = {
      rtype = "A"
      ttl   = 60
      rdata = ["192.0.2.10", "192.0.2.11"]
    }
    "_dmarc/TXT" = {
      rtype = "TXT"
      rdata = ["v=DMARC1; p=reject"]
    }
  }
}
```

See [Records](#records-1) for how names are resolved.

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
| `records` requires `zone_type = "PRIMARY"` | A secondary zone takes its records from the external masters. |
| Every record resolves to a name inside the zone | A record outside the zone cannot be written to it. |
| No two `records` entries resolve to the same name and type | Each entry is an authoritative rrset; two of them would overwrite each other on every apply. |

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
| `records`          | Record sets in the zone, keyed by a label (by convention `name/TYPE`). `PRIMARY` zones only.         | `map(object(...))`  | `{}`        |    no    |

`external_masters` entries are objects of:

| Field         | Type     | Required | Notes                                     |
|---------------|----------|:--------:|-------------------------------------------|
| `address`     | `string` |   yes    | The master server's IPv4 or IPv6 address. |
| `port`        | `number` |    no    | OCI only accepts `53`; leave null to omit.|
| `tsig_key_id` | `string` |    no    | OCID of the TSIG key.                     |

`records` values are objects of:

| Field    | Type           | Required | Notes                                                              |
|----------|----------------|:--------:|--------------------------------------------------------------------|
| `domain` | `string`       |    no    | FQDN without trailing dot. Defaults to the name taken from the key. |
| `rtype`  | `string`       |   yes    | Record type (`A`, `AAAA`, `CNAME`, `MX`, `TXT`, ...).               |
| `ttl`    | `number`       |    no    | Seconds, default `300`.                                            |
| `rdata`  | `list(string)` |   yes    | One value per record; at least one, none empty.                    |

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
| `record_fqdns`  | Resolved domain of each managed record set, keyed like `records`.                      |

## Records

`records` is a map; each entry becomes one `oci_dns_rrset` that targets the zone by
OCID. An rrset is authoritative for its (domain, rtype) pair: it replaces every
record of that type at that name, including records added in the Console or by
another tool. Put all values for a name and type in one entry's `rdata` list.

The map key is a free label, by convention `name/TYPE`. When `domain` is not set,
the part of the key before the first `/` is the name:

| Key            | Resolved domain (zone `example.com`) |
|----------------|--------------------------------------|
| `@/MX` or `/MX`| `example.com`                        |
| `www/A`        | `www.example.com`                    |
| `api.example.com/CNAME` | `api.example.com` (already in the zone) |
| `www` with `domain = "web.example.com"` | `web.example.com` |

`rtype` is upper-cased; `ttl` defaults to 300 seconds. Write `rdata` the way OCI
stores it (for example a CNAME or MX target with its trailing dot): OCI normalises
record data, and a value written differently can show up as a change on every
plan. `record_fqdns` maps each key to the resolved name.

The default `records = {}` creates no rrsets, so earlier configurations that manage
records next to the module keep working. When moving such records into the module,
remove the outside `oci_dns_rrset` for the same name and type, or use a `moved` /
`import` block, so the two do not fight over the set.

## Development

```sh
tofu fmt -recursive
tofu init -backend=false && tofu validate
tofu test          # mocked provider: no credentials, no network
tflint --recursive
```

## License

[MIT](LICENSE)
