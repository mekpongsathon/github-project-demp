/**
 * update-status — Update Project V2 status for issues without touching git
 *
 * Usage:
 *   npm run update-status -- --issues 2 3 4 --status "In Progress"
 *   npm run update-status -- --issues 2 3 4 --status "Code Review"
 *   npm run update-status -- --issues 2 3 4 --status "Done"
 */

import { getConfig } from "../shared/config.js";
import { updateIssuesStatus } from "../github/project.js";

const args = process.argv.slice(2);
const issueNumbers: number[] = [];
let status = "In Progress";

for (let i = 0; i < args.length; i++) {
  if (args[i] === "--issues") {
    i++;
    while (i < args.length && !args[i].startsWith("--")) {
      const n = parseInt(args[i], 10);
      if (!isNaN(n)) issueNumbers.push(n);
      i++;
    }
    i--;
  } else if (args[i] === "--status" && args[i + 1]) {
    status = args[++i];
  }
}

if (issueNumbers.length === 0) {
  console.error('Usage: npm run update-status -- --issues <n> [n...] --status "In Progress|Code Review|Done"');
  process.exit(1);
}

const STATUS_KEY_MAP: Record<string, keyof ReturnType<typeof getConfig>> = {
  "in progress": "inProgressOptionId",
  "code review": "codeReviewOptionId",
  "done": "doneOptionId"
};

try {
  const cfg = getConfig();
  const key = STATUS_KEY_MAP[status.toLowerCase()];

  if (!key) {
    console.error(`Unknown status "${status}". Valid values: "In Progress", "Code Review", "Done"`);
    process.exit(1);
  }

  const optionId = cfg[key] as string;
  if (!optionId) {
    console.error(`Option ID for "${status}" is not configured in .env`);
    process.exit(1);
  }

  console.log(`\n▶ update-status: issues ${issueNumbers.map(n => `#${n}`).join(", ")} → ${status}\n`);

  await updateIssuesStatus(
    cfg.owner,
    cfg.repo,
    issueNumbers,
    cfg.projectId,
    cfg.statusFieldId,
    optionId,
    status
  );

  console.log(`\n✅ Done: ${issueNumbers.length} issue(s) → ${status}`);
} catch (err) {
  console.error("\n❌ update-status failed:", (err as Error).message);
  process.exit(1);
}
