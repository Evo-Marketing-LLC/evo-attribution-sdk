# EVO Attribution for React Native

Add EVO install and purchase attribution to an Expo or bare React Native app. The package has no runtime or peer dependencies: provide the storage and clipboard adapters your app already uses.

## Install

```bash
npm install @evomarketing/attribution-react-native
```

## Expo

Configure once during app startup. Clipboard matching is opt-in because the operating system may show a paste notification.

```ts
import AsyncStorage from "@react-native-async-storage/async-storage";
import * as Clipboard from "expo-clipboard";
import {
  configureEvoAttribution,
  trackInstall,
  trackPurchase,
} from "@evomarketing/attribution-react-native";

configureEvoAttribution({
  pixelKey: "pk_your_brand_key",
  platform: "ios", // or "android"
  storage: AsyncStorage,
  getClipboard: Clipboard.getStringAsync,
  appVersion: "1.0.0",
});

await trackInstall(true);
await trackPurchase("store-transaction-id", 49.99, "USD");
```

When a new user types a creator code in the app, pass it as the second argument to `trackInstall`. At checkout, pass it as the fourth argument to `trackPurchase`.

```ts
await trackInstall(true, enteredCode);
await trackPurchase("store-transaction-id", 49.99, "USD", enteredCode);
```

For a TestFlight or store-sandbox purchase, pass the optional fifth argument so the event can validate the connection without entering production totals:

```ts
await trackPurchase("sandbox-transaction-id", 49.99, "USD", undefined, {
  sandbox: true,
});
```

## Bare React Native

Any adapter with `getItem` and `setItem` works, including AsyncStorage, MMKV, and secure-store wrappers.

```ts
import AsyncStorage from "@react-native-async-storage/async-storage";
import Clipboard from "@react-native-clipboard/clipboard";
import { Platform } from "react-native";
import {
  configureEvoAttribution,
  trackInstall,
  trackPurchase,
} from "@evomarketing/attribution-react-native";

configureEvoAttribution({
  pixelKey: "pk_your_brand_key",
  platform: Platform.OS === "ios" ? "ios" : "android",
  storage: AsyncStorage,
  getClipboard: () => Clipboard.getString(),
});

await trackInstall(true);
await trackPurchase("store-transaction-id", 49.99);
```

`trackInstall` creates and persists an installation UUID. It marks the install as reported only after a successful response, so a network failure retries on the next launch. The helper reads a clipboard value only when requested and sends it only when it begins with `evc_`.

For tests and demos, the package includes a non-persistent adapter:

```ts
import { memoryStorage } from "@evomarketing/attribution-react-native";

configureEvoAttribution({
  pixelKey: "pk_your_brand_key",
  platform: "ios",
  storage: memoryStorage(),
});
```

Do not use `memoryStorage()` for production installs because its values disappear when the process restarts.

## RevenueCat and Superwall

Use the same persistent install ID as a subscriber or user attribute after configuring EVO:

```ts
Purchases.setAttributes({ evo_install_id: await getEvoInstallId() });
Superwall.shared.setUserAttributes({ evo_install_id: await getEvoInstallId() });
```

For a direct Apple App Store connection, the equivalent Swift value is the StoreKit 2 `appAccountToken`:

```swift
try await product.purchase(options: [.appAccountToken(UUID(uuidString: EVOAttribution.installId)!)])
```

## Test it

1. Use a real Brand pixel key from **Results → Attribution → Developer setup** in the Dialed client portal.
2. Open one of the Brand's app attribution links on a device, install or freshly launch the app, and call `console.log(await trackInstall(true))`.
3. Confirm the result reports `attributed`, `resolution_method`, and `confidence`, then verify the install in the portal.
4. Call `trackPurchase` with a unique test transaction ID and confirm the conversion. For TestFlight or a store sandbox, pass `{ sandbox: true }` as the fifth argument. Sandbox events confirm the connection but are excluded from production totals. Reusing a transaction ID is deduplicated server-side.

A successful install is reported once per persistent app installation. Use a fresh install or cleared app storage when repeating the end-to-end install test.

## API

- `configureEvoAttribution(options)` configures the pixel key, `ios` or `android` platform, storage, and optional endpoint, app version, and clipboard reader.
- `trackInstall(readClipboard?, code?)` resolves the first install and returns its attribution result, or `null` when already reported or when the attempt fails.
- `trackPurchase(transactionId, amount, currency?, code?, options?)` reports a deduplicated purchase and never rejects into host tracking code. Set `options.sandbox` for TestFlight or store-sandbox transactions.
- `getEvoInstallId()` returns the persistent UUID for billing-provider attributes.
- `EVO_ATTRIBUTION_VERSION` is the package/SDK version sent in every request.

Tracking failures are logged with the `[EVOAttribution]` prefix and otherwise contained. `getEvoInstallId()` must be called after configuration.
