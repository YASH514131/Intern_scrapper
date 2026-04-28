# Nexus Jobs Scanner

Nexus Jobs Scanner is a Flutter-based Android app for importing company lists, scanning career pages for internship and entry-level openings, filtering results, and exporting job data.

## App Overview

- App name: **Nexus Jobs Scanner**
- Package name: `com.nexus.jobscanner`
- Current version: **1.1.0**
- Release artifact: `apps/nexus_mobile/build/app/outputs/flutter-apk/app-release.apk`

## Features

- Upload company lists in CSV/XLSX format
- Scan public job/career pages for internship listings
- Filter and exclude results by keyword
- Export job data in CSV or Excel format
- Save scan results locally for offline review
- Optional analytics telemetry via Firebase Analytics

## Screenshots

Add app screenshots to the repository or GitHub release notes. Recommended locations:

- `docs/screenshots/`
- GitHub Release attachments

> Screenshots should show the upload flow, scan progress, and results dashboard.

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/YASH514131/Intern_scrapper.git
   cd Intern_scrapper/apps/nexus_mobile
   ```
2. Install Flutter dependencies:
   ```bash
   flutter pub get
   ```
3. If you use Firebase services, copy and complete the example config files:
   - `android/key.properties.example`
   - `firebase.json.example`
   - `android/google-services.json.example`

## Build Instructions

1. Build the release APK:
   ```bash
   flutter build apk --release --no-shrink
   ```
2. The signed APK is created at:
   ```bash
   build/app/outputs/flutter-apk/app-release.apk
   ```

### Release signing

- The app is configured to use `android/key.properties` and a release keystore file at `android/release.keystore` if available.
- If a release keystore is missing, the build falls back to debug signing for CI convenience.
- Do not commit `key.properties`, keystores, or Google service files to the public repo.

## Privacy Policy

The app privacy policy is stored in `docs/privacy_policy.md`.

## OpenAPK Compliance Notes

- The repository includes a public open-source license: `LICENSE`.
- The package name is configured as `com.nexus.jobscanner`.
- The Android app uses only required permissions.
- Local secret files are ignored by Git.
- A GitHub release workflow is included at `.github/workflows/release.yml`.

## Repository Structure

- `apps/nexus_mobile/` — Flutter mobile application
- `backend/nexus_api/` — Backend scraper service
- `docs/privacy_policy.md` — Privacy policy for app submission
- `.github/workflows/release.yml` — GitHub release automation


