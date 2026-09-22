# Development priorities

The 0.2.0 delivery adds common partition transforms, day-to-month evolution,
batch delivery, shared delete indexes and a MoonFrame consumer example.
Remaining priorities:

1. Obtain an independently provided real Iceberg v2 diagnostic sample and reproduce one user-reported problem. Record consent and actual feedback; do not manufacture endorsements.
2. Extend the differential corpus beyond the current 201 transform vectors and day/month table to more partitioned delete combinations, schema removal/reuse safeguards and Parquet encodings. Add support only alongside independent test evidence.
3. Replace materialization with bounded streaming/range reads, then benchmark memory and latency on published synthetic datasets and fixed hardware.
4. Add an object-store/catalog adapter as a separate integration using the existing storage callback. Keep Iceberg semantics in the library and credentials outside table metadata.
5. Address upstream dependency limitations through small attributable contributions rather than copying their implementation into this project.

Maintainers should understand the complete three-snapshot fixture, the equality-delete sequence boundary, the conservative pruning rule and field-ID projection when reviewing or extending the implementation.
