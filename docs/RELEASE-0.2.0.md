# MoonIce 0.2.0

MoonBit 原生 Iceberg v2 读取组件。本版补上分区演进和批次 API，并提供可运行的 MoonFrame 接入。

[在线体验](https://ridge-lab.github.io/moonice/) · [验收证据](https://github.com/Ridge-Lab/moonice/blob/main/docs/ACCEPTANCE.md) · [兼容范围](https://github.com/Ridge-Lab/moonice/blob/v0.2.0/docs/COMPATIBILITY.md)

- 支持 bucket、truncate、year/month/day/hour，按各 manifest 的规格处理新旧分区；201 组 PyIceberg 对照值覆盖精度、负时间戳、闰年和 Unicode 边界。
- 新增 `scan_batches` 和 `ScanSummary`：先删除、后过滤，再逐批交付；删除索引在数据文件之间复用。原有 API 保持兼容。
- 新增真实格式的按天→按月分区样本、批次读取示例和 MoonFrame typed Series 接入。后者把五条物理记录还原为两条有效记录，聚合 ID 得到 6。
- 独立样本验证 NONE/Snappy、字典编码、多 row group、空值和 Int64；Gzip/Zstd 明确报不支持。
- 45 项回归测试；四后端检查、测试、release 构建，以及 CLI、批次示例和 JS MoonFrame 接入已通过 [CI](https://github.com/Ridge-Lab/moonice/actions/runs/35725800115)。注册表包已通过独立消费者下载运行验证。

下载 `moonice-cli-0.2.0.zip` 后用 `node moonice.cjs --help`；浏览器包解压后由静态 HTTP 服务提供。`moonice-module-0.2.0.zip` 是 Mooncakes 模块归档；普通 MoonBit 项目可执行 `moon add Ridge-Lab/moonice@0.2.0`。`SHA256SUMS-0.2.0.txt` 提供下载校验值。

范围：有界、只读 Iceberg v2；按整文件解码。无 catalog/S3 客户端、事务写入、nested/decimal/UUID 行执行或完整 Iceberg 认证。没有外部采用或性能领先的声明。Apache-2.0；代码和技术文档使用 AI 辅助开发，来源公开。

MoonFrame 示例只验证 JS；其较新 x 依赖与 Parquet 默认文件接口在 Wasm 下冲突，详见[接入限制](https://github.com/Ridge-Lab/moonice/blob/main/integrations/moonframe/README.md#backend-boundary)。核心四后端使用各自已验证的依赖图。Mooncakes 模块归档保持首次发布字节；后补证据和限制见仓库文档。
