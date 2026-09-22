const $ = (id) => document.getElementById(id);
const escape = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const fileName = (path) => String(path).split("/").at(-1);
const size = (n) => {
  n = Number(n);
  return n < 1024
    ? `${n} B`
    : n < 1048576
      ? `${(n / 1024).toFixed(1)} KB`
      : `${(n / 1048576).toFixed(1)} MB`;
};
const date = (n) =>
  new Date(Number(n)).toLocaleString("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
const worker = new Worker(new URL("./worker.js", import.meta.url), {
  type: "module",
});
let requestId = 0,
  metadata,
  selected = "",
  source = "",
  lastReport,
  busy = false;
const pending = new Map();
worker.onmessage = ({ data }) => {
  const item = pending.get(data.id);
  if (!item) return;
  clearTimeout(item.timeout);
  pending.delete(data.id);
  $("timing").textContent = `MoonBit 核心 · ${data.milliseconds.toFixed(1)} ms`;
  data.payload.ok
    ? item.resolve(data.payload.result)
    : item.reject(data.payload.error);
};
worker.onerror = (event) => {
  for (const item of pending.values()) {
    clearTimeout(item.timeout);
    item.reject({ code: "WORKER_START", message: event.message });
  }
  pending.clear();
  status("核心未能启动，请先执行 npm run build，并通过 HTTP 打开网页。", true);
};
function call(options, bundle) {
  return new Promise((resolve, reject) => {
    const id = ++requestId;
    const timeout = setTimeout(() => {
      pending.delete(id);
      reject({
        code: "TIMEOUT",
        message: "处理超过 30 秒。请重新加载页面并使用较小的数据包。",
      });
    }, 30000);
    pending.set(id, { resolve, reject, timeout });
    worker.postMessage({ id, bundle, options });
  });
}
function status(message, error = false) {
  $("status").textContent = message;
  $("status").classList.toggle("error", error);
}
function failure(error) {
  status(
    `${error.code || "ERROR"} · ${error.path || ""} ${error.message || String(error)}`,
    true,
  );
}
function controls(disabled) {
  busy = disabled;
  document
    .querySelectorAll("button,select,input")
    .forEach((x) => (x.disabled = disabled));
}
async function task(fn) {
  if (busy) return;
  controls(true);
  try {
    await fn();
  } catch (e) {
    failure(e);
  } finally {
    controls(false);
  }
}
function timeline() {
  $("timeline").innerHTML =
    metadata.snapshots
      .map(
        (s, i) =>
          `<button class="snapshot ${selected === s.id ? "selected" : ""}" data-snapshot="${escape(s.id)}"><span class="snap-top"><b>快照 ${String(i + 1).padStart(2, "0")}</b><span class="tag">${escape(s.operation.toUpperCase())}</span></span><code>${escape(s.id)}</code><small>${date(s.timestamp_ms)} · 序列 ${escape(s.sequence_number)}${s.id === metadata.current_snapshot_id ? " · 当前" : ""}</small></button>`,
      )
      .join("") || '<div class="empty">空表尚无快照</div>';
  $("table-location").textContent = metadata.location;
  document.querySelectorAll("[data-snapshot]").forEach(
    (button) =>
      (button.onclick = () =>
        task(async () => {
          selected = button.dataset.snapshot;
          timeline();
          await loadSchema();
          await scan();
        })),
  );
}
function options(action) {
  return {
    action,
    ...(selected !== metadata.current_snapshot_id
      ? { snapshot: selected }
      : {}),
  };
}
async function loadSchema() {
  const snapshot = metadata.snapshots.find((s) => s.id === selected);
  const schema =
    metadata.schemas.find(
      (s) =>
        s.id ===
        (selected === metadata.current_snapshot_id
          ? metadata.current_schema_id
          : snapshot?.schema_id),
    ) || metadata.schemas.find((s) => s.id === metadata.current_schema_id);
  const old = $("field").value;
  $("field").innerHTML = schema.fields
    .map(
      (f) =>
        `<option value="${escape(f.name)}" data-type="${escape(f.field_type)}">${escape(f.name)} · #${f.id}</option>`,
    )
    .join("");
  if (schema.fields.some((f) => f.name === old)) $("field").value = old;
}
function predicate() {
  const op = $("operator").value;
  if (op === "all") return null;
  const field = $("field").value;
  if (op === "is_null" || op === "not_null") return { field, op };
  const type = $("field").selectedOptions[0]?.dataset.type;
  const input = $("literal").value;
  let value = input;
  if (["float", "double"].includes(type)) {
    value = Number(input);
    if (!input.trim() || !Number.isFinite(value))
      throw { code: "FILTER_VALUE", message: "请输入有限数值。" };
  } else if (type === "boolean") {
    if (!["true", "false"].includes(input))
      throw { code: "FILTER_VALUE", message: "布尔值请输入 true 或 false。" };
    value = input === "true";
  } else if (type !== "string" && !/^-?\d+$/.test(input))
    throw { code: "FILTER_VALUE", message: "整数条件请输入完整十进制数。" };
  return { field, op, value };
}
const translations = {
  MAY_MATCH: "现有分区和统计值不足以排除此文件，保留并逐行过滤。",
  EMPTY_FILE: "文件记录数为 0。",
};
function reason(d) {
  return (
    translations[d.reason_code] ||
    (d.explanation.includes("upper bound")
      ? "字段最大值低于条件边界，文件中没有匹配记录。"
      : d.explanation.includes("lower bound")
        ? "字段最小值高于条件边界，文件中没有匹配记录。"
        : d.explanation.includes("null_count = 0")
          ? "空值计数为 0，无法满足为空条件。"
          : d.explanation.includes("every row is null")
            ? "该字段全部为空，无法满足当前条件。"
            : d.explanation)
  );
}
async function scan() {
  if (!selected) {
    status("该表没有快照，可使用引用诊断查看元数据。");
    return;
  }
  status("正在解析清单并执行扫描…");
  const opts = { ...options("scan"), filter: predicate(), limit: 1000 };
  let report;
  try {
    report = await call(opts);
  } catch (e) {
    clearResults();
    await check();
    throw e;
  }
  lastReport = report;
  const decisions = report.plan.decisions,
    kept = decisions.filter((d) => d.kept).length,
    pruned = decisions.length - kept;
  const cards = [
    ["保留文件", kept, `${size(report.plan.retained_bytes)} 待读取`],
    ["裁剪文件", pruned, `${size(report.plan.pruned_bytes)} 已跳过`],
    ["删除行数", report.scan.deleted_rows, "物理读取后应用"],
    ["匹配记录", report.scan.matched_rows, `${report.scan.read_rows} 行已读取`],
  ];
  $("metrics").innerHTML = cards
    .map(
      ([name, value, note]) =>
        `<article><span>${name}</span><strong>${value}</strong><small>${note}</small></article>`,
    )
    .join("");
  $("plan-summary").textContent =
    `${report.manifests.length} 个清单 · ${decisions.length} 个数据文件`;
  $("files").innerHTML =
    decisions
      .map(
        (d) =>
          `<tr><td><span class="path" title="${escape(d.entry.file.path)}">${escape(fileName(d.entry.file.path))}</span><span class="subpath">${escape(d.entry.file.path)}</span></td><td>${escape(d.entry.file.record_count)}</td><td>${size(d.entry.file.size_bytes)}</td><td><span class="pill ${d.kept ? "" : "pruned"}">${d.kept ? "保留" : "裁剪"}</span></td><td class="reason" title="${escape(d.explanation)}"><b>${escape(d.reason_code)}</b>${escape(reason(d))}</td></tr>`,
      )
      .join("") ||
    '<tr><td colspan="5" class="empty">此快照没有数据文件</td></tr>';
  $("row-summary").textContent =
    `${report.scan.rows.length} 条${report.scan.truncated ? " · 已截断" : ""}`;
  $("rows").innerHTML = report.scan.rows.length
    ? `<table><thead><tr>${report.schema.fields.map((f) => `<th>${escape(f.name)}</th>`).join("")}<th>源文件行号</th></tr></thead><tbody>${report.scan.rows.map((r) => `<tr>${report.schema.fields.map((f) => `<td>${r.values[f.name] === null ? '<span class="null">NULL</span>' : escape(typeof r.values[f.name] === "object" ? JSON.stringify(r.values[f.name]) : r.values[f.name])}</td>`).join("")}<td title="${escape(r.file)}">${escape(r.position)}</td></tr>`).join("")}</tbody></table>`
    : '<div class="empty">没有符合条件的记录</div>';
  $("schema-id").textContent = `Schema #${report.schema.id}`;
  $("schema").innerHTML = report.schema.fields
    .map(
      (f) =>
        `<div class="field-row"><code>#${f.id}</code><span>${escape(f.name)}</span><small>${escape(typeof f.field_type === "string" ? f.field_type : JSON.stringify(f.field_type))} · ${f.required ? "必填" : "可空"}</small></div>`,
    )
    .join("");
  $("delete-panel").hidden = !report.deletes.length;
  $("delete-rows").innerHTML = report.deletes
    .map(
      (d) =>
        `<tr><td>${escape(fileName(d.data_path))}</td><td>${escape(fileName(d.delete_path))}</td><td><span class="pill ${d.applies ? "" : "pruned"}">${d.applies ? "适用" : "不适用"}</span></td><td class="reason">${escape(d.reason_code === "SEQUENCE" ? "等值删除只影响更早序列的数据，不删除同序列新写入的数据。" : d.explanation)}</td></tr>`,
    )
    .join("");
  const index = metadata.snapshots.findIndex((s) => s.id === selected);
  if (index > 0) {
    const diff = await call({
      ...options("diff"),
      from: metadata.snapshots[index - 1].id,
    });
    $("diff").textContent =
      `相对上一快照：新增 ${diff.added.length} 个文件，移除 ${diff.removed.length} 个文件。${diff.schema_changes.map((c) => `字段 #${c.field_id} ${c.kind === "renamed" ? `${c.before.name} → ${c.after.name}` : c.kind === "added" ? "新增 " + c.after.name : c.kind}`).join("；")} 这是物理文件变化，不等同于逻辑行增删。`;
  } else
    $("diff").textContent = "这是最早保留的快照。字段 ID 在改名后保持稳定。";
  await check();
  status("扫描完成 · 所有结果由 MoonBit 核心计算，数据未上传。");
}
function clearResults() {
  lastReport = undefined;
  $("files").innerHTML = "";
  $("rows").innerHTML = '<div class="empty">等待有效扫描结果</div>';
  $("schema").innerHTML = "";
  $("diff").textContent = "";
  $("plan-summary").textContent = "";
  $("row-summary").textContent = "";
  $("schema-id").textContent = "";
  $("delete-panel").hidden = true;
  $("metrics")
    .querySelectorAll("strong")
    .forEach((n) => (n.textContent = "—"));
  $("metrics")
    .querySelectorAll("small")
    .forEach((n) => (n.textContent = ""));
}
async function check() {
  const result = await call({ action: "check" });
  $("findings").innerHTML = result.findings.length
    ? result.findings
        .map(
          (f) =>
            `<div class="finding ${escape(f.severity)}"><strong>${f.severity === "error" ? "错误" : f.severity === "warning" ? "提示" : "信息"}</strong><div><b>${escape(f.code)}</b><p>${escape(f.explanation)}</p><code>${escape(f.path)}</code></div></div>`,
        )
        .join("")
    : `<div class="finding"><strong>通过</strong><div>已检查 ${result.checked_snapshots} 个快照、${result.checked_objects} 个引用对象，未发现引用缺失或大小异常。</div></div>`;
}
async function load(text, name, field) {
  source = text;
  selected = "";
  clearResults();
  metadata = await call({ action: "inspect" }, source);
  selected = metadata.current_snapshot_id || "";
  $("source-name").textContent = name;
  timeline();
  await loadSchema();
  if (field) $("field").value = field;
  await scan();
}
async function demo(name) {
  const type = ["deletes", "partitioned"].includes(name) ? name : "events";
  const response = await fetch(`./${type}.icebundle.json`);
  if (!response.ok)
    throw {
      code: "DEMO_MISSING",
      message: "示例未准备好，请执行 npm run build。",
    };
  let text = await response.text();
  if (name === "broken") {
    const b = JSON.parse(text);
    const metadataResponse = await call({ action: "inspect" }, text);
    const latest = metadataResponse.snapshots.find(
      (s) => s.id === metadataResponse.current_snapshot_id,
    );
    delete b.files[latest.manifest_list];
    text = JSON.stringify(b);
  }
  $("operator").value = ["events", "partitioned"].includes(name) ? ">=" : "all";
  $("literal").value = name === "partitioned" ? "1709251200000000" : "10";
  document
    .querySelectorAll("[data-demo]")
    .forEach((x) => x.classList.toggle("active", x.dataset.demo === name));
  await load(
    text,
    name === "events"
      ? "PyIceberg 真实生成 · 3 个快照"
      : name === "deletes"
        ? "标准 Avro / Parquet · 位置与等值删除"
        : name === "partitioned"
          ? "按天 → 按月分区 · ts 为 Unix 微秒 · 筛选 2024-03-01 及之后"
          : "故障注入 · 当前快照清单缺失",
    name === "partitioned" ? "ts" : "id",
  );
}
document
  .querySelectorAll("[data-demo]")
  .forEach((b) => (b.onclick = () => task(() => demo(b.dataset.demo))));
$("run").onclick = () => task(scan);
$("check").onclick = () => task(check);
$("upload-button").onclick = () => $("upload").click();
$("upload").onchange = () =>
  task(async () => {
    const file = $("upload").files[0];
    if (!file) return;
    if (file.size > 128 * 1024 * 1024)
      throw { code: "RESOURCE_LIMIT", message: "数据包最大 128 MiB。" };
    document
      .querySelectorAll("[data-demo]")
      .forEach((b) => b.classList.remove("active"));
    $("operator").value = "all";
    await load(await file.text(), file.name);
  });
$("export").onclick = () => {
  if (!lastReport) {
    status("先完成一次扫描再导出报告。", true);
    return;
  }
  const url = URL.createObjectURL(
    new Blob([JSON.stringify(lastReport, null, 2)], {
      type: "application/json",
    }),
  );
  const a = document.createElement("a");
  a.href = url;
  a.download = `moonice-${selected}.json`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};
task(() => demo("events"));
