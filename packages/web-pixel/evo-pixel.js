/*!
 * EVO pixel — reports storefront purchases back to Dialed for creator attribution.
 *
 * Install (paste once, ideally in <head>):
 *   <script async src="https://dialed.evomarketing.co/evo-pixel.js" data-pixel-key="pk_..."></script>
 *
 * Then on the order-confirmation page:
 *   evo("purchase", { orderId: "1234", amount: 99.5, currency: "USD" });
 *
 * Pass a creator code the customer typed at checkout so the sale credits them:
 *   evo("purchase", { orderId, amount, code: "JANE10" });
 *
 * Stripe Checkout can read the captured click token with evo.token(). Shopify
 * storefronts automatically copy a newly captured token into cart attributes.
 *
 * Optional attributes: data-endpoint="https://.../api/public/attribution/events".
 * Nothing in here is allowed to throw into the host page.
 */
/* eslint-disable @typescript-eslint/no-unused-vars -- ES5 has no optional catch binding */
(function (window, document) {
  "use strict"

  var STORAGE_KEY = "evo_attr"
  var MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000
  var DEFAULT_ENDPOINT =
    "https://dialedapi.evomarketing.co/api/public/attribution/events"

  function currentScript() {
    try {
      if (document.currentScript) return document.currentScript
      return document.querySelector('script[src*="evo-pixel"]')
    } catch (e) {
      return null
    }
  }

  var script = currentScript()

  function attr(name) {
    try {
      var value = script && script.getAttribute ? script.getAttribute(name) : null
      return value ? String(value).replace(/^\s+|\s+$/g, "") : ""
    } catch (e) {
      return ""
    }
  }

  var pixelKey = attr("data-pixel-key")
  var endpoint = attr("data-endpoint") || DEFAULT_ENDPOINT

  function readStore() {
    try {
      var raw = window.localStorage.getItem(STORAGE_KEY)
      if (!raw) return null
      var parsed = JSON.parse(raw)
      if (!parsed || typeof parsed.t !== "string" || !parsed.t) return null
      if (typeof parsed.ts !== "number") return null
      if (Date.now() - parsed.ts > MAX_AGE_MS) return null
      return parsed
    } catch (e) {
      // Private mode / in-app webviews throw on storage access.
      return null
    }
  }

  function captureClickToken() {
    try {
      var match = /[?&]evo_cid=([^&#]+)/.exec(window.location.search || "")
      if (!match) return null
      var token = decodeURIComponent(match[1])
      if (!token) return null
      var previous = readStore()
      var stored = {
        t: token,
        ts: Date.now(),
        sent: !!(previous && previous.t === token && previous.sent),
      }
      window.localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify(stored)
      )
      return stored
    } catch (e) {
      return null
    }
  }

  function syncShopifyToken(stored) {
    try {
      if (!stored || stored.sent || !window.Shopify || !window.fetch) return

      // Mark first so reloads and duplicate script tags never send twice.
      stored.sent = true
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(stored))
      window
        .fetch("/cart/update.js", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ attributes: { evo_cid: stored.t } }),
          credentials: "same-origin",
        })
        .catch(function () {
          /* best-effort Shopify cart enrichment */
        })
    } catch (e) {
      /* never break the host page */
    }
  }

  function pick() {
    for (var i = 0; i < arguments.length; i++) {
      var value = arguments[i]
      if (value !== null && value !== undefined && value !== "") return value
    }
    return null
  }

  function send(eventType, props) {
    try {
      if (!pixelKey) return
      var p = props || {}
      var stored = readStore()
      var amount = pick(p.amount, p.revenue)
      var body = {
        pixel_key: pixelKey,
        event_type: eventType ? String(eventType) : "purchase",
      }

      if (stored) body.click_token = stored.t

      var transactionId = pick(p.transactionId, p.orderId)
      if (transactionId !== null) body.transaction_id = String(transactionId)
      if (amount !== null && !isNaN(Number(amount))) body.amount = Number(amount)
      if (p.currency) body.currency = String(p.currency)
      if (p.userId !== null && p.userId !== undefined && p.userId !== "") {
        body.external_user_id = String(p.userId)
      }
      // A creator code typed at checkout attributes the sale on its own, with
      // no click token in the picture.
      if (p.code !== null && p.code !== undefined && p.code !== "") {
        body.code = String(p.code)
      }
      body.occurred_at = new Date().toISOString()

      if (!window.fetch) return
      window
        .fetch(endpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
          keepalive: true,
          mode: "cors",
          credentials: "omit",
        })
        .catch(function () {
          /* delivery is best-effort */
        })
    } catch (e) {
      /* never break the host page */
    }
  }

  try {
    var captured = captureClickToken()
    syncShopifyToken(captured)

    var queued = window.evo && window.evo.q ? window.evo.q : []
    window.evo = send
    window.evo.q = []
    window.evo.token = function () {
      var stored = readStore()
      return stored ? stored.t : null
    }

    for (var i = 0; i < queued.length; i++) {
      try {
        send(queued[i][0], queued[i][1])
      } catch (e) {
        /* skip the bad call, keep draining */
      }
    }
  } catch (e) {
    /* no-op */
  }
})(window, document)
