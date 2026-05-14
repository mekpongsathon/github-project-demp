/**
 * check-status — Summarize current branch, PR, and linked issues state
 *
 * Usage:
 *   npm run check-status
 */

import { getConfig } from "../shared/config.js";
import { currentBranch } from "../shared/git.js";
import { rest } from "../github/graphql.js";

interface PRItem {
  number: number;
  title: string;
  html_url: string;
  state: string;
  body: string;
  head: { ref: string };
}

const closesPattern = /closes\s+#(\d+)/gi;

function extractLinkedIssues(body: string): number[] {
  const matches = [...body.matchAll(closesPattern)];
  return matches.map(m => parseInt(m[1], 10));
}

try {
  const cfg = getConfig();
  const branch = currentBranch();

  console.log(`\n▶ check-status`);
  console.log(`  Branch: ${branch}\n`);

  // Find open PR for current branch
  const prs = await rest<PRItem[]>(
    `/repos/${cfg.owner}/${cfg.repo}/pulls?head=${cfg.owner}:${branch}&state=open`
  );

  if (prs.length === 0) {
    console.log("  No open PR found for this branch.");
    console.log("\nStatus: branch created, PR not yet opened.");
    process.exit(0);
  }

  const pr = prs[0];
  const linkedIssues = extractLinkedIssues(pr.body ?? "");

  console.log(`PR: #${pr.number} — ${pr.title} (${pr.state.toUpperCase()})`);
  console.log(`URL: ${pr.html_url}`);
  console.log(`Linked issues: ${linkedIssues.length > 0 ? linkedIssues.map(n => `#${n}`).join(", ") : "(none detected)"}`);
} catch (err) {
  console.error("\n❌ check-status failed:", (err as Error).message);
  process.exit(1);
}
