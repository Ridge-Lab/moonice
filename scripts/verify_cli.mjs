import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
const cli = '_build/js/release/build/cmd/main/main.js';
function run(args, code = 0) {
  const child = spawnSync(process.execPath, [cli, ...args], {encoding: 'utf8', timeout: 30000});
  assert.equal(child.error, undefined);
  assert.equal(child.status, code, `${args.join(' ')}\n${child.stdout}\n${child.stderr}`);
  return child.stdout;
}
const input = 'fixtures/deletes.icebundle.json';
const result = JSON.parse(run(['scan', input, '--limit', '1']));
assert.equal(result.ok, true);
assert.equal(result.result.scan.rows.length, 1);
assert.equal(result.result.scan.matched_rows, 2);
assert.equal(result.result.scan.deleted_rows, 3);
assert.equal(result.result.scan.truncated, true);
assert.deepEqual(result.result.scan.rows.map(r => r.values.id), ['4']);
assert.equal(JSON.parse(run(['scan', input, '--limit', '0'])).result.scan.rows.length, 0);
run(['scan', input, '--limit', '1', '--limit', '2'], 2);
run(['scan', 'work/does-not-exist.icebundle.json'], 2);
run(['scan', input, '--filter', '{"field":"unknown","op":"=","value":1}'], 1);
run(['scan', input, '--limit', '-1'], 1);
run(['scan', input, '--filter', '{"field":"id","op":"=","value":"9007199254740993"}']);

// DuckDB's shared_source fixture stores region in the manifest's identity
// partition. Its Parquet file physically contains only id.
const sharedSource = 'fixtures/duckdb/identity-source.icebundle.json';
const allRows = JSON.parse(run(['scan', sharedSource])).result.scan.rows;
assert.deepEqual(allRows.map(row => [row.values.id, row.values.region]).sort(),
  [['1', 'eu'], ['2', 'eu']]);
const byRegion = JSON.stringify({field: 'region', op: '=', value: 'eu'});
const filtered = JSON.parse(run(['scan', sharedSource, '--filter', byRegion])).result.scan;
assert.equal(filtered.matched_rows, 2);
const mixed = 'fixtures/duckdb/column-mapping.icebundle.json';
const adults = JSON.stringify({field: 'age', op: '>=', value: '30'});
const names = JSON.parse(run(['scan', mixed, '--column', 'name', '--filter', adults])).result.scan;
assert.deepEqual(names.rows.map(row => row.values), [{name: 'Bob'}, {name: 'Charlie'}]);
assert.deepEqual(names.schema.fields.map(field => field.name), ['name']);
assert.equal(JSON.parse(run(['scan', mixed, '--column', 'scores'], 1)).error.code, 'UNSUPPORTED_TYPE');
assert.equal(JSON.parse(run(['scan', mixed], 1)).error.code, 'UNSUPPORTED_NESTED');
run(['plan', mixed, '--column', 'name'], 2);
console.log('CLI: exact Int64, deletes, identity partition columns, limits and error exits passed');
