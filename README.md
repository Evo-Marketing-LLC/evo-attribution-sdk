# EVO Attribution SDK

## What this does

Add install and purchase attribution to an iOS or React Native app in a few minutes. The SDK creates one persistent install ID, reports the first successful install once, and uses that same ID to connect later purchases. You can also pass the install ID to RevenueCat, Superwall, or Apple so subscription and App Store events join the same attribution record.

## Install

### Xcode

In Xcode, choose **File → Add Package Dependencies**, then paste:

```text
https://github.com/Evo-Marketing-LLC/evo-attribution-sdk
```

Select a dependency rule starting at `0.1.0`, add the `EVOAttribution` library to your app target, and import it:

```swift
import EVOAttribution
```

### React Native

```bash
npm install @evo-marketing/attribution-react-native
```

The package has no peer dependencies. Bring the storage and optional clipboard adapters already used by your app.

## Quick start

### Swift

Configure once during startup, then report the install. Clipboard access is opt-in because iOS may show paste UI; EVO accepts only clipboard strings beginning with `evc_`.

```swift
import EVOAttribution

EVOAttribution.configure(pixelKey: "pk_your_brand_key")
_ = await EVOAttribution.trackInstall(readClipboard: true)

await EVOAttribution.trackPurchase(
    transactionId: transaction.id,
    amount: 49.99,
    currency: "USD"
)
```

If a user types a creator code in the app or at checkout, pass it as `code:` to `trackInstall` or `trackPurchase`.

For a TestFlight or StoreKit sandbox purchase, either mark the scalar call explicitly or pass the verified StoreKit 2 transaction and let EVO infer its environment:

```swift
await EVOAttribution.trackPurchase(
    transactionId: "sandbox-transaction-id",
    amount: 49.99,
    sandbox: true
)

await EVOAttribution.trackPurchase(
    transaction: transaction,
    amount: 49.99,
    currency: "USD"
)
```

The StoreKit overload uses `transaction.environment == .sandbox` when that typed API is available and keeps an iOS 15-compatible fallback. If you do not pass a StoreKit transaction, `sandbox` defaults to `false`, so the caller must identify sandbox purchases.

### React Native

```ts
import AsyncStorage from "@react-native-async-storage/async-storage";
import * as Clipboard from "expo-clipboard";
import {
  configureEvoAttribution,
  trackInstall,
  trackPurchase,
} from "@evo-marketing/attribution-react-native";

configureEvoAttribution({
  pixelKey: "pk_your_brand_key",
  platform: "ios",
  storage: AsyncStorage,
  getClipboard: () => Clipboard.getStringAsync(),
});

await trackInstall(true);
await trackPurchase("store-transaction-id", 49.99, "USD");
```

Pass an optional creator code as the second argument to `trackInstall` or the fourth argument to `trackPurchase`. Failed network and storage operations during tracking are contained by the SDK; an install is marked reported only after a successful HTTP response, so a later call or launch can retry it.

For TestFlight or store-sandbox purchases, pass the optional fifth argument:

```ts
await trackPurchase("sandbox-transaction-id", 49.99, "USD", undefined, {
  sandbox: true,
});
```

Both forms send `sandbox: true` so the attribution service can keep test purchases out of live revenue totals.

## If you use RevenueCat, Superwall, or Apple direct

Use EVO's persistent install ID as the `evo_install_id` subscriber or user attribute.

```swift
Purchases.shared.attribution.setAttributes(["evo_install_id": EVOAttribution.installId])
Superwall.shared.setUserAttributes(["evo_install_id": EVOAttribution.installId])
try await product.purchase(options: [.appAccountToken(UUID(uuidString: EVOAttribution.installId)!)])
```

```ts
Purchases.setAttributes({ evo_install_id: await getEvoInstallId() });
Superwall.shared.setUserAttributes({ evo_install_id: await getEvoInstallId() });
```

The StoreKit 2 `appAccountToken` line applies when you connect Apple directly instead of using RevenueCat or Superwall. StoreKit 1 apps can use the same value for `payment.applicationUsername`.

## Website pixel

Storefronts can load the hosted pixel and report the purchase on the confirmation page:

```html
<script async src="https://dialed.evomarketing.co/evo-pixel.js" data-pixel-key="pk_your_brand_key"></script>
<script>evo("purchase", { orderId: "1234", amount: 49.99, currency: "USD" });</script>
```

The hosted file is [https://dialed.evomarketing.co/evo-pixel.js](https://dialed.evomarketing.co/evo-pixel.js). [`packages/web-pixel/evo-pixel.js`](packages/web-pixel/evo-pixel.js) is a reference copy and is not the hosted asset.

## Get your pixel key

In the Dialed client portal, open **Results → Attribution → Developer setup**. Copy the Brand pixel key shown there and use it in `configure` or `configureEvoAttribution`.

## How matching works

EVO uses the first successful match:

1. A valid `evc_` clipboard click token for the same Brand: `clipboard`, confidence `0.95`.
2. An active creator code for the same Brand: `code`, confidence `0.9`.
3. A recent matching app-link click by IP hash and platform: `ip`, confidence `0.6`. EVO considers only the previous 24 hours and refuses ambiguous groups of four or more matching clicks.
4. If nothing matches, EVO still records the install as `unattributed`, confidence `0`.

A purchase can resolve from its own click token or creator code, then from the matched install, before falling back to unattributed. Clipboard and creator-code matches are deterministic; IP matching is useful for reporting but is not payout-grade.

## Privacy

The app stores only a random install UUID and a flag recording whether the install request succeeded, under `evo_install_id` and `evo_install_reported`. The SDK sends the pixel key, install ID, platform, app and SDK versions, timestamps, and only the optional sandbox status, clipboard token, or creator code the host app chooses to provide. It does not collect an advertising ID, contacts, photos, or a raw IP address.

EVO never stores raw visitor IPs for app-install matching. The service stores secret-keyed SHA-256 hashes only for app-link clicks, uses them only during the 24-hour matching window, and removes them after that window.

## Versioning

Releases use semantic version tags such as `v0.1.0`. npm publishes the matching package version, while Swift Package Manager consumes the Git tag directly. In a manifest, depend on this package from `0.1.0`:

```swift
.package(
    url: "https://github.com/Evo-Marketing-LLC/evo-attribution-sdk",
    from: "0.1.0"
)
```

The public Swift `EVOAttribution.version` and React Native `EVO_ATTRIBUTION_VERSION` constants match the release tag without its `v` prefix.

## Support

For a pixel key or attribution setup issue, use **Results → Attribution → Developer setup** in the Dialed client portal or contact your EVO Marketing representative. Include the SDK version, platform, and whether the install call returned a result; never send customer clipboard contents or credentials.
