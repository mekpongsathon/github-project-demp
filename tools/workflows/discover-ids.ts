/**
 * discover-ids — Query GitHub API to find Project V2 field option IDs
 *
 * Usage:
 *   npm run discover-ids
 *
 * Requires GITHUB_TOKEN and WORKFLOW_PROJECT_ID in .env
 */

import { getConfig } from "../shared/config.js";
import { graphql } from "../github/graphql.js";

interface FieldOption {
  id: string;
  name: string;
}

interface ProjectField {
  __typename: string;
  id: string;
  name: string;
  options?: FieldOption[];
}

interface DiscoverResult {
  node: {
    fields: {
      nodes: ProjectField[];
    };
  };
}

try {
  const cfg = getConfig();

  console.log(`\n▶ discover-ids`);
  console.log(`  Project: ${cfg.projectId}\n`);

  const result = await graphql<DiscoverResult>(
    `query($project: ID!) {
      node(id: $project) {
        ... on ProjectV2 {
          fields(first: 30) {
            nodes {
              __typename
              ... on ProjectV2SingleSelectField {
                id
                name
                options { id name }
              }
              ... on ProjectV2Field {
                id
                name
              }
            }
          }
        }
      }
    }`,
    { project: cfg.projectId }
  );

  const fields = result.node.fields.nodes;

  for (const field of fields) {
    if (field.__typename === "ProjectV2SingleSelectField" && field.options) {
      console.log(`Field: ${field.name}`);
      console.log(`  ID: ${field.id}`);
      for (const opt of field.options) {
        console.log(`  Option "${opt.name}": ${opt.id}`);
      }
      console.log();
    }
  }

  console.log("Paste the above IDs into your .env file.");
} catch (err) {
  console.error("\n❌ discover-ids failed:", (err as Error).message);
  process.exit(1);
}
