#!/usr/bin/env node
// The marketplace's own checks on one commit of this repository, before the
// marketplace's bots see it. It is the "Validate plugin update" workflow's two
// steps (scripts/validate-plugin-update.mjs, then scripts/security-baseline.mjs)
// run from a checkout of the marketplace, with one difference: the commit is
// the one given here, not the head of the default branch, because a pull
// request into main is not the head yet. Nothing of the marketplace is copied.
//
//   MARKETPLACE_DIR=<checkout> node dev/marketplace-check.mjs <commit-sha> [out-dir]
//
// Reads GITHUB_TOKEN (the bots' token; without it GitHub's rate limit applies).
// Writes update-validation-report.md, update-security-baseline-report.md and
// update-security-baseline.json to out-dir (default: the current folder), the
// bots' report files. Exit 0: both ran (a baseline that needs a maintainer's
// review is still 0); 1: the marketplace would answer "needs fixes"; 2: the
// check could not complete.
import { spawnSync } from "node:child_process";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { resolve, join } from "node:path";
import { pathToFileURL } from "node:url";

const marketplace = process.env.MARKETPLACE_DIR;
const commit = (process.argv[2] || "").toLowerCase();
const outDir = resolve(process.argv[3] || ".");
const repoRoot = resolve(import.meta.dirname, "..");
const repoUrl = process.env.CHECK_REPO_URL || "https://github.com/sceny/omarchy-devices";

if (!marketplace || !/^[a-f0-9]{40}$/.test(commit)) {
  console.error("usage: MARKETPLACE_DIR=<marketplace checkout> marketplace-check.mjs <40-hex commit> [out-dir]");
  process.exit(2);
}

const load = (name) => import(pathToFileURL(join(marketplace, "scripts", name)).href);

// The text a maintainer's verify issue would carry, so the marketplace's own
// parser reads the request.
async function requestBody(pluginId, ack) {
  return `### Verification action

Verify and publish a newer upstream commit

### Plugin ID

${pluginId}

### Repository URL

${repoUrl}

### Target commit

${commit}

### Verification acknowledgment

- [x] ${ack}

### Standard installation acknowledgment

- [ ] I confirm that this listed root plugin supports the standard Omarchy installation path and does not require manual setup.
`;
}

async function main() {
  await mkdir(outDir, { recursive: true });
  const [{ inspectListedPluginSource, CatalogCheckError }, update, subject, request] = await Promise.all([
    load("build-catalog.mjs"),
    load("plugin-update.mjs"),
    load("verification-subject.mjs"),
    load("plugin-verification-request.mjs"),
  ]);
  const manifest = JSON.parse(await readFile(join(repoRoot, "manifest.json"), "utf8"));
  const registry = JSON.parse(await readFile(join(marketplace, "registry.json"), "utf8"));
  const parsed = subject.canonicalRepositoryRequest(
    registry,
    update.parsePluginUpdateRequest(await requestBody(manifest.id, request.pluginVerificationAcknowledgment)),
  );
  const source = update.sourceForPluginUpdate(registry, parsed);
  let inspection;
  try {
    inspection = await inspectListedPluginSource({ ...source, snapshotCommit: commit });
  } catch (error) {
    if (!(error instanceof CatalogCheckError)) throw error;
    console.error(`::error::marketplace compatibility check: ${error.message}`);
    throw new update.PluginUpdateError(
      "update-compatibility-invalid",
      "The update commit did not pass marketplace compatibility validation",
    );
  }
  // The listed snapshot itself is a valid candidate here, unlike on an update.
  const result = update.resolvePluginUpdate(registry, parsed, inspection, { allowCurrentCommit: true });
  const metadataPath = join(outDir, "update-validation-metadata.json");
  await writeFile(metadataPath, `${JSON.stringify({
    schemaVersion: 1,
    context: "update",
    repoUrl: parsed.repoUrl,
    repository: parsed.repository,
    defaultBranch: inspection.defaultBranch,
    commitSha: inspection.commitSha,
    pluginIds: result.pluginIds,
    listedPlugins: result.manifests.map((m) => ({ pluginId: m.id, manifestPathHint: m.path })),
    entryPoints: [...new Set(result.manifests.flatMap((m) => m.entryPoints || []))].sort(),
  }, null, 2)}\n`);
  await writeFile(
    join(outDir, "update-validation-report.md"),
    update.buildPluginUpdateValidationReport({ ...result, request: parsed }),
  );
  return metadataPath;
}

let metadataPath;
try {
  metadataPath = await main();
} catch (error) {
  const load2 = await import(pathToFileURL(join(marketplace, "scripts", "plugin-update.mjs")).href);
  const failure = load2.publicPluginUpdateFailure(error);
  console.error(`Plugin update validation failed [${failure.code}]`);
  await writeFile(join(outDir, "update-validation-report.md"), `<!-- marketplace-update-validation -->
## Plugin update validation

❌ **Validation failed:** ${failure.reason}
`);
  process.exit(failure.code === "update-internal-error" ? 2 : 1);
}

const baseline = spawnSync(process.execPath, [
  join(marketplace, "scripts", "security-baseline.mjs"),
  `--metadata=${metadataPath}`,
  `--json=${join(outDir, "update-security-baseline.json")}`,
], { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"], maxBuffer: 64 * 1024 * 1024 });
await writeFile(join(outDir, "update-security-baseline-report.md"), baseline.stdout || "");
process.exit(baseline.status === 0 ? 0 : 2);
