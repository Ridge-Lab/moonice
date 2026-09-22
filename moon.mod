// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "Ridge-Lab/moonice"

version = "0.2.0"

readme = "README.md"

repository = "https://github.com/Ridge-Lab/moonice"

license = "Apache-2.0"

keywords = [ "iceberg", "snapshot", "data-lake", "scan-planning" ]

preferred_target = "wasm"

description = "MoonBit-native Iceberg v2 reading with partition evolution, delete semantics and explainable scan planning."

import {
  "mizchi/parquet@0.2.1",
  "yugonlian/moon-avro@0.3.0",
  "moonbitlang/x@0.4.40",
}
