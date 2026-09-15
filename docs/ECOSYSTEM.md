# MoonIce 在 MoonBit 生态中的位置

核查日期：2026-09-15。本文区分已有能力、本项目新增能力和仍待验证的使用需求。

## 要解决的具体问题

读取 Iceberg 表需要在文件解码之外确定快照中的有效文件、应用适用的删除记录，并按字段 ID 处理 schema。单独遍历目录或拼接 Parquet 内容，可能包含历史数据或已删除行。相关规则见 [Iceberg 扫描规划](https://iceberg.apache.org/spec/#scan-planning)和[字段演进说明](https://iceberg.apache.org/docs/latest/evolution/)。

MoonIce 为 MoonBit 应用实现这部分表语义：输入标准元数据及对象读取回调，输出类型化的快照、文件保留/排除决策、删除关联和行数据。底层 Avro、Parquet 解码来自现有生态依赖，来源和许可见 [PROVENANCE](PROVENANCE.md)。

因此，价值主张是减少 MoonBit 数据工具重复实现表规则的工作，并让这些规则的执行过程可检查。不能仅凭“有一个同名空缺”推导项目有必要，也不能将 Iceberg 在其他语言的使用量当成 MoonBit 用户需求。

## 与已有生态能力的关系

| 项目或路径 | 已有职责 | 与 MoonIce 的关系 |
|---|---|---|
| [yugonlian/moon-avro](https://github.com/yugonlian/moon-avro) | Avro schema、数据编解码、OCF 容器 | 实际依赖；MoonIce 在解码结果上解释 manifest 与序列号 |
| [mizchi/parquet](https://github.com/mizchi/parquet) | Parquet 文件读写 | 实际依赖；MoonIce 决定读哪些文件、哪些行可见及字段投影 |
| [ihb2032/MoonFrame](https://github.com/ihb2032/MoonFrame) | 表格数据过滤、聚合和 CSV/JSON 等输入输出 | 潜在下游；目前没有专用适配器，也没有该项目已采用 MoonIce 的证据 |
| [f4ah6o/duckdb](https://github.com/f4ah6o/duckdb.mbt) | MoonBit 调用 native / JS 的 DuckDB 引擎 | 需要 SQL 查询时应比较的替代路径，不是 MoonIce 的必要前置组件 |

[DuckDB 自身已有 Iceberg 扩展](https://duckdb.org/docs/current/core_extensions/iceberg/overview)，支持读取表、查看元数据和快照；其绑定也有浏览器后端。不能声称“MoonBit 没办法访问 Iceberg”或“只有 MoonIce 能在浏览器里处理数据”。本次没有实际运行 DuckDB 绑定加 Iceberg 扩展的组合，不将每个后端的该组合写成已验证支持。

MoonIce 更窄的适用条件是：应用需要直接持有、组合和检查 MoonBit 的表语义对象，并希望核心代码在多个 MoonBit 后端复用，无需在运行时加载外部数据库引擎。若需求只是成熟的 SQL 查询、远程 catalog 或大表读取，应先评估现有引擎；目前没有 MoonIce 更快、更省内存的对比证据。

## 可复现的差别：文件中的行与表中可见的行

在仓库根目录运行：

```sh
moon run --target js examples/library_read
```

[接入示例](../examples/library_read/main.mbt)只调用公开 API。输入是 `fixtures/deletes.icebundle.json`，其中保存原始标准 Avro、Parquet 字节。关键输出：

```text
physical_rows=5
deleted_rows=3
visible_rows=2
```

随后过滤 `id=2`，输出 `{"id":"2","category":"new"}`。旧文件对应记录被删除，同序列新增的数据保留；程序还返回删除关联的 `APPLIES` / `SEQUENCE` 原因。这说明调用方拿到的不只是格式解码结果。

样本由本项目通过独立格式库生成，删除结果按规范推导。它验证可运行行为，不是客户案例，也不是大表性能测试。另有六组 PyIceberg 参考结果验证三个快照的文件集合和行值，见[验证记录](VALIDATION.md)。

## 在另一个 MoonBit 项目中接入

创建普通 MoonBit 项目，执行：

```sh
moon add Ridge-Lab/moonice@0.1.0
moon add moonbitlang/x@0.4.40
```

将本仓库 `examples/library_read/main.mbt` 与 `moon.pkg` 放入该项目的 `main/`，将删除样本放入其 `fixtures/deletes.icebundle.json`，在新项目根目录运行：

```sh
moon run --target js main
moon run --target wasm main
```

这条路径使用已发布的库。应用可以替换 `read` 回调，从自己的对象映射返回字节，保留 `load_snapshot → plan_scan → plan_deletes / scan_rows` 调用顺序。回调目前是同步整对象读取；远程客户端、异步读取和 range read 均未实现。

## 查重证据及局限

从 [Mooncakes 官方模块目录](https://mooncakes.io/api/v0/modules)读取到 2,487 个模块。按名称、描述、关键词检查 Iceberg、数据湖及相邻格式能力，相关条目和检索表达式记录在 [registry-2026-09-15.json](evidence/registry-2026-09-15.json)。官方搜索的 `iceberg` 结果仅返回 `Ridge-Lab/moonice`；GitHub `iceberg language:MoonBit` 仓库检索也仅返回本项目。

结论限于：本次元数据检索未发现另一个直接同类的 MoonBit 库，已有相邻库和外部引擎路径需要明确区分。这不是对全部源代码的相似度审计，不覆盖未公开、未发布、缺少关键词的实现，也不证明不存在替代品。

## 还缺少什么

现在能提供库接口、发布包、四后端回归结果、网页/CLI 和接入示例。尚无独立用户采用、外部提供的真实故障样本、生产规模数据或性能优势证据；本项目自行运行消费者示例，不能算外部采用。

下一阶段应优先验证一项具体需求：由真实 MoonBit 数据工具作者提供希望完成的读取或诊断任务，在得到授权的数据上接入，记录原有做法、需要补写的逻辑、实际输出及未解决的问题。需求被证实后再扩展分区演进、编码兼容或存储适配，不以增加功能名、测试数量或提交数量代替用户价值。

当前完整边界见 [COMPATIBILITY](COMPATIBILITY.md)：这是支持部分 Iceberg v2 场景的有界诊断读取库，不是完整 Iceberg SDK。
