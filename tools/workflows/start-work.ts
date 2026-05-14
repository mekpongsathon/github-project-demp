/**
 * start-work — Create branch, push, update Project V2 → In Progress
 *
 * Usage:
 *   npm run start-work -- 2 3 4
 *   npm run start-work -- 12 --branch feat/my-custom-branch
 */

import { getConfig } from "../shared/config.js";
import { updateIssuesStatus } from "../github/project.js";
import { createAndPushBranch } from "../shared/git.js";

const args = process.argv.slice(2);

// Parse issue numbers and optional --branch flag
const issueNumbers: number[] = [];
let customBranch: string | undefined;

for (let i = 0; i < args.length; i++) {
  if (args[i] === "--branch" && args[i + 1]) {
    customBranch = args[++i];
  } else {
    const n = parseInt(args[i], 10);
    if (!isNaN(n)) issueNumbers.push(n);
  }
}

if (issueNumbers.length === 0) {
  console.error("Usage: npm run start-work -- <issueNumber> [issueNumber...] [--branch <branchName>]");
  console.error("Example: npm run start-work -- 2 3 4");
  process.exit(1);
}

const branchName = customBranch ?? `feat/issues-${issueNumbers.join("-")}`;

console.log(`\n▶ start-work: issues ${issueNumbers.map(n => `#${n}`).join(", ")}`);
console.log(`  Branch: ${branchName}\n`);

try {
  const cfg = getConfig();

  // Step 1: create and push branch
  console.log("→ Creating and pushing branch...");
  createAndPushBranch(branchName);
  console.log(`  ✓ Branch "${branchName}" pushed\n`);

  // Step 2: update Project V2 statuses → In Progress
  console.log("→ Updating Project V2 statuses → In Progress...");
  await updateIssuesStatus(
    cfg.owner,
    cfg.repo,
    issueNumbers,
    cfg.projectId,
    cfg.statusFieldId,
    cfg.inProgressOptionId,
    "In Progress"
  );

  console.log("\n✅ start-work complete");
  console.log(`   Branch: ${branchName}`);
  console.log(`   Issues: ${issueNumbers.map(n => `#${n}`).join(", ")} → In Progress`);
} catch (err) {
  console.error("\n❌ start-work failed:", (err as Error).message);
  process.exit(1);
}
