# noop-testflight

Builds [ryanbr/noop](https://github.com/ryanbr/noop)'s iOS app in GitHub Actions, signs it with my own
Apple Developer team, and uploads it to TestFlight. Unlike a SideStore/AltStore sideload, this build
has the **HealthKit entitlement**, so NOOP can write WHOOP data into Apple Health, where Bevel picks it up.

- Builds the latest stable upstream release. A daily check rebuilds when upstream ships a new one.
- The watch app is left out, as it is in upstream's sideload `.ipa`.
- TestFlight builds last 90 days, and there's no 7-day re-signing.

Everything below is a one-time setup. `<prefix>` means your bundle id prefix, e.g. `au.com.jacobslab`.
It must be the same everywhere.

## 1. Distribution certificate

`../signing/distribution.csr` was generated locally, and its private key stays in `../signing/`, outside git.

1. Go to [developer.apple.com → Certificates](https://developer.apple.com/account/resources/certificates/list) and click **+**.
2. Choose **Apple Distribution**, then upload `signing/distribution.csr`.
3. Download the `.cer` and save it into the `signing/` folder.

## 2. Identifiers

Go to [Identifiers](https://developer.apple.com/account/resources/identifiers/list) and click **+**.

1. Create an **App Group** with id `group.<prefix>.noop.staging`. Use that exact id, because upstream derives it this way.
2. Create an **App ID** (type *App*) with bundle id `<prefix>.noop`.
   - Tick **HealthKit**.
   - Tick **App Groups**, click *Configure*, and pick the group from step 1.
3. Create another **App ID** with bundle id `<prefix>.noop.widgets`.
   - Tick **App Groups**, click *Configure*, and pick the same group.

## 3. App Store Connect API key

1. Go to [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api).
2. Open **Team Keys** and click **+**. Give it a name like "noop-testflight" and **Admin** access. Admin is needed so the workflow can create provisioning profiles.
3. Download `AuthKey_XXXX.p8` into `signing/`. Apple only lets you download it once.
4. Note the **Key ID** and the **Issuer ID**, which is shown above the keys table.

## 4. App record

1. In [App Store Connect → Apps](https://appstoreconnect.apple.com/apps), click **+** and choose **New App**.
2. Set Platform to **iOS**.
3. Enter any unique name, e.g. "NOOP (Brandon)". The home-screen name stays "NOOP".
4. Set Bundle ID to `<prefix>.noop` and SKU to `noop-personal`.

## 5. GitHub secrets

From Git Bash in this folder:

```bash
scripts/set-secrets.sh
```

The script checks that the `.cer` matches the local key, builds the `.p12`, and sets these secrets:
`APPLE_TEAM_ID`, `BUNDLE_ID_PREFIX`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`,
`DIST_CERT_P12_BASE64`, `DIST_CERT_P12_PASSWORD`.

## 6. Build

```bash
gh workflow run testflight.yml
```

Or go to **Actions → TestFlight → Run workflow**. Leave *ref* blank to get the latest release, or enter `main` for bleeding edge.

## 7. Install

1. In App Store Connect, open the app, go to **TestFlight → Internal Testing**, and click **+**.
2. Create a group, add yourself, and turn on automatic distribution.
3. Install **TestFlight** from the App Store, accept the invite, and install NOOP.
4. Open NOOP, go to **More → Apple Health**, turn on write-back, and allow the permissions.

### Moving over from the sideloaded NOOP

The TestFlight app has a different bundle id, so it starts with an empty database.

1. In the old app, go to **More → Backup & Sync → Back up now**.
2. In the new app, use **Restore from a backup…**.
3. Delete the old app, so only one app talks to the strap.

## Troubleshooting

- **"Profile … lacks com.apple.developer.healthkit"**: the App ID is missing that capability (step 2). Fix it and re-run. The profile is regenerated automatically.
- **Upload rejected for a duplicate build number**: re-run the workflow. The build number includes the run number.
- **Archive fails**: download the `build-logs` artifact from the failed run.
