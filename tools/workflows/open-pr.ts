/**
 * open-pr — Create PR with Closes references for all linked issues
 *
 * Usage:
 *   npm run open-pr -- --issues 2 3 4 --title "feat: implement issues 2 3 4"
 *   npm run open-pr -- --issues 2 3 4  (title auto-generated)
 */

import { getConfig } from "../shared/config.js";
import { updateIssuesStatus } from "../github/project.js";
import { currentBranch } from "../shared/git.js";
import { rest } from "../github/graphql.js";

interface PRResponse {
  number: number;
  html_url: string;
  title: string;
}

const args = process.argv.slice(2);

const issueNumbers: number[] = [];
let title: string | undefined;
let reviewers: string[] = [];

for (let i = 0; i < args.length; i++) {
  if (args[i] === "--issues") {
    i++;
    while (i < args.length && !args[i].startsWith("--")) {
      const n = parseInt(args[i], 10);
      if (!isNaN(n)) issueNumbers.push(n);
      i++;
    }
    i--;
  } else if (args[i] === "--title" && args[i + 1]) {
    title = args[++i];
  } else if (args[i] === "--reviewers") {
    i++;
    while (i < args.length && !args[i].startsWith("--")) {
      reviewers.push(args[i++]);
    }
    i--;
  }
}

if (issueNumbers.length === 0) {
  console.error("Usage: npm run open-pr -- --issues <n> [n...] [--title <title>] [--reviewers <user...>]");
  console.error("Example: npm run open-pr -- --issues 2 3 4");
  process.exit(1);
}

try {
  const cfg = getConfig();
  const branch = currentBranch();

  const prTitle = title ?? `feat: implement issues ${issueNumbers.map(n => `#${n}`).join(", ")}`;
  const closingRefs = issueNumbers.map(n => `Closes #${n}`).join("\n");
  const body = `${closingRefs}\n\n---\n_PR created via github-workflow-cli_`;

  console.log(`\n▶ open-pr`);
  console.log(`  Branch: ${branch}`);
  console.log(`  Issues: ${issueNumbers.map(n => `#${n}`).join(", ")}`);
  console.log(`  Title:  ${prTitle}\n`);

  // Step 1: create PR via REST API
  console.log("→ Creating PR...");
  const pr = await rest<PRResponse>(`/repos/${cfg.owner}/${cfg.repo}/pulls`, {
    method: "POST",
    body: {
      title: prTitle,
      head: branch,
      base: "main",
      body,
      draft: false
    }
  });

  console.log(`  ✓ PR #${pr.number} created: ${pr.html_url}\n`);

  // Step 2: assign reviewers if provided
  if (reviewers.length > 0) {
    console.log(`→ Assigning reviewers: ${reviewers.join(", ")}...`);
    await rest(`/repos/${cfg.owner}/${cfg.repo}/pulls/${pr.number}/requested_reviewers`, {
      method: "POST",
      body: { reviewers }
    });
    console.log("  ✓ Reviewers assigned\n");
  }

  // Step 3: update Project V2 → Code Review
  console.log("→ Updating Project V2 statuses → Code Review...");
  await updateIssuesStatus(
    cfg.owner,
    cfg.repo,
    issueNumbers,
    cfg.projectId,
    cfg.statusFieldId,
    cfg.codeReviewOptionId,
    "Code Review"
  );

  console.log("\n✅ open-pr complete");
  console.log(`   PR:     #${pr.number} — ${pr.title}`);
  console.log(`   URL:    ${pr.html_url}`);
  console.log(`   Issues: ${issueNumbers.map(n => `#${n}`).join(", ")} → Code Review`);
} catch (err) {
  console.error("\n❌ open-pr failed:", (err as Error).message);
  process.exit(1);
}
