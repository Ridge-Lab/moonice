# MoonIce

**MoonBit 原生的 Apache Iceberg v2 快照检查、可解释扫描规划与有界读取工具。**

从标准 `metadata.json → manifest list → manifest → Parquet` 追踪一次读取：哪些文件参与扫描、哪些被排除、为什么删除文件会影响某些数据、字段改名后旧文件如何读取。核心表语义使用 MoonBit 实现；命令行和浏览器工作台共用同一套 API。

这是可运行的 **0.1.0 有界实现**。支持范围见 [兼容性说明](docs/COMPATIBILITY.md)，不代表完整 Iceberg 引擎或生产级数据湖服务。

[在线体验](https://ridge-lab.github.io/moonice/) · [构建与测试记录](https://github.com/Ridge-Lab/moonice/actions/workflows/ci.yml) · [API 示例](README.mbt.md)

## 五分钟运行

需要 MoonBit（本地验证：`moonc v0.10.8+8606a5800`）、Node.js。Python 仅用于可选的参考数据生成和本地静态文件服务。

```sh
moon update
moon check --target all --deny-warn
moon test --target wasm
moon test --target js
moon test --target wasm-gc
moon run --target js cmd/main -- scan fixtures/events.icebundle.json --filter-file fixtures/id-ge-10.filter.json
```

最后一条命令返回 `id=10,11`，并说明另一个数据文件为什么被上界统计排除。所有 64 位整数在 JSON 输出中使用十进制字符串。

启动浏览器工作台：

```sh
npm run build
python -m http.server 8765 --bind 127.0.0.1 --directory web
```

打开 <http://127.0.0.1:8765>。页面提供订单演进、删除语义、缺失清单三个演示，也支持导入自己的离线数据包。没有服务器端数据处理或上传接口。扫描在 Web Worker 内运行。

## 可复现的使用场景

1. **定位扫描成本。** 选择订单当前快照，设置 `id >= 10`。MoonIce 解析真实 Avro 清单，从两份数据文件中排除一份，并展示排除依据、保留字节数和最终两条记录。统计缺失时保留文件，避免误裁剪。
2. **核对删除后的结果。** 打开“删除语义”：旧文件 4 行、新文件 1 行。位置删除移除旧文件第 0 行，等值删除匹配 `category=b` 和空值。新文件与等值删除处于同一数据序列，因此其 `id=2` 保留；最终剩 2 行。界面逐对解释删除关联。
3. **排查不完整的快照导出。** 打开“缺失文件”，模拟当前快照清单遗失。扫描返回带对象路径的 `MISSING_FILE`；诊断继续检查其他快照，且不会在引用遍历不完整时把未知对象当作可安全清理的文件。
4. **核对字段演进与重写。** 在订单第一代与当前快照之间切换：`city` 改名为 `region`，字段 ID 仍为 2；新字段 `note` 在旧文件中补空值。快照差异展示物理文件的替换，区分重写文件数量和逻辑数据变化。

## 命令行

```sh
moon run --target js cmd/main -- inspect fixtures/events.icebundle.json
moon run --target js cmd/main -- plan fixtures/events.icebundle.json --filter-file fixtures/id-ge-10.filter.json
moon run --target js cmd/main -- scan fixtures/deletes.icebundle.json --limit 100
moon run --target js cmd/main -- check fixtures/events.icebundle.json
moon run --target js cmd/main -- diff fixtures/events.icebundle.json --from 7153263061864200117
moon run --target js cmd/main -- scan fixtures/events.icebundle.json --snapshot 7153263061864200117
```

示例 ID 对应仓库中冻结的参考数据；重新生成后请用 `inspect` 取得新 ID。`--ref main` 按引用选择快照；`--snapshot` 与 `--ref` 互斥。`--limit` 限制返回行数，计数仍覆盖本次有界扫描，并明确标注截断。退出码：0 成功；1 核心错误或诊断发现错误；2 参数或本地 I/O 错误。

过滤语法为 JSON，不是 SQL：

```json
{"and":[{"field":"id","op":">=","value":"10"},{"field":"region","op":"not_null"}]}
```

支持 `= < <= > >= is_null not_null`、二元 `and/or`、`null`（所有行）。整数参数支持十进制字符串，保留超过 JavaScript 安全整数范围的值。字段名通过所选 schema 绑定到字段 ID；未知字段和类型不匹配会报错。

## 使用自己的标准 Iceberg 文件

MoonIce 库不要求专用数据格式：`load_snapshot(metadata, read_file)` 接收调用方提供的对象读取回调。CLI/网页用 `.icebundle.json` 将**原始标准文件字节**放入一个便于离线传递的 JSON 容器，不转换 Avro/Parquet，也不替换 Iceberg 格式。

准备对象映射文件 `objects.json`，键必须是 metadata/manifest 中的完整原始 URI，值是本地文件路径：

```json
{"s3://example/table/metadata/snap.avro":"./downloaded/snap.avro","s3://example/table/metadata/m0.avro":"./downloaded/m0.avro","s3://example/table/data/a.parquet":"./downloaded/a.parquet"}
```

```sh
moon run --target js cmd/main -- pack metadata.json --objects objects.json --out table.icebundle.json
moon run --target js cmd/main -- check table.icebundle.json
```

文件映射由使用者明确提供，程序不会根据表内 URI 自动访问网络或任意本地文件。`pack` 不覆盖已有输出。metadata 保存为原始字符串，避免外围 JSON 解析器破坏 64 位快照 ID。

## 库 API 与结构

参见 [可运行的 API 示例](README.mbt.md) 和 [公开接口](pkg.generated.mbti)。

| 模块 | 职责 |
|---|---|
| `metadata.mbt`, `types.mbt` | 精确整数、schema、快照与引用校验 |
| `manifests.mbt`, `bundle.mbt` | Avro 互操作、继承序列号、加载有效文件 |
| `predicate.mbt`, `metrics.mbt`, `planner.mbt` | 字段 ID 绑定、保守裁剪、解释依据 |
| `deletes.mbt`, `scanner.mbt` | 删除适用性、位置和等值删除、残余过滤 |
| `parquet_ids.mbt`, `rows.mbt` | 读取 Parquet 字段 ID、稳定投影 |
| `diagnostics.mbt` | 引用诊断、物理快照差异 |
| `request.mbt`, `bridge/`, `cmd/main/`, `web/` | 共用 JSON 接口、CLI 与网页 |

Avro 与 Parquet 的底层解码复用现有 MoonBit 生态库；MoonIce 提供这些格式之上的 Iceberg 表语义，不把依赖代码算作本项目实现。具体来源见 [PROVENANCE](docs/PROVENANCE.md)。

## 验证

仓库包含 PyIceberg 实际生成的三代快照、六组独立扫描参考结果，以及使用 fastavro/PyArrow 写出的删除语义数据。等值删除用规范推导的明确预期值验证；没有声称 PyIceberg 执行了等值删除。

```sh
python -m pip install -r tools/requirements-reference.txt
python tools/reference.py fixtures
python tools/delete_reference.py
moon test --target wasm
moon test --target js
```

生成器会创建新的随机快照 ID/文件名，语义可复现，输出不保证逐字节相同。日常回归直接使用已提交的冻结样本。测试包含精度边界、穷举区间裁剪不漏行、序列号矩阵、空值删除、字段演进、缺失对象和头部不一致等。详见 [验证记录](docs/VALIDATION.md)。

## 开发与贡献

```sh
moon info
moon fmt
moon test --target wasm
```

欢迎提供最小标准 Iceberg 样本和可复现错误。新增支持必须补充独立格式实现产生的数据或规范边界测试，并更新兼容性表。当前尚无外部生产部署或第三方采用的证据，不声称已有这些成果。

许可证：[Apache-2.0](LICENSE)。本项目使用 AI 辅助开发，编译、参考对照和界面操作验证记录均如实列出；参赛者需亲自理解、审查并维护提交成果。
