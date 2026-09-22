# MoonIce 0.2.0 版本验证记录

核对日期：2026-09-22。本文记录版本的实现范围、复现步骤与发布验证结果。

仓库：[https://github.com/Ridge-Lab/moonice](https://github.com/Ridge-Lab/moonice)

## 技术验证概览

| 验证项目 | 可核查证据 |
|---|---|
| 主要功能由 MoonBit 实现 | 根目录 `.mbt`、`bridge/`、`cmd/`；Python 仅作独立参考数据生成 |
| 版本历史 | 本仓库 Git 历史、版本标签与 CHANGELOG.md |
| 核心功能可运行 | 快照、清单、文件规划、位置/等值删除、ID 投影、分区演进、批次读取、诊断与差异 |
| README 可复现 | [运行步骤](../README.md)、[可执行 API 文档](../README.mbt.md)、固定依赖与冻结样本 |
| CI 检查、构建、测试 | [workflow](../.github/workflows/ci.yml)：JS/Wasm/Wasm GC/native；另跑 MoonFrame 接入及网页构建 |
| 可运行示例 | `examples/library_read`、`examples/batch_read`、`integrations/moonframe`、网页四组演示 |
| 核心测试 | 45 项测试，含 PyIceberg/PyArrow 对照、序列边界、保守裁剪、回调与错误传播 |
| Mooncakes 发布 | 发布结果及消费者下载验证见本文件的发布记录 |
| 开源许可证与来源 | Apache-2.0；[来源说明](PROVENANCE.md)、[第三方组件](../THIRD_PARTY.md) |

## 建议现场验证顺序

1. `moon update` 后运行 `moon check --target all --deny-warn`、`moon test --target js --deny-warn`。
2. `moon run --target js examples/library_read`：物理 5 行、删除 3 行、可见 2 行；同序列新数据不被等值删除误删。
3. `moon run --target js examples/batch_read`：两种分区规格共存，最终两批两行、ID 合计 21。
4. 在 `integrations/moonframe` 目录运行 `moon run --target js .`：DataFrame 两行、合计 6，验证精确 Int64。
5. 打开[工作台](https://ridge-lab.github.io/moonice/)，依次选“分区演进”“删除语义”“缺失文件”。正常样本返回可解释结果；缺失样本返回对象路径并清除旧结果。

## 实现范围与贡献边界

这是独立实现的表语义层，复用已有 Avro/Parquet 解码库。可以回答“MoonBit 工具怎样得到某个 Iceberg 快照删除后的有效数据，并解释为何读这些文件”。[生态定位](ECOSYSTEM.md)列出实际依赖、可运行下游接入、替代路径和最新目录检索。

功能完整性仅指[公开兼容范围](COMPATIBILITY.md)，不宣称完整 Iceberg SDK：只读、有界、平面基本类型；无 catalog/S3 客户端、事务写入、嵌套/decimal/UUID 行执行和 Parquet range read。NONE/Snappy 已验证，Gzip/Zstd 明确报错。

代码与技术文档使用 AI 辅助开发，维护者负责审查、验证和维护。来源说明与测量结果公开；未声称已获外部采用、第三方背书或性能优势。

## 发布记录

- [CI 35725800115](https://github.com/Ridge-Lab/moonice/actions/runs/35725800115)：提交 `b3c399e` 的 JS、Wasm、Wasm GC、Linux native 四组检查/45 项测试/release 构建全部成功；CLI、两个库示例、JS MoonFrame 接入、网页构建与部署成功。
- `moon publish` 返回 HTTP 200；[Mooncakes 0.2.0](https://mooncakes.io/docs/Ridge-Lab/moonice@0.2.0/) 已通过独立消费者实际下载验证。消费者只有版本依赖，没有本地 path/workspace 替换。
- 注册表包的独立 JS MoonFrame 接入：物理 5 行、删除 3 行、DataFrame 2 行、合计 6，精确大整数检查通过；独立核心消费者的 Wasm 批次示例：两种规格、两批两行、合计 21。
- 下游组合限制：MoonFrame 示例只验证 JS。它引入的 x 0.4.47 与 Parquet 0.2.1 的默认文件接口在 Wasm 下冲突，见[说明](../integrations/moonframe/README.md#backend-boundary)。这不影响核心自己的四后端 CI 结果。
- [GitHub 0.2.0 发布页](https://github.com/Ridge-Lab/moonice/releases/tag/v0.2.0)提供源码、CLI、网页、模块归档与 SHA-256 校验文件。Mooncakes 模块归档保持发布时字节不变；发布后补充的证据和限制以本仓库文档为准。
