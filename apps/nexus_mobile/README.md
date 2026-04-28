# Nexus Jobs Scanner

A Flutter Android app that scans company career pages for internship and entry-level job openings using an uploaded company list.

## App Information

- App name: **Nexus Jobs Scanner**
- Package name: `com.nexus.jobscanner`
- Current version: **1.1.0**

## Features

- Import company lists from CSV/XLSX
- Scan public career pages for job listings
- Filter results using include/exclude keywords
- Export job data as CSV or Excel
- Local scan history and saved job results
- Optional Firebase analytics telemetry

## Screenshots

Add screenshots to GitHub release notes and include them in a `docs/screenshots/` directory for reviewers.

## Build Instructions

1. Change into the mobile app directory:
   ```bash
   cd apps/nexus_mobile
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Configure signing and Firebase if needed:
   - Copy `android/key.properties.example` to `android/key.properties`
   - Copy `firebase.json.example` to `firebase.json` if you use Firebase
   - If using Firebase on Android, provide `android/app/google-services.json`
4. Build the release APK:
   ```bash
   flutter build apk --release --no-shrink
   ```
5. Release artifact path:
   ```bash
   build/app/outputs/flutter-apk/app-release.apk
   ```

## Notes

- The repository ignores `key.properties`, keystore files, `google-services.json`, and `firebase.json` so secrets are not committed.
- If `android/release.keystore` is not present, the release build falls back to debug signing for automated CI builds.

## Privacy Policy

See `docs/privacy_policy.md` for the app privacy policy and data handling information.

## Additional Documentation

- Mobile design spec: `apps/nexus_mobile/DESIGN_SPEC.md`
