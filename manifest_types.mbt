///|
pub(all) enum Scalar {
  Missing
  Boolean(Bool)
  Integer(Int64)
  Real(Double)
  Text(String)
  Binary(Bytes)
} derive(Debug, Eq, ToJson)

///|
pub(all) struct Manifest {
  path : String
  length : Int64
  spec_id : Int32
  content : Int32
  sequence_number : Int64
  min_sequence_number : Int64
  added_snapshot_id : Int64
} derive(Debug, Eq, ToJson)

///|
/// File content: 0=data, 1=position deletes, 2=equality deletes.
pub(all) struct DataFile {
  content : Int32
  path : String
  format : String
  partition : Map[String, Scalar]
  record_count : Int64
  size_bytes : Int64
  lower_bounds : Map[Int32, Bytes]
  upper_bounds : Map[Int32, Bytes]
  null_counts : Map[Int32, Int64]
  nan_counts : Map[Int32, Int64]
  equality_ids : Array[Int32]
} derive(Debug, Eq, ToJson)

///|
/// Status: 0=existing, 1=added, 2=deleted. Sequence inheritance is resolved.
pub(all) struct ManifestEntry {
  manifest_path : String
  spec_id : Int32
  status : Int32
  snapshot_id : Int64
  sequence_number : Int64
  file_sequence_number : Int64
  file : DataFile
} derive(Debug, Eq, ToJson)
