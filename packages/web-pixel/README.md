# EVO website pixel reference

`evo-pixel.js` is an unchanged reference copy of the browser pixel served from [https://dialed.evomarketing.co/evo-pixel.js](https://dialed.evomarketing.co/evo-pixel.js).

Do not deploy this directory as the hosted pixel. Load the hosted URL in a storefront:

```html
<script>
  window.evo = window.evo || function () {
    (window.evo.q = window.evo.q || []).push(arguments);
  };
</script>
<script async src="https://dialed.evomarketing.co/evo-pixel.js" data-pixel-key="pk_your_brand_key"></script>
```

Keep the queue bootstrap before the async script and before every `evo()` call. Calls made while the file downloads are replayed in order when it is ready.

Then report a purchase from the order-confirmation page:

```html
<script>evo("purchase", { orderId: "1234", amount: 49.99, currency: "USD" });</script>
```

`orderId` (or `transactionId`) is required for purchases, renewals, and refunds. Use the stable store transaction id so retries cannot count revenue twice.

For `evo("refund", …)`, pass the refunded amount with either sign. The attribution service stores refunds as a negative absolute value so they reduce net revenue exactly once.
