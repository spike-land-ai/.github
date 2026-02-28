## Contributing

- TypeScript strict mode is enforced across all packages — use `unknown` instead of `any`
- Tests are written with Vitest; coverage thresholds are enforced in CI (80%+ for most packages)
- Never use `eslint-disable`, `@ts-ignore`, or `@ts-nocheck`
- Version and publish via [Changesets](https://github.com/changesets/changesets) — do not manually bump `package.json` versions
- MCP servers follow the pattern: `@modelcontextprotocol/sdk` + Zod schema + tool handler + matching test file
- spike.land uses Yarn; all other packages use npm
