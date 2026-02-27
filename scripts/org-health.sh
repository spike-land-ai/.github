#!/usr/bin/env bash
# org-health.sh — Single-pane org health report for all spike-land-ai repos
# Usage: bash .github/scripts/org-health.sh [/path/to/spike-land-ai]
set -o pipefail

ORG="spike-land-ai"
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"

REPOS=(hackernews-mcp openclaw-mcp spike-review spike-cli esbuild-wasm-mcp
       vibe-dev shared esbuild-wasm code transpile spike-land-backend
       mcp-pixel react-ts-worker video spike.land .github)

# Age threshold (days) for flagging PRs and issues
PR_AGE_DAYS=3
ISSUE_AGE_DAYS=7

# Colors
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

# Counters
TOTAL_OK=0
TOTAL_WARN=0
TOTAL_FAIL=0

now_epoch=$(date +%s)

days_ago() {
  local iso_date="$1"
  local then_epoch
  then_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$iso_date" +%s 2>/dev/null \
    || date -d "$iso_date" +%s 2>/dev/null \
    || echo "$now_epoch")
  echo $(( (now_epoch - then_epoch) / 86400 ))
}

echo -e "${BOLD}=== spike-land-ai Org Health Report ===${RESET}"
echo ""

for repo in "${REPOS[@]}"; do
  issue_lines=""
  warn_lines=""
  issue_count=0
  warn_count=0

  # --- Open PRs (skip gh repo view check — just query directly) ---
  pr_json=$(gh pr list --repo "$ORG/$repo" --state open \
    --json number,title,createdAt,statusCheckRollup,reviewDecision 2>/dev/null || echo "[]")
  pr_count=$(echo "$pr_json" | node -e "
    const d=JSON.parse(require('fs').readFileSync(0,'utf8'));
    console.log(d.length);
  " 2>/dev/null || echo "0")

  if [ "$pr_count" -gt 0 ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      num=$(echo "$line" | cut -d'|' -f1)
      title=$(echo "$line" | cut -d'|' -f2)
      created=$(echo "$line" | cut -d'|' -f3)
      ci_status=$(echo "$line" | cut -d'|' -f4)
      review=$(echo "$line" | cut -d'|' -f5)

      age=$(days_ago "$created")

      if [ "$ci_status" = "FAILURE" ]; then
        issue_lines="${issue_lines}PR #${num} failing CI (opened ${age}d ago)\n"
        issue_count=$((issue_count + 1))
      elif [ "$review" = "CHANGES_REQUESTED" ]; then
        warn_lines="${warn_lines}PR #${num} has changes requested (opened ${age}d ago)\n"
        warn_count=$((warn_count + 1))
      elif [ "$age" -gt "$PR_AGE_DAYS" ]; then
        warn_lines="${warn_lines}PR #${num} open ${age}d (${title})\n"
        warn_count=$((warn_count + 1))
      fi
    done < <(echo "$pr_json" | node -e "
      const d=JSON.parse(require('fs').readFileSync(0,'utf8'));
      d.forEach(pr => {
        const checks = pr.statusCheckRollup || [];
        const hasFail = checks.some(c => c.conclusion === 'FAILURE');
        const ciStatus = hasFail ? 'FAILURE' : 'OK';
        console.log([pr.number, pr.title.substring(0,50), pr.createdAt, ciStatus, pr.reviewDecision || ''].join('|'));
      });
    " 2>/dev/null || true)
  fi

  # --- Last CI run on main ---
  last_ci=$(gh run list --repo "$ORG/$repo" --branch main --limit 1 \
    --json conclusion 2>/dev/null || echo "[]")
  ci_conclusion=$(echo "$last_ci" | node -e "
    const d=JSON.parse(require('fs').readFileSync(0,'utf8'));
    console.log(d[0]?.conclusion || 'none');
  " 2>/dev/null || echo "none")
  if [ "$ci_conclusion" = "failure" ]; then
    issue_lines="${issue_lines}Last CI on main failed\n"
    issue_count=$((issue_count + 1))
  fi

  # --- Open issues ---
  issue_json=$(gh issue list --repo "$ORG/$repo" --state open \
    --json number,title,createdAt,labels 2>/dev/null || echo "[]")
  stale_issues=$(echo "$issue_json" | node -e "
    const d=JSON.parse(require('fs').readFileSync(0,'utf8'));
    const now=Date.now();
    const threshold=${ISSUE_AGE_DAYS}*86400000;
    const stale=d.filter(i => {
      const age=now-new Date(i.createdAt).getTime();
      const blocked=(i.labels||[]).some(l=>l.name==='blocked');
      return age>threshold && !blocked;
    });
    console.log(stale.length);
  " 2>/dev/null || echo "0")
  if [ "$stale_issues" -gt 0 ]; then
    warn_lines="${warn_lines}${stale_issues} open issue(s) > ${ISSUE_AGE_DAYS} days\n"
    warn_count=$((warn_count + 1))
  fi

  # --- Local worktree ---
  repo_dir="$ROOT/$repo"
  if [ -d "$repo_dir/.git" ]; then
    dirty_count=$(cd "$repo_dir" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$dirty_count" -gt 0 ]; then
      warn_lines="${warn_lines}Worktree dirty (${dirty_count} files)\n"
      warn_count=$((warn_count + 1))
    fi

    # --- Stale branches ---
    branch_count=$(cd "$repo_dir" && git branch 2>/dev/null | grep -v '^\*' | grep -v 'main$' | grep -v 'master$' | wc -l | tr -d ' ')
    if [ "$branch_count" -gt 2 ]; then
      warn_lines="${warn_lines}${branch_count} non-main branches\n"
      warn_count=$((warn_count + 1))
    fi
  fi

  # --- Dep drift (for consuming repos) ---
  if [ -f "$repo_dir/package.json" ]; then
    drift=$(node -e "
      const fs=require('fs');
      const root='$ROOT';
      const sources=['esbuild-wasm','esbuild-wasm-mcp','code','shared','react-ts-worker','spike-cli'];
      const pub={};
      sources.forEach(s=>{
        try{
          const p=JSON.parse(fs.readFileSync(root+'/'+s+'/package.json','utf8'));
          pub[p.name]=p.version;
        }catch(e){}
      });
      const pkg=JSON.parse(fs.readFileSync('$repo_dir/package.json','utf8'));
      const all=Object.assign({},pkg.dependencies,pkg.devDependencies,pkg.peerDependencies);
      let drift=0;
      Object.entries(pub).forEach(([name,ver])=>{
        if(all[name] && all[name]!==ver) drift++;
      });
      console.log(drift);
    " 2>/dev/null || echo "0")
    if [ "$drift" -gt 0 ]; then
      warn_lines="${warn_lines}${drift} @spike-land-ai dep(s) out of sync\n"
      warn_count=$((warn_count + 1))
    fi
  fi

  # --- Print result ---
  if [ "$issue_count" -gt 0 ]; then
    status="${RED}FAIL${RESET}"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  elif [ "$warn_count" -gt 0 ]; then
    status="${YELLOW}WARN${RESET}"
    TOTAL_WARN=$((TOTAL_WARN + 1))
  else
    status="${GREEN}OK${RESET}"
    TOTAL_OK=$((TOTAL_OK + 1))
  fi

  padding_len=$((30 - ${#repo}))
  [ "$padding_len" -lt 1 ] && padding_len=1
  padding=$(printf '%*s' "$padding_len" '' | tr ' ' '.')
  echo -e "${BOLD}${repo}${RESET} ${padding} ${status}"

  if [ -n "$issue_lines" ]; then
    echo -e "$issue_lines" | while IFS= read -r line; do
      [ -n "$line" ] && echo -e "  ${RED}✗${RESET} ${line}"
    done
  fi
  if [ -n "$warn_lines" ]; then
    echo -e "$warn_lines" | while IFS= read -r line; do
      [ -n "$line" ] && echo -e "  ${YELLOW}⚠${RESET} ${line}"
    done
  fi
  if [ "$issue_count" -eq 0 ] && [ "$warn_count" -eq 0 ]; then
    echo -e "  ${GREEN}✓${RESET} All clear"
  fi
  echo ""
done

echo -e "${BOLD}Summary: ${GREEN}${TOTAL_OK} OK${RESET} | ${YELLOW}${TOTAL_WARN} WARN${RESET} | ${RED}${TOTAL_FAIL} FAIL${RESET}"
