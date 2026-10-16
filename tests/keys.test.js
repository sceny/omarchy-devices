// The Keys page (Model.KEYS), the key handlers in Panel.qml and
// docs/use/keyboard.md name the same keys. Any drift fails the build naming
// the key. All data is the repository's own.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..")
const read = f => fs.readFileSync(path.join(root, f), "utf8")
const src = read("Model.js").replace(/^\.pragma library\s*$/m, "")
const names = [...src.matchAll(/^(?:function|var)\s+([A-Za-z_]\w*)/gm)].map(m => m[1])
const M = new Function(src + "; return {" + names.join(",") + "}")()
const panel = read("Panel.qml")

// One spelling per key: a capital is Shift+letter, Shift+Return is Shift+Enter.
const ARROWS = ["↑", "↓", "←", "→"]
const norm = k => {
  if (/^[A-Z]$/.test(k)) return "Shift+" + k
  return { "PgDown": "PgDn", "Shift+Return": "Shift+Enter", "+": "=" }[k] || k
}
const digits = (a, b) => Array.from({ length: Number(b) - Number(a) + 1 }, (_, i) => String(Number(a) + i))

// A key on the Keys page: tokens split by spaces and "·", "1–9" a range.
const listed = keys => new Set(keys
  .replace(/(\d)–(\d)/g, (_, a, b) => digits(a, b).join(" "))
  .split(/[\s·]+/).filter(Boolean).map(norm))

// A key in docs/use/keyboard.md: `code` spans are keys; the bare words are
// Esc, Tab, Enter, Space, PgUp PgDn, Shift+Tab, Shift+Enter, "arrows".
function docKeys(cell) {
  const keys = []
  const bare = cell.replace(/`(\d)`–`(\d)`/g, (_, a, b) => { keys.push(...digits(a, b)); return " " })
    .replace(/`([^`]+)`/g, (_, k) => { keys.push(k); return " " })
  bare.split(/[\s·/]+/).filter(w => w && w !== "or").forEach(w => w === "arrows" ? keys.push(...ARROWS) : keys.push(w))
  return new Set(keys.map(norm))
}

// The text-key handler's body, with the three views' blocks apart from the rest.
function stripComments(text) { return text.replace(/(^|\s)\/\/.*$/gm, "$1") }
function block(text, open) {
  const at = text.indexOf(open)
  assert.ok(at >= 0, `${open} is found`)
  let depth = 1, i = at + open.length
  while (depth) depth += { "{": 1, "}": -1 }[text[i++]] || 0
  return { start: at, end: i, text: text.slice(at, i) }
}
function handledIn(text) {
  const keys = [...text.matchAll(/\bt === "(.)"/g)].map(m => m[1])
  if (/\bt === Model\.HOME_KEY\b/.test(text)) keys.push(M.HOME_KEY)
  for (const m of text.matchAll(/\bt >= "(\d)" && t <= "(\d)"/g)) keys.push(...digits(m[1], m[2]))
  return new Set(keys.map(norm))
}

const handler = block(stripComments(panel), "onTextKey: function(t) {")
let rest = handler.text
const views = {}
for (const [view, open] of [["Contacts", "if (root.contactsOpen) {"], ["Messages", "if (root.messagesOpen) {"], ["Apps", "if (root.appsOpen) {"]]) {
  const b = block(rest, open)
  views[view] = handledIn(b.text)
  rest = rest.slice(0, b.start) + rest.slice(b.end)
}
const textKeys = handledIn(rest)

// PanelKeyCatcher (Omarchy's, not in this repository) answers these itself;
// the panel's Shortcut items add the page keys and Shift+Enter.
const catcher = new Set(["j", "k", "h", "l", "x", "Enter", "Space", "Esc", "Tab", "Shift+Tab", ...ARROWS])
const shortcuts = new Set([...panel.matchAll(/sequences:\s*\[([^\]]*)\]/g)]
  .flatMap(m => [...m[1].matchAll(/"([^"]+)"/g)].map(s => norm(s[1]))))
const always = new Set([...catcher, ...shortcuts])

const handled = new Set([...always, ...textKeys, ...Object.values(views).flatMap(s => [...s])])
const page = new Set(M.KEYS.flatMap(g => g.keys.flatMap(k => [...listed(k[0])])))

const missing = (have, want) => [...want].filter(k => !have.has(k))

test("the handlers are read: the keys the test depends on are found", () => {
  for (const k of ["?", "0", "c", "Shift+E", "1", "9", "Shift+H", "=", "m", "PgUp", "PgDn", "Shift+Enter"]) assert.ok(handled.has(k), `${k} is read from the handlers`)
  assert.deepEqual([...views.Contacts].sort(), ["/", "Shift+G", "g", "m", "r"].sort())
  assert.ok(views.Messages.has("u") && views.Apps.has("p"))
  assert.ok(page.has("↑") && page.has("1") && page.has("Shift+K") && page.has("Esc"), "the Keys page is read")
})

test("Keys page: every key the panel handles is listed, naming the key", () => {
  assert.deepEqual(missing(page, handled), [], "handled in Panel.qml but not in Model.KEYS")
})

test("Keys page: every key listed has a handler, naming the key", () => {
  assert.deepEqual(missing(handled, page), [], "in Model.KEYS but handled nowhere in Panel.qml")
})

test("Keys page: a view's group is that view's keys and the keys that work everywhere", () => {
  for (const view of ["Messages", "Contacts"]) {
    const group = new Set(M.KEYS.find(g => g.group === view).keys.flatMap(k => [...listed(k[0])]))
    const own = new Set([...views[view], ...always])
    assert.deepEqual(missing(group, views[view]), [], `${view} handles it, its group does not list it`)
    assert.deepEqual(missing(own, group), [], `${view}'s group lists it, the view has no handler`)
  }
})

test("docs/use/keyboard.md: the same keys as the Keys page, naming the key", () => {
  const rows = read("docs/use/keyboard.md").split("\n").filter(l => /^\|/.test(l)).slice(2)
  assert.ok(rows.length > 10, "the table is read")
  const docs = new Set(rows.flatMap(r => [...docKeys(r.split("|")[1])]))
  assert.deepEqual(missing(docs, page), [], "on the Keys page but not in docs/use/keyboard.md")
  assert.deepEqual(missing(page, docs), [], "in docs/use/keyboard.md but not on the Keys page")
})
