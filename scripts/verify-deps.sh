#!/usr/bin/env bash
# verify-deps.sh — Report @spike-land-ai/* version drift across all consuming repos.
# Usage: .github/scripts/verify-deps.sh [/path/to/spike-land-ai]
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Source packages (those that publish to the registry)
SOURCES=(esbuild-wasm esbuild-wasm-mcp code shared react-ts-worker spike-cli)

# Consuming repos to check
CONSUMERS=(shared code esbuild-wasm-mcp transpile spike-land-backend spike.land react-ts-worker spike-cli hackernews-mcp mcp-pixel openclaw-mcp spike-review vibe-dev video)

declare -A PUBLISHED

echo "============================================"
echo " spike-land-ai Dependency Drift Report"
echo " Root: $ROOT"
echo "============================================"
echo ""
echo "--- Published versions ---"

for pkg in "${SOURCES[@]}"; do
  PKG_JSON="$ROOT/$pkg/package.json"
  if [ ! -f "$PKG_JSON" ]; then
    continue
  fi
  NAME=$(node -e "console.log(require('$PKG_JSON').name)" 2>/dev/null || true)
  VERSION=$(node -e "console.log(require('$PKG_JSON').version)" 2>/dev/null || true)
  if [ -n "$NAME" ] && [ -n "$VERSION" ]; then
    PUBLISHED["$NAME"]="$VERSION"
    printf "  %-50s %s\n" "$NAME" "$VERSION"
  fi
done

echo ""
echo "--- Consumer audit ---"

DRIFT=0
for repo in "${CONSUMERS[@]}"; do
  PKG_JSON="$ROOT/$repo/package.json"
  if [ ! -f "$PKG_JSON" ]; then
    echo "  [$repo] package.json not found, skipping."
    continue
  fi

  echo ""
  echo "  [$repo]"

  for PKG_NAME in "${!PUBLISHED[@]}"; do
    EXPECTED="${PUBLISHED[$PKG_NAME]}"
    ACTUAL=$(node -e "
      try {
        const p = JSON.parse(require('fs').readFileSync('$PKG_JSON','utf8'));
        const all = Object.assign({}, p.dependencies, p.devDependencies, p.peerDependencies);
        process.stdout.write(all['$PKG_NAME'] || '');
      } catch(e) {}
    " 2>/dev/null || true)

    if [ -z "$ACTUAL" ]; then
      continue
    fi

    if [ "$ACTUAL" = "$EXPECTED" ]; then
      printf "    ✓ %-45s %s\n" "$PKG_NAME" "$ACTUAL"
    else
      printf "    ✗ %-45s %s  (published: %s)\n" "$PKG_NAME" "$ACTUAL" "$EXPECTED"
      DRIFT=1
    fi
  done
done

echo ""
echo "============================================"
if [ $DRIFT -eq 0 ]; then
  echo " ✓ All @spike-land-ai/* dependencies are in sync."
else
  echo " ✗ Version drift detected."
  echo "   Run: gh workflow run dep-sync-sweep.yml --repo spike-land-ai/.github"
  echo "   Or open manual PRs to bump the versions listed above."
  exit 1
fi
echo "============================================"
