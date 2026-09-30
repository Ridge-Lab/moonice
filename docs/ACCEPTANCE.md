# MoonIce 0.2.1 版本验证记录

核对日期：2026-09-30。本文记录实现范围、复现命令与实际发布验证结果。

仓库：[https://github.com/Ridge-Lab/moonice](https://github.com/Ridge-Lab/moonice)

## 技术验证概览

| 验证项目 | 可核查证据 |
|---|---|
| 主要实现语言及版本 | 核心、CLI 和浏览器桥接均为 MoonBit；`moonc v0.10.14+7d59c7ec9`，CI 固定同版 core |
| 公开仓库与版本历史 | 公开仓库、真实功能提交、CHANGELOG 和版本标签 |
| 源码结构及核心功能 | 快照、清单、规划、位置/等值删除、ID 投影、分区演进、批次读取、诊断与差异；结构见 README |
| 安装及复现文档 | [README](../README.md)含库安装、指定版本克隆、编译及样例预期；[API 文档](../README.mbt.md)参与测试 |
| 持续集成 | [workflow](../.github/workflows/ci.yml)执行格式、检查、测试、release 构建；四后端核心及 MoonFrame 接入、网页构建与部署 |
| 可运行示例 | `examples/library_read`、`examples/batch_read`、`integrations/moonframe`、[浏览器工作台](https://ridge-lab.github.io/moonice/) |
| 核心测试 | 45 项测试，含独立格式样本、精度及序列边界、保守裁剪、回调与错误传播；详见 [VALIDATION](VALIDATION.md) |
| 注册表分发 | `Ridge-Lab/moonice`；具体版本及独立消费者验证记录见下 |
| 许可证及来源 | [Apache-2.0](../LICENSE)、[来源说明](PROVENANCE.md)、[第三方组件](../THIRD_PARTY.md) |

## 复现顺序

安装 README 指定的工具链后，在仓库根目录运行：

```sh
moon version --all
moon update
moon check --target all --deny-warn
moon test --target js --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target native --deny-warn
moon build --target all --release
moon run --target js examples/library_read
moon run --target js examples/batch_read
```

native 需要 C 编译器；Linux CI 安装环境可见 workflow。库示例预期分别为物理 5 行、删除 3 行、可见 2 行，以及两种分区规格、两批两行、ID 合计 21。在 `integrations/moonframe` 中运行 `moon run --target js .`，预期 DataFrame 两行、合计 6，且大整数与空值断言通过。

## 实现范围

项目复用 Avro/Parquet 解码库，独立实现上层表语义；没有将依赖源码计作本项目贡献。完整性对应[公开兼容范围](COMPATIBILITY.md)：只读、有界、平面基本类型；无 catalog/S3 客户端、事务写入、嵌套/decimal/UUID 行执行和 Parquet range read。NONE/Snappy 已验证，Gzip/Zstd 明确报错。

代码与技术文档使用 AI 辅助开发，维护者负责审查、验证和维护。没有外部采用、背书或性能优势的未经验证声明。

## 发布验证

- [CI 36724785284](https://github.com/Ridge-Lab/moonice/actions/runs/36724785284)：提交 `8a06849`，moonc `0.10.14+7d59c7ec9`；JS、Wasm、Wasm GC、Linux native 各通过 45 项测试，格式、检查、release 构建、CLI 和库示例通过。四组 MoonFrame 接入、网页构建及部署全部成功。
- `moon publish` 对生成的归档解压检查通过后返回 `200 OK`。[Mooncakes 0.2.1](https://mooncakes.io/docs/Ridge-Lab/moonice@0.2.1/) 已发布。
- 独立消费者仅声明 Mooncakes 版本依赖，没有 path/workspace 替换。实际解析到 MoonIce 0.2.1、Parquet 0.2.2、x 0.5.5：JS/Wasm/Wasm GC 的 MoonFrame 示例均返回两行、合计 6，精确 Int64 和空值断言通过；Wasm 批次示例返回两批两行、合计 21；JS 库读取示例返回物理 5 行、删除 3 行、可见 2 行。
- 已检查部署后的 0.2.1 工作台：订单筛选得到 ID 10、11；删除样本得到 ID 4、2；分区样本保留 2 份、裁剪 4 份文件并返回 2 行；缺失文件样本返回完整 `MISSING_FILE` 路径，清除旧行结果和统计值。
- 独立 Node.js CLI 使用 `.mjs`，支持新版 x 生成的 ES Module；已运行帮助和删除样本。发布资产、源码及 SHA-256 校验见 [GitHub Release](https://github.com/Ridge-Lab/moonice/releases/tag/v0.2.1)。Mooncakes 模块归档保持首次发布字节；发布后补充的验证记录以本仓库文档为准。
