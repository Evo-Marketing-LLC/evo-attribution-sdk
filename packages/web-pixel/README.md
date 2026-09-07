# EVO website pixel reference

`evo-pixel.js` is an unchanged reference copy of the browser pixel served from [https://dialed.evomarketing.co/evo-pixel.js](https://dialed.evomarketing.co/evo-pixel.js).

Do not deploy this directory as the hosted pixel. Load the hosted URL in a storefront:

```html
<script async src="https://dialed.evomarketing.co/evo-pixel.js" data-pixel-key="pk_your_brand_key"></script>
```

Then report a purchase from the order-confirmation page:

```html
<script>evo("purchase", { orderId: "1234", amount: 49.99, currency: "USD" });</script>
```
