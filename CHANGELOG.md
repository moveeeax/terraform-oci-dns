# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `records` input: record sets managed in a primary zone, one authoritative
  `oci_dns_rrset` per entry, keyed by a label (by convention `name/TYPE`) with
  optional `domain`, `rtype`, `ttl` (default 300) and `rdata`. Plan-time checks
  reject records in secondary zones, names outside the zone and two entries for
  the same name and type. New output `record_fqdns`. Default `{}` creates
  nothing; existing inputs and outputs are unchanged.

[Unreleased]: https://github.com/moveeeax/terraform-oci-dns/compare/v1.1.0...HEAD
