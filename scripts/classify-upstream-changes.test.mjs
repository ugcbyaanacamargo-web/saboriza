import { test } from "node:test";
import { strict as assert } from "node:assert";
import { classifyUpstreamChange } from "./classify-upstream-changes.mjs";

test("auto release accepts source and state changes when SQL contract is unchanged", () => {
  const result = classifyUpstreamChange([
    "src/store/catalog-store.ts", "src/types/product.ts", "src/lib/mappers/product-mapper.ts",
    "src/pages/admin/ProductsPage.tsx", "package.json", "package-lock.json",
  ]);
  assert.equal(result.auto, true);
  assert.deepEqual(result.blockers, []);
});

test("auto release accepts original UI change without new data", () => {
  assert.equal(classifyUpstreamChange(["src/components/admin/AdminNav.tsx"]).auto, true);
});

test("auto release blocks new/changed SQL and typed database contracts", () => {
  for (const file of ["scripts/2026-10-01_products.sql", "src/types/supabase.ts",
                      "supabase/migrations/20261001120000_new_table.sql"]) {
    const x = classifyUpstreamChange([file, "src/pages/admin/ProductsPage.tsx"]);
    assert.equal(x.auto, false, file);
    assert.ok(x.blockers.some(v => v.includes(file)), file);
  }
});

test("auto release protects local auth, credentials, project identity and unknown files", () => {
  for (const file of [".env.example", ".gitignore", "src/main.tsx",
                      "src/store/admin-auth-store.ts", "src/lib/supabase.ts",
                      "src/config/contact.ts", "vercel.json", ".github/workflows/release-saboriza.yml",
                      "SABORIZA_MODULOS (guia de fases).md"]) {
    assert.equal(classifyUpstreamChange([file]).auto, false, file);
  }
});

test("auto release does nothing when source did not change", () => {
  assert.equal(classifyUpstreamChange([]).auto, false);
});

test("rejects unversioned source migrations, even when client contract stayed constant", () => {
  const x = classifyUpstreamChange(["src/components/catalog/Hero.tsx"], true);
  assert.equal(x.auto, false);
  assert.match(x.blockers.join(" "), /upstream.*migrations/i);
});
