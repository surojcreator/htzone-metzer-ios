# Metzer — iOS client

[![ios](https://github.com/surojcreator/htzone-metzer-ios/actions/workflows/ios.yml/badge.svg)](https://github.com/surojcreator/htzone-metzer-ios/actions/workflows/ios.yml)

A native SwiftUI client for the HTZone **מצ״ר** account, built on the same API the
Android app uses. It is an independent front end for an account you control.

## Features

- Email/password login with the client-side credential encryption the API expects
- Persistent session via HTTP cookies; optional Keychain credential storage
- Catalog tree taken from `generalDeclaration` (25 top categories, ~495 nodes, merged
  `categories` + `sub_categories`)
- Category landing pulls live children from `getCategory`, shows promo cards from
  `connected_items`, an item preview, and an “all items” entry
- Item grid pages through `getItems` (100 per page) until the server runs out,
  even when `total_items` is missing; “load more” button as a fallback
- Full item detail from `getItem { itemId }`: image gallery, brief, spec groups,
  delivery options, stock/warranty, and a link to the web page
- Variant products (the API's `collected` flag) get a colour/model picker on the
  detail screen, per-variant stock and price, and a `collectedIds` entry on add to
  cart; cards show the distinct `sub_title` and the number of options so products
  that share a title stay distinguishable
- Home banner carousel from `tv_banners`, plus the `elipses` circular quick
  links, and category artwork from `categoriesImages`
- Search with debounce, recent searches, result grid, and category matches
  (the server caps search at 8 results)
- Add to cart, including the metzer-credit popup flow
- Server-backed favourites (`{itemId, itemType}`) with an on-device cache, a
  heart on every card and the detail screen, and a favourites screen
- Recently-viewed rail on the home screen, product sharing, pull-to-refresh, and
  an in-app API diagnostics screen that exercises every read endpoint
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
`JSONValue` because field types vary (strings/numbers, arrays/keyed objects), and
repairs the three malformed shapes this backend emits: a UTF-8 BOM, raw control
characters inside strings, and trailing PHP notices after the payload.

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
| Add to cart | `addToCart` | `itemId`, `quantity`, and `collectedIds: [{collectedId, quantity}]` for collected products |
| Remove from cart | `removeFromCart` | `itemKey` |
| Favourites | `getUserFavorites` | `{}` |
| Add favourite | `addToFavorites` | `itemId`, `itemType` |
| Remove favourite | `removeFromFavorites` | `itemId`, `itemType` |
| Companies (public) | `getCompanies` | `{}` |
| Cities (public) | `getCities` | `{}` |
| Chitabox list (public) | `getChitaboxList` | `{}` |
| Boxit areas | `getBoxitAreas` | `{}` |
| Boxit cities | `getBoxitCities` | `areaId` |
| Boxit lockers | `getBoxitLockers` | `cityCode` |
| Streets | `getStreets` | `cityId` |
| Host URL | `getHostUrl` | `{}` |
| Popup validation | `popup_validate` | `response_key` + popup inputs |
| Orders | `getUserOrders` | `{}` |
| Order detail | `getUserOrder` | `orderId` |
| Wallet | `getUserWallet` | `{}` |
| Cards | `getUserCards` | `{}` |
| Pro state | `checkProState` | `{}` |

Numeric parameters are sanitised server-side to digits only; the app sends plain
values and does not attempt to encode anything special.

`itemType` is the product's `type_id`, defaulting to `1`. Items whose `type_id`
is `banner_item` are promo rows, not products; the app filters them out of
product grids.

### Endpoints used by the official client but not driven yet

The request classes in the Hermes bundle expose the parameter names below. They
are not wired into the iOS app because they change server state (orders,
addresses, credentials) and cannot be verified without a live account.

| Method | Data |
|---|---|
| `verifyCart` | `isQuick` |
| `setCartDeliveries` | per-item `selectedDeliveryValue` |
| `validateCoupon` | coupon code |
| `submitOrder`, `finalizeOrder` | checkout payload |
| `addUserAddress`, `editUserAddress`, `removeUserAddress` | address fields |
| `editUserInformation`, `newPassword`, `forgotPassword` | account fields |
| `addUser`, `SendRegistrationEmail`, `loginByAuthCode`, `loginbyRegisterLink` | registration / SSO |
| `startUserDeleteProcess`, `finalizeUserDelete` | account deletion |
| `rateApp`, `registerPushNotification`, `sendLeadInformation`, `setSettings`, `clearSession`, `errorReprot` | misc |

## Verified against the live API

The published client was exercised against `api/app/metzer/android/1.6/` with a
real session. Public and authenticated calls all returned `status: 1`:

- config/catalog: `generalDeclaration`, `getCategory`, `getItems`,
  `searchQuery`, `getPopularSearches`, `getContentPage`
- session: `loginUser`, `getUserWallet`, `getUserCards`, `getUserOrders`,
  `getCart`, `getUserFavorites`, `checkProState`, `getItem`
- favourites write: `addToFavorites` then `removeFromFavorites` (list restored)
- reference data: `getCompanies`, `getCities`, `getChitaboxList`,
  `getBoxitAreas`, `getHostUrl`, `getItemComments`, `getItemMoreProducts`

Response shapes that drove fixes:

- `items_collected` is a keyed map whose **key is the collected id**; its rows
  carry `title`, `price`, `full_price`, `total_stock`, `max_purchase` but no
  `id`.
- `total_stock` is authoritative. `items_stock.total_active_items` is 0 or
  negative for unlimited/withdrawn rows, so it is only a fallback.
- The variant dimension is often **absent from `extra_features`**; chip labels
  must come from `items_collected.title`, and the group title is matched by
  label overlap rather than by option count.
- Cards expose `last_numbers` (not `last_digits`); comments expose `content`,
  `customer_name` and `score`.
- `getItem` requires a session (`err 150` when anonymous); every other catalog
  call used by the grid is public. The client sends `{itemId, itemType}`, and a
  response carrying `redirectUrl` is shown as an external link instead of being
  treated as a parse failure.
- Image hosts matter: `mediacrm.htzone.co.il` serves `item_image/...`,
  `media.htzone.co.il` serves `cms/...` and `/36/...`, and `/_media/...` belongs
  to `www.htzone.co.il`. All of them answer `403` without a User-Agent.
- Decoding falls back to `JSONSerialization` (top-level fragments) and to
  Windows-1255 for legacy rows, and retries read-only calls once when a body is
  empty or unparseable.

The same checks are available on the device: **חשבון → בדיקת API** runs every
read endpoint and reports pass/fail with latency.

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
- Product detail falls back to the list payload if `getItem` rejects an item
  (`234` product unavailable).
- Variant mapping prefers `items_collected` (per-variant title, price and
  `max_purchase`); for payloads without it the option order is aligned with
  `items_stock` rows and the product price is shown for every option.
- Filters and brand shortcuts are not exposed: `getCategory.filters` and
  `dynamic_fieldsArr` come back empty and `getItems.brands` is `null` for the
  catalog branches tested.
- Favourites use the server list, cached on device so the screen still renders
  offline; a rejected write rolls back the optimistic heart.

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
      LibraryStore.swift        # local favourites + history
      Models.swift
    Features/
      RootView.swift          # splash + login
      MainTabView.swift
      HomeView.swift
      CatalogView.swift
      ItemsView.swift
      SearchView.swift
      ItemDetailView.swift    # detail + metzer credit sheet
      FavoritesView.swift     # favourites grid + heart control
      CartView.swift
      OrdersView.swift
      OrderDetailView.swift
      AccountView.swift
      ContentPageView.swift   # WKWebView for HTML pages
      Components.swift
```
