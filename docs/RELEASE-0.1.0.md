# MoonIce 0.1.0

MoonBit 原生的 Iceberg v2 快照检查、可解释扫描规划与有界读取。

[在线体验](https://ridge-lab.github.io/moonice/) · [运行说明](https://github.com/Ridge-Lab/moonice#五分钟运行)

本版包含：

- 标准 metadata / Avro manifest list / manifest / Parquet 读取链路，精确保留 64 位 ID。
- 带依据的统计与 identity 分区裁剪，缺少排除证据时保留文件。
- 数据序列和分区约束下的位置删除、等值删除，以及残余过滤。
- 按字段 ID 读取旧文件、处理字段改名和可空字段新增。
- 缺失引用诊断、物理快照差异、CLI、离线文件打包、浏览器工作台。
- 三代 PyIceberg 快照和六组独立参考扫描；规范驱动的删除语义样本。

31 项测试已在 Wasm、Wasm GC、JavaScript、Linux native 通过。
GitHub Actions 同时构建并运行 JS/native 命令行，再部署网页。
验证证据和曾出现的原生接口兼容问题见 [VALIDATION](VALIDATION.md)。

下载包：源码保留在 GitHub；`moonice-web-0.1.0.zip` 可解压后用静态 HTTP
服务运行；`moonice-cli-0.1.0.zip` 可用 Node.js 执行 `node moonice.mjs --help`。
浏览器包包含合成演示数据；自行导入的数据仅在本地浏览器处理。

本版面向有界诊断样本：不支持表写入、REST catalog / S3 网络客户端、
流式大表扫描、nested/decimal/UUID 行投影或完整格式认证。详见
[COMPATIBILITY](COMPATIBILITY.md)。没有生产采用、性能领先或获奖保证。

Apache-2.0。使用 AI 辅助开发并公开来源；本说明不是赛事申报书。
