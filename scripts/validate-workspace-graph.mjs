#!/usr/bin/env node

/**
 * Validates that the workspace dependency graph (from package.json files)
 * matches the CI cascade config in .github/dependency-map.json.
 *
 * Reports:
 * - Missing cascade entries (workspace:* deps not in dependency-map.json)
 * - Stale cascade entries (dependency-map.json entries with no workspace:* dep)
 */

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..", "..");

// Load dependency-map.json
const depMapPath = join(root, ".github", "dependency-map.json");
const depMap = JSON.parse(readFileSync(depMapPath, "utf8"));

// Get workspace list from yarn
const workspaceJson = execSync("yarn workspaces list --json", {
  cwd: root,
  encoding: "utf8",
});
const workspaces = workspaceJson
  .trim()
  .split("\n")
  .map((line) => JSON.parse(line))
  .filter((w) => w.location !== ".");

// Shared config packages — not part of the publish cascade
const sharedConfigPackages = new Set([
  "@spike-land-ai/eslint-config",
  "@spike-land-ai/tsconfig",
]);

// Build actual dependency graph from workspace:* declarations
const actualGraph = new Map(); // packageName -> Set<consumerLocation>

for (const ws of workspaces) {
  const pkgPath = join(root, ws.location, "package.json");
  if (!existsSync(pkgPath)) continue;

  const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
  const allDeps = {
    ...pkg.dependencies,
    ...pkg.devDependencies,
  };

  for (const [dep, version] of Object.entries(allDeps)) {
    if (!dep.startsWith("@spike-land-ai/")) continue;
    if (sharedConfigPackages.has(dep)) continue;
    if (typeof version !== "string" || !version.startsWith("workspace:"))
      continue;

    if (!actualGraph.has(dep)) {
      actualGraph.set(dep, new Set());
    }
    // Map location to the short name used in dependency-map.json
    // spike.land uses "spike.land", packages/spike.land uses "spike.land"
    const location = ws.location.replace(/^packages\//, "");
    actualGraph.get(dep).add(location);
  }
}

let errors = 0;

// Check for missing cascade entries
for (const [pkg, consumers] of actualGraph) {
  const cascadeConsumers = new Set(depMap[pkg] || []);

  for (const consumer of consumers) {
    if (!cascadeConsumers.has(consumer)) {
      console.error(
        `MISSING: ${pkg} -> ${consumer} (workspace:* dep exists but not in dependency-map.json)`,
      );
      errors++;
    }
  }
}

// Check for stale cascade entries
for (const [pkg, consumers] of Object.entries(depMap)) {
  if (sharedConfigPackages.has(pkg)) continue;

  const actualConsumers = actualGraph.get(pkg) || new Set();

  for (const consumer of consumers) {
    if (!actualConsumers.has(consumer)) {
      console.error(
        `STALE: ${pkg} -> ${consumer} (in dependency-map.json but no workspace:* dep found)`,
      );
      errors++;
    }
  }
}

// Report packages in workspace graph but not in dependency-map.json at all
for (const [pkg] of actualGraph) {
  if (!(pkg in depMap)) {
    console.error(
      `MISSING KEY: ${pkg} has workspace:* consumers but no entry in dependency-map.json`,
    );
    errors++;
  }
}

if (errors > 0) {
  console.error(`\n${errors} drift issue(s) found.`);
  process.exit(1);
} else {
  console.log("Workspace graph matches dependency-map.json — no drift found.");
}
