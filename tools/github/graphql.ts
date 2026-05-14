// Minimal GitHub GraphQL client using Node.js built-in fetch

export async function graphql<T>(
  query: string,
  variables: Record<string, unknown> = {}
): Promise<T> {
  const token = process.env.GITHUB_TOKEN;
  if (!token) throw new Error("GITHUB_TOKEN environment variable is required");

  const res = await fetch("https://api.github.com/graphql", {
    method: "POST",
    headers: {
      Authorization: `bearer ${token}`,
      "Content-Type": "application/json",
      "User-Agent": "github-workflow-cli"
    },
    body: JSON.stringify({ query, variables })
  });

  if (!res.ok) {
    throw new Error(`GitHub API HTTP error: ${res.status} ${res.statusText}`);
  }

  const json = (await res.json()) as { data?: T; errors?: Array<{ message: string }> };

  if (json.errors && json.errors.length > 0) {
    throw new Error(`GraphQL error: ${json.errors.map(e => e.message).join(", ")}`);
  }

  return json.data as T;
}

// GitHub REST API helper
export async function rest<T>(
  path: string,
  options: { method?: string; body?: unknown } = {}
): Promise<T> {
  const token = process.env.GITHUB_TOKEN;
  if (!token) throw new Error("GITHUB_TOKEN environment variable is required");

  const res = await fetch(`https://api.github.com${path}`, {
    method: options.method ?? "GET",
    headers: {
      Authorization: `bearer ${token}`,
      "Content-Type": "application/json",
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "github-workflow-cli"
    },
    ...(options.body ? { body: JSON.stringify(options.body) } : {})
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`GitHub REST API error ${res.status}: ${text}`);
  }

  return res.json() as Promise<T>;
}
