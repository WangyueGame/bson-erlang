# Map Encoding Decision

This document records the BSON library decision for Erlang map input.

## Decision

`map()` input is treated as unordered BSON document input.

The library does not guarantee a stable field order when encoding a map with
`bson_binary:put_document/1` or when traversing a map through `bson:doc_foldl/3`.
If a caller needs a specific BSON field order, it must use `bson:document/1`
or a tuple document directly.

## Rationale

The BSON library is primarily responsible for BSON encoding and decoding, not
for adding ordering semantics to Erlang maps.

For this project, the trade-off is:

- prefer lower encoding overhead for `map()` input
- keep ordered document semantics on tuple/list document APIs
- validate map-based behavior through field lookup and value equality instead of
  exact tuple ordering

Sorting map keys during encoding made the output deterministic, but it also
added measurable overhead on common encoding paths. Since callers do not rely on
ordered map output as a public contract, the library keeps map encoding
unordered and reserves ordered BSON construction for explicit document APIs.

## Testing Guidance

Tests for map input should verify logical document content, for example through:

- `bson:lookup/2`
- `bson:at/2`
- `bson_binary:get_map/1`

Tests should not assert an exact tuple field order for data that originated from
an Erlang map.
