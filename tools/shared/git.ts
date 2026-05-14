import { execSync } from "child_process";

export function currentBranch(): string {
  return execSync("git branch --show-current", { encoding: "utf-8" }).trim();
}

export function createAndPushBranch(branchName: string): void {
  execSync(`git checkout -b ${branchName}`, { stdio: "inherit" });
  execSync(`git push -u origin ${branchName}`, { stdio: "inherit" });
}

export function commitAll(message: string): void {
  execSync("git add -A", { stdio: "inherit" });
  execSync(`git commit -m "${message}"`, { stdio: "inherit" });
}

export function push(): void {
  execSync("git push", { stdio: "inherit" });
}
