// The plugin manifest of one commit of a repository, read from GitHub, so the
// id checked is the candidate's own and never the id of the checkout that runs
// the check.

export function manifestUrl(repoUrl, commit) {
  const slug = new URL(repoUrl).pathname.replace(/^\/+|\/+$/g, "");
  return `https://api.github.com/repos/${slug}/contents/manifest.json?ref=${commit}`;
}

export async function candidateManifest(repoUrl, commit, token) {
  const headers = { Accept: "application/vnd.github.raw", "User-Agent": "marketplace-check" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(manifestUrl(repoUrl, commit), { headers });
  if (!response.ok) throw new Error(`GitHub answered ${response.status} for the manifest of ${commit}`);
  return JSON.parse(await response.text());
}
