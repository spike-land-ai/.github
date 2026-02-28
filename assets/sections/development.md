## Development

### Common Commands

```bash
# Node.js / MCP servers
npm run build         # Compile TypeScript
npm test              # Run Vitest tests
npm run test:coverage # Tests with coverage thresholds
npm run typecheck     # tsc --noEmit
npm run lint          # ESLint

# spike.land (Yarn)
yarn dev              # Dev server (localhost:3000)
yarn build            # Production build
yarn typecheck        # TypeScript check
yarn test:coverage    # Vitest with enforced thresholds
yarn depot:ci         # Remote CI build via Depot

# Cloudflare Workers
npm run dev           # Local wrangler dev
npm run w:deploy:prod # Deploy to production
```

### CI/CD

All repos share a reusable workflow at `.github/.github/workflows/ci-publish.yml` running on Node 24. Changesets manages versioning; packages publish to GitHub Packages on every merge to `main`. spike.land uses its own extended pipeline: ESLint, TypeScript, Vitest (4 shards), Next.js build, then AWS ECS deploy via Depot remote builds.

### Dependency Cascade

Publishing any `@spike-land-ai/*` package triggers automated PRs in downstream repos. The DAG is defined in `.github/dependency-map.json`. Check for drift locally:

```bash
bash .github/scripts/verify-deps.sh
```

Key upstream packages and their consumers:

| Source | Consumers |
|--------|-----------|
| `esbuild-wasm` | esbuild-wasm-mcp, code, transpile, spike-land-backend, spike.land |
| `shared` | code, transpile, spike-land-backend, spike.land |
| `react-ts-worker` | spike.land |
| `spike-cli` | spike.land |
