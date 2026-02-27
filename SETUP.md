# Dependency Cascade — Setup Guide

This document explains how to set up and maintain the automated dependency
cascade system for **spike-land-ai**.

---

## How It Works

```
Package merges to main
        │
        ▼
ci-publish.yml  ──(Changesets publishes)──► npm.pkg.github.com
        │
        ▼  [notify job]
dependency-map.json lookup
        │
        ▼  [repository_dispatch]
receive-dispatch.yml (in each consumer repo)
        │
        ▼
bump-dependency.yml (reusable workflow)
        │
        ├── Updates package.json
        ├── Opens PR via peter-evans/create-pull-request
        └── Enables auto-merge (squash) — CI gates the merge
```

A **nightly sweep** (`dep-sync-sweep.yml`, 06:00 UTC) catches anything the
cascade misses (manual publishes, race conditions).

---

## Prerequisites: GitHub PAT Token

`GITHUB_TOKEN` cannot dispatch `repository_dispatch` to other repos — a
classic PAT (or fine-grained token) is required.

### Create the PAT

1. Go to <https://github.com/settings/tokens>
2. Click **Generate new token (classic)**
3. Note: `spike-land-ai dependency cascade`
4. Expiration: 1 year (set a calendar reminder to rotate)
5. Scope: `repo` (full repository access)
6. Click **Generate token** — copy the value immediately

### Add `GH_PAT_TOKEN` Secret to Each Repo

Add the PAT as `GH_PAT_TOKEN` in these repositories:

| Repository | Role |
|------------|------|
| `spike-land-ai/.github` | Runs sweep + sends dispatch notifications |
| `spike-land-ai/code` | Receives bump PRs |
| `spike-land-ai/esbuild-wasm-mcp` | Receives bump PRs |
| `spike-land-ai/transpile` | Receives bump PRs |
| `spike-land-ai/spike-land-backend` | Receives bump PRs |
| `spike-land-ai/spike.land` | Receives bump PRs |

Using the GitHub CLI:

```bash
PAT="ghp_your_token_here"
for repo in .github code esbuild-wasm-mcp transpile spike-land-backend spike.land; do
  gh secret set GH_PAT_TOKEN \
    --repo "spike-land-ai/$repo" \
    --body "$PAT"
done
```

---

## Dependency Map

`dependency-map.json` (in the root of this repo) is the **source of truth** for
who depends on whom:

```json
{
  "@spike-land-ai/esbuild-wasm": ["esbuild-wasm-mcp", "code", "transpile", "spike-land-backend", "spike.land"],
  "@spike-land-ai/code":         ["transpile", "spike-land-backend"],
  ...
}
```

**Keys** are npm package names. **Values** are GitHub repo names (without the
`spike-land-ai/` prefix).

---

## Adding a New Package to the Cascade

1. **Publish the package** to GitHub Packages (ensure `publishConfig.registry`
   is set in its `package.json`).

2. **Update `dependency-map.json`** in this repo:
   ```json
   "@spike-land-ai/new-package": ["consumer-repo-a", "consumer-repo-b"]
   ```

3. **Add `receive-dispatch.yml`** to each consuming repo:
   ```yaml
   # .github/workflows/receive-dispatch.yml
   name: Receive Dependency Update
   on:
     repository_dispatch:
       types: [dependency-updated]
   jobs:
     bump:
       uses: spike-land-ai/.github/.github/workflows/bump-dependency.yml@main
       with:
         package-name: ${{ github.event.client_payload.package }}
         new-version: ${{ github.event.client_payload.version }}
         package-manager: npm   # or yarn for spike.land
       secrets: inherit
   ```

4. **Ensure `GH_PAT_TOKEN`** is set in the consuming repo (see above).

---

## Verifying Drift

Run the verify script from the umbrella `spike-land-ai` directory:

```bash
bash .github/scripts/verify-deps.sh
```

Example output:
```
--- Consumer audit ---

  [transpile]
    ✓ @spike-land-ai/code          0.9.58
    ✓ @spike-land-ai/esbuild-wasm  0.27.4

✓ All @spike-land-ai/* dependencies are in sync.
```

---

## Manual Sweep

To trigger the nightly sweep on-demand:

```bash
gh workflow run dep-sync-sweep.yml --repo spike-land-ai/.github
```

---

## Excluded Repos

| Repo | Reason |
|------|--------|
| `vinext.spike.land` | Uses git-SHA deps, not registry versions |
| `hackernews-mcp`, `mcp-pixel`, `openclaw-mcp`, `spike-review`, `vibe-dev` | Leaf nodes — no internal `@spike-land-ai/*` deps |

---

## Rotating the PAT

When the PAT expires, generate a new one and update all repos:

```bash
NEW_PAT="ghp_new_token_here"
for repo in .github code esbuild-wasm-mcp transpile spike-land-backend spike.land; do
  gh secret set GH_PAT_TOKEN \
    --repo "spike-land-ai/$repo" \
    --body "$NEW_PAT"
done
```
