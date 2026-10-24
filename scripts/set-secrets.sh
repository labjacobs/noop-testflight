#!/usr/bin/env bash
# Builds the distribution .p12 from the local private key + Apple's .cer, then stores every value the
# TestFlight workflow needs as GitHub Actions secrets. Run from Git Bash after README steps 1-4.
#
#   scripts/set-secrets.sh
#
# Nothing secret is written into this repo: the key, .cer and .p12 live in ../signing (outside git).
set -euo pipefail
export MSYS_NO_PATHCONV=1

here="$(cd "$(dirname "$0")/.." && pwd)"
signing="$(cd "$here/../signing" && pwd)"
repo="$(cd "$here" && gh repo view --json nameWithOwner -q .nameWithOwner)"

ask() { local var="$1" prompt="$2" def="${3:-}"; local val
  read -r -p "$prompt${def:+ [$def]}: " val; printf -v "$var" '%s' "${val:-$def}"; }

echo "Setting secrets on $repo (signing files from $signing)"
ask TEAM_ID          "Apple Team ID (10 chars, developer.apple.com > Membership)"
ask BUNDLE_ID_PREFIX "Bundle id prefix" "au.com.jacobslab"
ask ASC_KEY_ID       "App Store Connect API Key ID"
ask ASC_ISSUER_ID    "App Store Connect Issuer ID"
ask P8               "Path to AuthKey_<id>.p8" "$(ls "$signing"/AuthKey_*.p8 2>/dev/null | head -1)"
ask CER              "Path to the Apple Distribution .cer" "$(ls "$signing"/*.cer 2>/dev/null | head -1)"

key="$signing/distribution.key"
for f in "$key" "$P8" "$CER"; do [ -f "$f" ] || { echo "Missing file: $f" >&2; exit 1; }; done

# .cer from Apple is DER; make sure it belongs to our private key before going further.
openssl x509 -inform DER -in "$CER" -out "$signing/distribution.pem"
if [ "$(openssl x509 -in "$signing/distribution.pem" -noout -pubkey)" != "$(openssl pkey -in "$key" -pubout)" ]; then
  echo "That .cer was not issued for signing/distribution.csr - did you upload the right CSR?" >&2; exit 1
fi
openssl x509 -in "$signing/distribution.pem" -noout -subject -enddate

# 3DES/SHA1 PBE so macOS's `security import` accepts it regardless of OpenSSL 3 defaults.
p12_pw="$(openssl rand -hex 24)"
openssl pkcs12 -export -inkey "$key" -in "$signing/distribution.pem" -out "$signing/distribution.p12" \
  -name "NOOP Apple Distribution" -passout "pass:$p12_pw" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
printf '%s\n' "$p12_pw" > "$signing/distribution.p12.password"

set_secret() { printf '%s' "$2" | gh secret set "$1" --repo "$repo"; }
set_secret APPLE_TEAM_ID          "$TEAM_ID"
set_secret BUNDLE_ID_PREFIX       "$BUNDLE_ID_PREFIX"
set_secret ASC_KEY_ID             "$ASC_KEY_ID"
set_secret ASC_ISSUER_ID          "$ASC_ISSUER_ID"
set_secret ASC_KEY_P8_BASE64      "$(base64 -w0 "$P8")"
set_secret DIST_CERT_P12_BASE64   "$(base64 -w0 "$signing/distribution.p12")"
set_secret DIST_CERT_P12_PASSWORD "$p12_pw"

echo
gh secret list --repo "$repo"
echo "Done. Start a build with:  gh workflow run testflight.yml --repo $repo"
