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
[MoonFrame 0.6.0](https://github.com/ihb2032/MoonFrame), Apache-2.0.
