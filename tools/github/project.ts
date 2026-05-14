import { graphql } from "./graphql.js";

interface IssueNode {
  id: string;
  number: number;
}

interface ProjectItem {
  id: string;
  content: { id: string } | null;
}

// Get issue nodeId by number
export async function getIssueNodeId(
  owner: string,
  repo: string,
  issueNumber: number
): Promise<IssueNode> {
  const result = await graphql<{
    repository: { issue: IssueNode };
  }>(
    `query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $number) { id number }
      }
    }`,
    { owner, repo, number: issueNumber }
  );
  return result.repository.issue;
}

// Get all project items (max 100)
async function getProjectItems(projectId: string): Promise<ProjectItem[]> {
  const result = await graphql<{
    node: { items: { nodes: ProjectItem[] } };
  }>(
    `query($project: ID!) {
      node(id: $project) {
        ... on ProjectV2 {
          items(first: 100) {
            nodes {
              id
              content { ... on Issue { id } }
            }
          }
        }
      }
    }`,
    { project: projectId }
  );
  return result.node.items.nodes;
}

// Find project item ID for a given issue nodeId
export async function getProjectItemId(
  projectId: string,
  issueNodeId: string
): Promise<string | null> {
  const items = await getProjectItems(projectId);
  const item = items.find(i => i.content?.id === issueNodeId);
  return item?.id ?? null;
}

// Update a single-select field on a project item
export async function updateProjectField(
  projectId: string,
  itemId: string,
  fieldId: string,
  optionId: string
): Promise<void> {
  await graphql(
    `mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
      updateProjectV2ItemFieldValue(input: {
        projectId: $project
        itemId: $item
        fieldId: $field
        value: { singleSelectOptionId: $option }
      }) {
        projectV2Item { id }
      }
    }`,
    { project: projectId, item: itemId, field: fieldId, option: optionId }
  );
}

// Update status for a list of issue numbers
export async function updateIssuesStatus(
  owner: string,
  repo: string,
  issueNumbers: number[],
  projectId: string,
  statusFieldId: string,
  optionId: string,
  label: string
): Promise<void> {
  for (const num of issueNumbers) {
    const issue = await getIssueNodeId(owner, repo, num);
    const itemId = await getProjectItemId(projectId, issue.id);
    if (!itemId) {
      console.warn(`  ⚠  Issue #${num} not found in Project V2 — skipped`);
      continue;
    }
    await updateProjectField(projectId, itemId, statusFieldId, optionId);
    console.log(`  ✓  Issue #${num} → ${label}`);
  }
}
