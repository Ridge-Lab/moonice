# Development priorities

The 0.1.0 delivery is a working base for further review and real use. Competition ranking is not guaranteed.

1. Obtain an independently provided real Iceberg v2 diagnostic sample and reproduce one user-reported problem. Record consent and actual feedback; do not manufacture endorsements.
2. Extend the differential corpus to identity/bucket/day partition evolution, schema removal/reuse safeguards, more Parquet encodings and delete combinations. Add support only alongside test evidence.
3. Replace materialization with bounded streaming/range reads, then benchmark memory and latency on published synthetic datasets and fixed hardware.
4. Add an object-store/catalog adapter as a separate integration using the existing storage callback. Keep Iceberg semantics in the library and credentials outside table metadata.
5. Address upstream dependency limitations through small attributable contributions rather than copying their implementation into this project.

The maintainer should be able to explain the complete three-snapshot fixture, the equality-delete sequence boundary, the conservative pruning rule and the field-ID projection before presenting the project. The competition application must be written personally when the rules prohibit AI-written applications; technical documentation here is not a substitute submission.
