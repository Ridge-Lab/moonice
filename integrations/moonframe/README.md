# MoonIce → MoonFrame integration

This separate consumer module combines the published MoonIce reader and
MoonFrame's typed columns. It adds no MoonFrame dependency to the core library
and is not a separate package submission. It is a maintainer-authored example,
not an endorsement or external adoption by MoonFrame.

From this directory:

```sh
moon update
moon run --target js .
```

The standard delete fixture has five physical rows. MoonIce removes three;
MoonFrame receives two rows (IDs 2 and 4), and its column sum is 6. Passing all
five physical rows to an analytics library would include deleted records.
Int64 values and nulls are transferred through typed Series; the program also
checks `9007199254740993` survives unchanged.

The adapter is specific to the fixture's `id` and `category` fields. It collects
the visible rows for a DataFrame; it is not a streaming DataFrame adapter or
a conversion for every Iceberg type. Example dependency:
[MoonFrame 0.8.1](https://github.com/ihb2032/MoonFrame), Apache-2.0.

## Backend boundary

MoonIce 0.3.2 uses `mizchi/parquet@0.2.2`, `moonbitlang/x@0.5.7`,
MoonFrame 0.8.1 and NyaCSV 0.3.4 with `moonc v0.10.20+65efd5b93`.
It uses public `Series::from_scalars` to retain typed Int64/null values.
MoonFrame 0.8.1 uses the gzip package supplied by this SDK. For SDK 0.10.16,
check out MoonIce v0.3.0, whose example pins MoonFrame 0.8.0.
CI exercises the pinned integration on Linux JS/Wasm/Wasm GC/native and Windows
JS/native. Completed results belong in the [version verification record](../../docs/ACCEPTANCE.md).

Normal use resolves MoonIce from Mooncakes. To test unpublished local changes,
run `moon work init . ../..` in this directory; remove that generated `moon.work`
before testing the published package. CI explicitly uses the source workspace.
