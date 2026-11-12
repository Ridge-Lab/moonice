// Replay the browser worker's message protocol against the staged JS and fixtures.
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {once} from "node:events";
import {isMainThread, parentPort, Worker} from "node:worker_threads";

if (isMainThread) {
  const worker = new Worker(new URL(import.meta.url));
  const fixture = path => readFile(new URL("../web/" + path, import.meta.url), "utf8");
  let sequence = 0;
  async function request(options, bundle) {
    const id = ++sequence;
    const reply = once(worker, "message", {signal: AbortSignal.timeout(30000)});
    worker.postMessage({id, bundle, options});
    const [data] = await reply;
    assert.equal(data.id, id);
    assert.equal(data.payload.ok, true, JSON.stringify(data.payload.error));
    return data.payload.result;
  }
  try {
    await request({action: "inspect"}, await fixture("fixtures/duckdb/column-mapping.icebundle.json"));
    const {scan} = await request({action: "scan", columns: ["name"],
      filter: {field: "age", op: ">=", value: "30"}});
    assert.deepEqual(scan.schema.fields.map(f => f.name), ["name"]);
    assert.deepEqual(scan.rows.map(r => r.values), [{name: "Bob"}, {name: "Charlie"}]);
    for (const file of ["events", "partitioned", "deletes"]) {
      const metadata = await request({action: "inspect"}, await fixture(file + ".icebundle.json"));
      const schema = metadata.schemas.find(s => s.id === metadata.current_schema_id);
      const whole = await request({action: "scan"});
      const selected = await request({action: "scan", columns: schema.fields.map(f => f.name)});
      assert.deepEqual(selected.scan.rows, whole.scan.rows, file + " demo rows");
    }
    console.log("Worker: DuckDB projection and all three bundled demo tables passed");
  } finally {
    await worker.terminate();
  }
} else {
  globalThis.self = {postMessage: data => parentPort.postMessage(data)};
  await import("../web/worker.js");
  parentPort.on("message", data => self.onmessage({data}));
}
