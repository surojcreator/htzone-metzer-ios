# Metzer — iOS client

[![ios](https://github.com/surojcreator/htzone-metzer-ios/actions/workflows/ios.yml/badge.svg)](https://github.com/surojcreator/htzone-metzer-ios/actions/workflows/ios.yml)

A native SwiftUI client for the HTZone **מצ״ר** account, built on the same API the
Android app uses. It is an independent front end for an account you control.

## Features

- Email/password login with the client-side credential encryption the API expects
- Persistent session via HTTP cookies; optional Keychain credential storage
- Catalog tree taken from `generalDeclaration` (top categories → subcategories → items)
- Item grid with sort (popular / price asc / price desc) and infinite scroll
- Search with debounce, recent searches, result grid
- Item detail with comments and related products
- Add to cart, including the metzer-credit popup flow
- Cart view with remove and total
- Orders list and order detail (line items, supplier totals, payments)
- Account: wallet, saved cards (masked), addresses, about page
- Full Hebrew RTL, dark theme

## Download

A prebuilt **unsigned** IPA is attached to the
[latest release](https://github.com/surojcreator/htzone-metzer-ios/releases/latest).
It targets `iphoneos` arm64, minimum iOS 16, and carries no signature.
Install it by re-signing with your own Apple ID using Sideloadly, AltStore, or a
similar sideloading tool. It is not an App Store build.

## Build

Requires macOS with Xcode 15+ and an iOS 16+ device/simulator.

```bash
brew install xcodegen          # one-time
cd ios
xcodegen generate
open HTZoneMetzer.xcodeproj
```

In Xcode: select the `HTZoneMetzer` target → Signing & Capabilities → choose your
team → run. The bundle id defaults to `il.co.inmanage.htzone.mzr.clone`; change it
in `project.yml` if needed.

If you prefer not to use XcodeGen: create a new iOS App project (SwiftUI, iOS 16),
delete its generated `ContentView`/`App` files, and drag the `HTZoneMetzer` folder
into the project.

## API notes

Base URL:

```
https://api.htzone.co.il/api/app/metzer/android/1.6/
```

Every call is `POST <base><method>/` with:

```json
{ "data": { ... } }
```

`data` must be the only top-level key. Responses are
`{ "status": 1|0, "err": ..., "data": ... }`. The app decodes into a tolerant
`JSONValue` because field types vary (strings/numbers, arrays/keyed objects).

### Login encryption

```
salt   = 16 random bytes
nonce  = 12 random bytes
key    = PBKDF2-HMAC-SHA256(staticKey, salt, 32767, 16)
ct+tag = AES-GCM(key, nonce, utf8(plaintext))
field  = base64(salt || nonce || ct || tag)
```

Both `email` and `password` are encrypted this way. `staticKey` is the 16-byte
value returned by `BaseEncryption_encryptionKey` in the shipped native library;
the constant lives in `Core/CredentialCrypto.swift`. Implemented with
CommonCrypto + CryptoKit.

### Endpoints used

| Purpose | Method | Data |
|---|---|---|
| Login | `loginUser` | encrypted `email`, `password` |
| Logout | `logout` | `{}` |
| App config / categories / labels | `generalDeclaration` | `{}` |
| Category | `getCategory` | `categoryId` |
| Items | `getItems` | `categoryId`, `page`, optional `sortById` |
| Search | `searchQuery` | `q` |
| Content page | `getContentPage` | `pageId` |
| Popular searches | `getPopularSearches` | `{}` |
| Comments | `getItemComments` | `itemId` |
| Related | `getItemMoreProducts` | `itemId` |
| Cart | `getCart` | `{}` |
| Add to cart | `addToCart` | `itemId`, `quantity` |
| Remove from cart | `removeFromCart` | `itemKey` |
| Popup validation | `popup_validate` | `response_key` + popup inputs |
| Orders | `getUserOrders` | `{}` |
| Order detail | `getUserOrder` | `orderId` |
| Wallet | `getUserWallet` | `{}` |
| Cards | `getUserCards` | `{}` |
| Pro state | `checkProState` | `{}` |

Numeric parameters are sanitised server-side to digits only; the app sends plain
values and does not attempt to encode anything special.

## Security decisions

- The password is encrypted before transmission and is **not** stored by default.
- “Remember me” stores the credentials in the iOS Keychain
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), never in UserDefaults.
- The profile cached for offline launch contains id/name/email/company/address
  lines only.
- Order detail deliberately hides `card_details` — the API returns a full card
  token and national ID there, and the UI never renders them.
- All traffic is HTTPS; the app does not install a custom trust store.

## Limitations

- Checkout is not implemented. Metzer purchases require a registered metzer card;
  `addToCart` returns a `popupObject` asking for the account’s national ID and the
  last six digits of that card. The app renders the popup and submits it via
  `popup_validate`, but the exact validation payload is inferred.
- Product detail is built from search/related payloads; `getItem` is gated on the
  server (returns product-not-available) for this tenant.
- Favourites endpoints require a parameter shape that was not identified, so the
  UI omits favourites.

## Disclaimer

Independent client for an account you own. Not affiliated with, endorsed by, or
supported by HTZone, Inmanage, or Rafael. It talks to the same endpoints as the
official Android app, and those endpoints can change without notice.

## Layout

```
ios/
  project.yml
  HTZoneMetzer/
    App/
      HTZoneMetzerApp.swift
      AppState.swift
      Theme.swift
    Core/
      APIClient.swift
      CredentialCrypto.swift
      JSONValue.swift
      Keychain.swift
      Models.swift
    Features/
      RootView.swift          # splash + login
      MainTabView.swift
      HomeView.swift
      CatalogView.swift
      ItemsView.swift
      SearchView.swift
      ItemDetailView.swift    # detail + metzer credit sheet
      CartView.swift
      OrdersView.swift
      OrderDetailView.swift
      AccountView.swift
      ContentPageView.swift   # WKWebView for HTML pages
      Components.swift
```
