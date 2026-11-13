const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

test("cursor bounds preserve grouped-list scroll positions", () => {
  const panel = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  const scrolled = []
  const context = {
    cursorActive: false,
    ddOpen: "",
    tab: "locations",
    vpn: { installed: true, loggedIn: true },
    visibleEntries: [{}, {}, {}],
    locationRows: [
      { kind: "entry", entryIndex: 0 },
      { kind: "header" },
      { kind: "entry", entryIndex: 1 },
      { kind: "header" },
      { kind: "entry", entryIndex: 2 },
    ],
    focusSection: "locations",
    locationIndex: 1,
    Qt: { callLater(callback) { callback() } },
    locationList: { positionViewAtIndex(index) { scrolled.push(index) } },
    ListView: { Contain: 1 },
  }
  context.focusHeader = () => { context.focusSection = "header" }
  vm.createContext(context)
  for (const name of ["moveCursor", "displayIndexFor"]) {
    const source = panel.match(new RegExp(`^  function ${name}\\([^)]*\\) \\{[\\s\\S]*?^  \\}`, "m"))
    assert.ok(source, `${name} is present`)
    vm.runInContext(source[0], context)
  }

  context.moveCursor(1)
  assert.equal(context.locationIndex, 2)
  assert.deepEqual(scrolled, [4])
  context.moveCursor(1)
  assert.equal(context.locationIndex, 2)
  assert.deepEqual(scrolled, [4])
  context.moveCursor(-1)
  assert.equal(context.locationIndex, 1)
  assert.deepEqual(scrolled, [4, 2])
  context.locationIndex = 0
  context.moveCursor(-1)
  assert.equal(context.focusSection, "header")
  assert.equal(context.locationIndex, 0)
})
