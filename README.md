# Sale Hunter

An iPhone app that tracks **Ounass Bahrain** men's sale items.

- Browse every men's sale item with filters (discount, category, brand, clothing and shoe size) and sorting
- **NEW** and **PRICE DROP** badges for items you haven't seen before or that got cheaper
- Favorites saved on your phone
- Background alerts: a notification when new items match your alert filters
- Tap any item to open it on Ounass

The app talks to Ounass directly from your phone — there is no server.

## Install

1. Download the latest unsigned IPA on your iPhone:
   **https://github.com/husain-313/sale-hunter/releases/latest/download/SaleHunter.ipa**
2. Open it in your signing app and install.

Every push to `main` that touches the app builds a new IPA automatically (GitHub Actions → **Build iOS app**). You can also run it manually from the Actions tab.

## Project layout

| Path | What it is |
|---|---|
| `SaleHunter/` | SwiftUI source code and assets |
| `project.yml` | XcodeGen spec (the `.xcodeproj` is generated in CI) |
| `.github/workflows/build-ios.yml` | Builds the unsigned IPA and publishes it as a release |

Bundle ID: `com.husain313.salehunter` · iOS 16+
