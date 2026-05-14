// Config — reads from environment variables
// Copy .env.example to .env and fill in values, or set env vars directly

import { readFileSync } from "fs";
import { resolve } from "path";

export interface Config {
  owner: string;
  repo: string;
  projectId: string;
  statusFieldId: string;
  inProgressOptionId: string;
  codeReviewOptionId: string;
  doneOptionId: string;
}

const ENV_MAP: Record<keyof Config, string> = {
  owner: "GITHUB_OWNER",
  repo: "GITHUB_REPO",
  projectId: "WORKFLOW_PROJECT_ID",
  statusFieldId: "WORKFLOW_STATUS_FIELD_ID",
  inProgressOptionId: "WORKFLOW_IN_PROGRESS_OPTION_ID",
  codeReviewOptionId: "WORKFLOW_CODE_REVIEW_OPTION_ID",
  doneOptionId: "WORKFLOW_DONE_OPTION_ID"
};

function loadDotEnv(): void {
  try {
    const envPath = resolve(process.cwd(), ".env");
    const content = readFileSync(envPath, "utf-8");
    for (const line of content.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const idx = trimmed.indexOf("=");
      if (idx === -1) continue;
      const key = trimmed.slice(0, idx).trim();
      const val = trimmed.slice(idx + 1).trim().replace(/^["']|["']$/g, "");
      if (key && val && !process.env[key]) {
        process.env[key] = val;
      }
    }
  } catch {
    // .env not found — use existing env vars only
  }
}

export function getConfig(): Config {
  loadDotEnv();

  const config = {} as Config;
  const missing: string[] = [];

  for (const key of Object.keys(ENV_MAP) as (keyof Config)[]) {
    const envKey = ENV_MAP[key];
    const value = process.env[envKey];
    if (!value) {
      missing.push(envKey);
    } else {
      config[key] = value;
    }
  }

  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables:\n${missing.map(k => `  ${k}`).join("\n")}\n\nCopy .env.example to .env and fill in the values.`
    );
  }

  return config;
}
