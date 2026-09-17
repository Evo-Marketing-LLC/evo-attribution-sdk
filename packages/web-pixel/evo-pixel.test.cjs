const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const pixelSource = fs.readFileSync(path.join(__dirname, "evo-pixel.js"), "utf8")

test("drains purchases queued by the documented async bootstrap", () => {
  const requests = []
  const stored = new Map()
  const script = {
    getAttribute(name) {
      if (name === "data-pixel-key") return "pk_test"
      return null
    },
  }
  const window = {
    location: { search: "?evo_cid=evc_queued-click" },
    localStorage: {
      getItem(key) {
        return stored.get(key) ?? null
      },
      setItem(key, value) {
        stored.set(key, value)
      },
    },
    fetch(input, init) {
      requests.push({ input, init })
      return Promise.resolve({ ok: true })
    },
  }

  window.evo = window.evo || function () {
    (window.evo.q = window.evo.q || []).push(arguments)
  }
  window.evo("purchase", { orderId: "queued-order", amount: 49.99, currency: "USD" })

  const document = {
    currentScript: script,
    querySelector() {
      return script
    },
  }

  vm.runInNewContext(pixelSource, { window, document, decodeURIComponent })

  assert.equal(requests.length, 1)
  assert.equal(requests[0].input, "https://dialedapi.evomarketing.co/api/public/attribution/events")
  assert.deepEqual(JSON.parse(requests[0].init.body), {
    pixel_key: "pk_test",
    event_type: "purchase",
    click_token: "evc_queued-click",
    transaction_id: "queued-order",
    amount: 49.99,
    currency: "USD",
    occurred_at: JSON.parse(requests[0].init.body).occurred_at,
  })
  assert.equal(window.evo.q.length, 0)
  assert.equal(window.evo.token(), "evc_queued-click")
})
