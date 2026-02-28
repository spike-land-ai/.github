## Quick Start

Each directory is a separate git repo. Clone the one you need:

```bash
# Main platform (Next.js 16)
git clone https://github.com/spike-land-ai/spike.land
cd spike.land
yarn install
yarn dev              # http://localhost:3000

# Node.js / MCP servers (most packages)
git clone https://github.com/spike-land-ai/<package>
cd <package>
npm install
npm run build
npm test

# Cloudflare Workers (spike-land-backend, transpile)
npm install
npm run dev           # local wrangler
npm run dev:remote    # remote wrangler

# Monaco editor (code)
npm install
npm run dev:vite      # Vite dev server

# Custom React (react-ts-worker)
yarn install
yarn build
yarn test
```

Org-wide health check (PRs, CI status, dep drift):

```bash
make health
# or: bash .github/scripts/org-health.sh
```
