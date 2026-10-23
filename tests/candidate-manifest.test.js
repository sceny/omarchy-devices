import { test } from "node:test";
import assert from "node:assert/strict";
import { manifestUrl, candidateManifest } from "../dev/candidate-manifest.mjs";

const SHA = "a".repeat(40);
const PAPERCLIPAI = "https://github.com/sceny/omarchy-paperclipai";

async function withFetch(stub, run) {
  const real = globalThis.fetch;
  globalThis.fetch = stub;
  try {
    return await run();
  } finally {
    globalThis.fetch = real;
  }
}

test("the manifest URL names the repository given and the commit", () => {
  assert.equal(manifestUrl(PAPERCLIPAI, SHA),
    `https://api.github.com/repos/sceny/omarchy-paperclipai/contents/manifest.json?ref=${SHA}`);
});

test("another plugin's commit gives that plugin's id, read from the commit", async () => {
  const asked = [];
  const manifest = await withFetch(async (url, init) => {
    asked.push({ url, init });
    return new Response(JSON.stringify({ id: "sceny.paperclipai" }), { status: 200 });
  }, () => candidateManifest(PAPERCLIPAI, SHA, "token"));
  assert.equal(manifest.id, "sceny.paperclipai");
  assert.equal(asked[0].url, manifestUrl(PAPERCLIPAI, SHA));
  assert.equal(asked[0].init.headers.Authorization, "Bearer token");
});

test("a manifest that cannot be read is an error, not another plugin's id", async () => {
  await withFetch(async () => new Response("", { status: 404 }), () =>
    assert.rejects(candidateManifest(PAPERCLIPAI, SHA), /GitHub answered 404/));
});
