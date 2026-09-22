// Fail closed when an upstream frontend expects schema not represented by
// approved versioned migrations. Never executes SQL in the Git sync job.
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const schema = readFileSync("src/types/supabase.ts", "utf8");
function between(start, end) {
  const a = schema.indexOf(start), b = schema.indexOf(end, a + start.length);
  if (a < 0 || b < 0) throw new Error("Cannot parse Supabase type definitions");
  return schema.slice(a + start.length, b);
}
const tablesText = between("    Tables: {", "    Views: {");
const functionsText = between("    Functions: {", "    Enums: {");
const tableMatches = [...tablesText.matchAll(/^      ([a-z][a-z0-9_]*): \{/gm)];
const tables = tableMatches.map((match) => match[1]);
const functions = [...functionsText.matchAll(/^      ([a-z][a-z0-9_]*): \{/gm)].map((match) => match[1]);
if (!tables.length || !functions.length) throw new Error("Supabase type parser returned empty table/function list.");

const columns = [];
tableMatches.forEach((match, index) => {
  const chunk = tablesText.slice(match.index, tableMatches[index + 1]?.index ?? tablesText.length);
  const row = chunk.match(/        Row: \{([\s\S]*?)\n        \}\n        Insert: \{/);
  if (!row) throw new Error("Cannot read Row fields of " + match[1]);
  const names = [...row[1].matchAll(/^          ([a-z][a-z0-9_]*):/gm)].map((v) => v[1]);
  if (!names.length) throw new Error("No columns found in " + match[1]);
  columns.push(...names.map((name) => [match[1], name]));
});
const quote = (value) => "'" + value.replaceAll("'", "''") + "'";
const values = (rows) => rows.map((row) => "(" + row.map(quote).join(",") + ")").join(",\n");
const sql = [
  "WITH",
  "expected_tables(name) AS (VALUES " + values(tables.map((v) => [v])) + "),",
  "expected_columns(table_name,column_name) AS (VALUES " + values(columns) + "),",
  "expected_functions(name) AS (VALUES " + values(functions.map((v) => [v])) + ")",
  "SELECT json_build_object(",
  "  'missing_tables', (SELECT coalesce(json_agg(e.name),'[]'::json) FROM expected_tables e",
  "    WHERE NOT EXISTS (SELECT 1 FROM information_schema.tables t",
  "      WHERE t.table_schema='public' AND t.table_name=e.name)),",
  "  'missing_columns', (SELECT coalesce(json_agg(e.table_name || '.' || e.column_name),'[]'::json)",
  "    FROM expected_columns e WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns c",
  "      WHERE c.table_schema='public' AND c.table_name=e.table_name AND c.column_name=e.column_name)),",
  "  'missing_functions', (SELECT coalesce(json_agg(e.name),'[]'::json) FROM expected_functions e",
  "    WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace",
  "      WHERE n.nspname='public' AND p.proname=e.name)),",
  "  'rls_disabled', (SELECT coalesce(json_agg(e.name),'[]'::json) FROM expected_tables e",
  "    JOIN pg_class c ON c.relname=e.name JOIN pg_namespace n ON n.oid=c.relnamespace AND n.nspname='public'",
  "    WHERE NOT c.relrowsecurity)",
  ");"
].join("\n");

if (process.argv.includes("--expected-sql")) {
  process.stdout.write(sql + "\n");
} else if (process.argv.includes("--verify-json")) {
  const index = process.argv.indexOf("--verify-json");
  const result = JSON.parse(readFileSync(process.argv[index + 1], "utf8").trim());
  const errors = Object.entries(result).filter(([, items]) => items.length > 0);
  if (errors.length) {
    for (const [kind, items] of errors) console.error(kind + ": " + items.join(", "));
    process.exitCode = 1;
  } else console.log("Live Supabase contract validated: " + tables.length + " tables, " + columns.length + " columns, " + functions.length + " RPCs and RLS.");
} else {
  const files = readdirSync("supabase/migrations").filter((f) => /^\d{14}_[a-z0-9_]+\.sql$/.test(f)).sort();
  if (!files.length) throw new Error("No versioned Supabase migrations");
  const source = files.map((f) => readFileSync(join("supabase/migrations", f), "utf8"))
    .join("\n").replace(/\/\*[\s\S]*?\*\//g, "").replace(/--[^\n]*/g, "");
  const createdTables = new Set(
    [...source.matchAll(/\bcreate\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-z][a-z0-9_]*)\s*\(/gi)]
      .map((m) => m[1].toLowerCase())
  );
  const createdFunctions = new Set(
    [...source.matchAll(/\bcreate\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z][a-z0-9_]*)\s*\(/gi)]
      .map((m) => m[1].toLowerCase())
  );
  const missingTables = tables.filter((t) => !createdTables.has(t));
  const missingFunctions = functions.filter((f) => !createdFunctions.has(f));
  if (missingTables.length || missingFunctions.length) {
    if (missingTables.length) console.error("No reviewed CREATE TABLE migration for: " + missingTables.join(", "));
    if (missingFunctions.length) console.error("No reviewed CREATE FUNCTION migration for: " + missingFunctions.join(", "));
    console.error("Add reviewed, non-destructive SQL under supabase/migrations before approving the upstream code.");
    process.exitCode = 1;
  } else console.log("Migrations declare " + tables.length + " tables and " + functions.length + " RPCs.");
}
