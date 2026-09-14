# Implementation and provenance

MoonIce is an independent implementation of a bounded Apache Iceberg v2 read
and inspection surface. The authoritative format reference is the
[Apache Iceberg specification](https://iceberg.apache.org/spec/).

The implementation is developed with AI assistance. Generated changes are
compiled and tested, and limitations and measured results are recorded in the
repository. AI assistance must not be represented as unassisted human authorship.
The entrant remains responsible for reviewing, understanding and maintaining the
submitted work. The competition application prose is not generated here.

## Dependencies

- `yugonlian/moon-avro@0.3.0`, Apache-2.0: Avro binary and OCF decoding.
  <https://github.com/yugonlian/moon-avro>
- `mizchi/parquet@0.2.1`, Apache-2.0: Parquet data-page decoding.
  <https://github.com/mizchi/parquet>
- MoonBit standard library, Apache-2.0.

These remain dependencies, rather than being presented as MoonIce implementation
work. Their transitive dependencies and licenses remain applicable.

## Reference data

Reference fixtures are synthetic data produced by Apache PyIceberg and PyArrow.
The generator and its pinned dependencies are included for reproducibility.
They do not contain personal or production data. Reference comparison programs
use Python because they execute the independent PyIceberg/PyArrow implementation;
MoonIce's table semantics and scan planning are implemented in MoonBit.

No production adoption, external endorsement, benchmark advantage or award is
claimed without corresponding evidence.
