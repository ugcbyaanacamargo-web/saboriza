// Classify an upstream sync without equating "TypeScript build" with database
// compatibility. A schema change needs versioned, reviewed SQL, not invented DDL.
import { execFileSync } from "node:child_process";
import { appendFileSync, existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const safeRootFiles = new Set([
  "index.html", "package.json", "package-lock.json",
  "tsconfig.json", "vite.config.ts",
]);
const protectedFiles = new Set([
  "src/types/supabase.ts", "src/lib/supabase.ts", "src/main.tsx",
  "src/store/admin-auth-store.ts", "src/config/contact.ts",
  ".env.example", ".gitignore",
]);

export function classifyUpstreamChange(files, upstreamMigrationsPresent = false) {
  const paths = [...new Set(files)].sort();
  const blockers = [];
  for (const file of paths) {
    if (protectedFiles.has(file)) {
      blockers.push("Protected local/database configuration: " + file);
    } else if (/^scripts\/.*\.sql$/i.test(file) || file.startsWith("supabase/")) {
      blockers.push("SQL or schema migration requires verification: " + file);
    } else if (
      file.startsWith("src/") ||
      file.startsWith("public/") ||
      /^scripts\/[^/]+\.(mjs|js)$/i.test(file) ||
      safeRootFiles.has(file)
    ) {
      continue;
    } else {
      blockers.push("Unhandled upstream path: " + file);
    }
  }
  if (upstreamMigrationsPresent) {
    blockers.push("Untracked upstream supabase/migrations need integration and verification");
  }
  return { auto: paths.length > 0 && blockers.length === 0, paths, blockers };
}

function gitNames(args) {
  const output = execFileSync("git", args, { encoding: "utf8" });
  return output.split("\0").filter(Boolean);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const files = [
    ...gitNames(["diff", "--name-only", "-z", "HEAD", "--"]),
    ...gitNames(["ls-files", "--others", "--exclude-standard", "-z"]),
  ];
  const upstreamDir = process.argv[2];
  const upstreamMigrationsDir = upstreamDir && join(upstreamDir, "supabase/migrations");
  const upstreamMigrationsPresent = Boolean(
    upstreamMigrationsDir &&
    existsSync(upstreamMigrationsDir) &&
    readdirSync(upstreamMigrationsDir).some(name => name.endsWith(".sql")),
  );
  const { auto, paths, blockers } =
    classifyUpstreamChange(files, upstreamMigrationsPresent);
  console.log("Upstream paths: " + JSON.stringify(paths));
  console.log("Auto-release allowed: " + auto);
  for (const reason of blockers) console.log("::warning::" + reason);
  if (process.env.GITHUB_OUTPUT) {
    appendFileSync(process.env.GITHUB_OUTPUT, "auto=" + auto + "\n");
    appendFileSync(process.env.GITHUB_OUTPUT, "review_required=" + (paths.length > 0 && !auto) + "\n");
  }
}
