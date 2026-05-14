<#
.SYNOPSIS
    Show current branch, linked PR, and issue statuses.

.DESCRIPTION
    Usage:
        .\tools\check-status.ps1
#>

. "$PSScriptRoot\_github.ps1"
Get-EnvConfig

$owner  = [System.Environment]::GetEnvironmentVariable("GITHUB_OWNER")
$repo   = [System.Environment]::GetEnvironmentVariable("GITHUB_REPO")
$branch = git branch --show-current

Write-Host "`n▶ check-status"
Write-Host "  Branch: $branch`n"

# Find open PR for current branch
$prs = Invoke-GitHubREST -Path "/repos/$owner/$repo/pulls?head=${owner}:${branch}&state=open"

if (-not $prs -or $prs.Count -eq 0) {
    Write-Host "  No open PR found for this branch."
    Write-Host "`nStatus: branch created, PR not yet opened."
    exit 0
}

$pr = $prs[0]

# Extract Closes #n references from PR body
$linkedIssues = [System.Collections.Generic.List[int]]::new()
$matches = [System.Text.RegularExpressions.Regex]::Matches($pr.body, 'closes\s+#(\d+)', 'IgnoreCase')
foreach ($m in $matches) { $linkedIssues.Add([int]$m.Groups[1].Value) }

$issueText = if ($linkedIssues.Count -gt 0) {
    ($linkedIssues | ForEach-Object { "#$_" }) -join ", "
} else { "(none detected)" }

Write-Host "PR:     #$($pr.number) — $($pr.title) ($($pr.state.ToUpper()))"
Write-Host "URL:    $($pr.html_url)"
Write-Host "Issues: $issueText"
