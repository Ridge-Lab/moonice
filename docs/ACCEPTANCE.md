# MoonIce 0.2.0 验收证据

核对日期：2026-09-22。本文是项目自检与技术证据，不代表赛事组已验收。

仓库：[https://github.com/Ridge-Lab/moonice](https://github.com/Ridge-Lab/moonice)

## 对应正式章程

依据官网链接的[九月黑客松章程](https://bxup9uklfcb.feishu.cn/wiki/Dx4Bwd6D1i3GfHkajQCcF7SznEd)。9 月 22 日读取时，正式章程申报与验收时间为 **9 月 24 日**；官网宣传页仍显示 9 月 30 日，实际应按组委会最新通知确认，准备工作按较早日期执行。

| 验收项目 | 可核查证据 |
|---|---|
| 主要功能由 MoonBit 实现 | 根目录 `.mbt`、`bridge/`、`cmd/`；Python 仅作独立参考数据生成 |
| 公开仓库和真实提交记录 | 本仓库 Git 历史；0.1.0 已有超过十次开发提交，本次不以拆分提交凑数 |
| 核心功能可运行 | 快照、清单、文件规划、位置/等值删除、ID 投影、分区演进、批次读取、诊断与差异 |
| README 可复现 | [运行步骤](../README.md)、[可执行 API 文档](../README.mbt.md)、固定依赖与冻结样本 |
| CI 检查、构建、测试 | [workflow](../.github/workflows/ci.yml)：JS/Wasm/Wasm GC/native；另跑 MoonFrame 接入及网页构建 |
| 至少一个示例 | `examples/library_read`、`examples/batch_read`、`integrations/moonframe`、网页四组演示 |
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

代码与技术文档使用 AI 辅助开发。参赛者仍须亲自理解、审查、答辩和维护。当前正式章程要求申报书人工撰写、一页 Markdown；本技术报告不能代替该申报正文。没有伪造客户采用、第三方背书、性能倍数或有效提交。

## 发布记录

本地 45 项测试已分别通过 JS/Wasm/Wasm GC。四后端远端 CI、0.2.0 发布地址和独立下载验证结果将在发布完成后补入此处。
