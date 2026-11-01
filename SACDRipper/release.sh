#!/bin/bash
set -euo pipefail

# SACDRipper Release Script
# Usage: ./release.sh 0.1.0
#        NOTARIZE=0 ./release.sh 0.1.0   # skip notarization (faster, dev only)
#        PUBLISH=0  ./release.sh 0.1.0   # notarize but don't upload
#
# Builds a Release .app signed with Developer ID + hardened runtime,
# submits to Apple's notarization service, staples the ticket, and
# publishes the zip + marketing site to sacdripper.priet.us.
#
# Notarization is a malware scan, not App Store review — bundled CLI
# tools (sacd_extract here) notarize fine as long as they're signed
# with the same Developer ID and hardened runtime.

VERSION="${1:?Usage: ./release.sh VERSION}"
NOTARIZE="${NOTARIZE:-1}"
PUBLISH="${PUBLISH:-1}"

TEAM_ID="LFTD9T269J"
SIGN_ID="Developer ID Application: carlos prieto ortiz ($TEAM_ID)"
KEYCHAIN_PROFILE="notarytool-profile"

SITE_DIR="/Users/carlos/sacdripper-site"
PUBLISH_HOST="teraflops@mail.priet.us"
PUBLISH_PATH="/srv/sites/sacdripper-site"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED="/tmp/SACDRipper-build"
APP_OUT="/tmp/SACDRipper.app"
ZIP_OUT="/tmp/SACDRipper-${VERSION}.zip"

cd "$PROJECT_DIR"

if [ "$PUBLISH" = "1" ]; then
    # Fail before building/uploading anything, not after the site is live.
    echo "==> Pre-flight checks for publishing..."
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "ERROR: working tree has uncommitted changes; commit them first." >&2
        exit 1
    fi
    git fetch --quiet
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse '@{u}')" ]; then
        echo "ERROR: HEAD is not in sync with $(git rev-parse --abbrev-ref '@{u}'); push (or pull) first." >&2
        exit 1
    fi
    if gh release view "v${VERSION}" >/dev/null 2>&1; then
        echo "ERROR: GitHub release v${VERSION} already exists." >&2
        exit 1
    fi
fi
RELEASE_COMMIT="$(git rev-parse HEAD)"

echo "==> Ensuring vendored sacd_extract is present..."
"$PROJECT_DIR/../scripts/bootstrap.sh"

echo "==> Generating Xcode project from project.yml..."
xcodegen generate

echo "==> Cleaning previous build artifacts..."
rm -rf "$DERIVED" "$APP_OUT" "$ZIP_OUT"

echo "==> Building Release v${VERSION}..."
xcodebuild \
    -project SACDRipper.xcodeproj \
    -scheme SACDRipper \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_ID" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
    build \
    | grep -E "(error|warning):|^\*\*" || true

BUILT_APP="$DERIVED/Build/Products/Release/SACDRipper.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "ERROR: build did not produce $BUILT_APP" >&2
    exit 1
fi

echo "==> Copying to $APP_OUT..."
cp -R "$BUILT_APP" "$APP_OUT"

# Sign inside-out. The bundled sacd_extract binary ships ad-hoc signed
# from EuFlo; re-sign with our Developer ID + hardened runtime before
# sealing the enclosing bundle, otherwise notarization rejects it with
# "The signature of the binary is invalid."
echo "==> Re-signing bundled sacd_extract..."
NESTED_BIN="$APP_OUT/Contents/Resources/sacd_extract"
codesign --force --options runtime --timestamp \
    --sign "$SIGN_ID" "$NESTED_BIN"

echo "==> Signing app bundle..."
codesign --force --options runtime --timestamp \
    --sign "$SIGN_ID" "$APP_OUT"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_OUT"
codesign -dv --verbose=4 "$APP_OUT" 2>&1 \
    | grep -E "(Identifier|TeamIdentifier|Authority|Sealed Resources|Signature|Hardened)"

if [ "$NOTARIZE" != "1" ]; then
    echo "==> Zipping for distribution (no notarization)..."
    ditto -c -k --keepParent "$APP_OUT" "$ZIP_OUT"
    echo
    echo "==> Done (signed, NOT notarized)."
    echo "    App: $APP_OUT"
    echo "    Zip: $ZIP_OUT"
    exit 0
fi

echo "==> Wrapping into zip for notarization..."
ditto -c -k --keepParent "$APP_OUT" "$ZIP_OUT"

echo "==> Submitting to Apple notarization service (1-5 min typical)..."
# --wait blocks until Apple returns Accepted / Invalid. On Invalid, pull
# the log with: xcrun notarytool log <submission-id> --keychain-profile $KEYCHAIN_PROFILE
xcrun notarytool submit "$ZIP_OUT" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

echo "==> Stapling notarization ticket to the .app..."
xcrun stapler staple "$APP_OUT"

echo "==> Re-zipping stapled .app for distribution..."
rm -f "$ZIP_OUT"
ditto -c -k --keepParent "$APP_OUT" "$ZIP_OUT"

echo "==> Final Gatekeeper assessment (should pass):"
spctl --assess --type exec --verbose=4 "$APP_OUT"

if [ "$PUBLISH" != "1" ]; then
    echo
    echo "==> Publish skipped (PUBLISH=$PUBLISH)."
    echo "    App: $APP_OUT"
    echo "    Zip: $ZIP_OUT"
    exit 0
fi

echo "==> Refreshing sitemap.xml lastmod to today..."
cat > "$SITE_DIR/public/sitemap.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://sacdripper.priet.us/</loc>
    <lastmod>$(date -u +%Y-%m-%d)</lastmod>
  </url>
</urlset>
EOF

echo "==> Building marketing site with version ${VERSION}..."
# Astro reads PUBLIC_APP_VERSION at build time via import.meta.env, so
# the source stays clean across releases and $VERSION is the single
# source of truth. node@18 is keg-only in homebrew; prepend its bin
# dir so npm is on PATH when the script runs from a fresh shell.
NODE_BIN="/opt/homebrew/opt/node@18/bin"
(cd "$SITE_DIR" && PATH="$NODE_BIN:$PATH" PUBLIC_APP_VERSION="$VERSION" npm run build)

echo "==> Uploading zip ${ZIP_OUT} to ${PUBLISH_HOST}:${PUBLISH_PATH}/..."
scp "$ZIP_OUT" "${PUBLISH_HOST}:${PUBLISH_PATH}/"

echo "==> Syncing site ${SITE_DIR}/dist/ to ${PUBLISH_HOST}:${PUBLISH_PATH}/..."
# --delete cleans up stale hashed assets from previous builds. The
# --exclude keeps every versioned zip intact, so old download links
# keep resolving even after we ship a new build.
rsync -av --delete \
    --exclude 'SACDRipper-*.zip' \
    "$SITE_DIR/dist/" \
    "${PUBLISH_HOST}:${PUBLISH_PATH}/"

echo "==> Creating GitHub release v${VERSION}..."
# Mirrors the same zip as a GitHub Release asset so users can pull from
# github.com/prietus/sacd-extract/releases as well as the marketing site.
# --latest marks this as the current release. Fails loudly if v$VERSION
# already exists, which is the right behaviour — don't silently
# overwrite a published tag.
gh release create "v${VERSION}" "$ZIP_OUT" \
    --target "$RELEASE_COMMIT" \
    --title "SACDRipper ${VERSION}" \
    --latest \
    --notes "Download: [\`SACDRipper-${VERSION}.zip\`](https://github.com/prietus/sacd-extract/releases/download/v${VERSION}/SACDRipper-${VERSION}.zip) · Mirror: https://sacdripper.priet.us"

echo "==> Pinging IndexNow (Bing, Yandex, Seznam, Naver)..."
ssh "$PUBLISH_HOST" "~/indexnow.sh https://sacdripper.priet.us/" || \
    echo "WARN: IndexNow ping failed (release still published)."

echo
echo "==> Done."
echo "    App:     $APP_OUT"
echo "    Zip:     $ZIP_OUT  ($(du -h "$ZIP_OUT" | cut -f1))"
echo "    Version: $VERSION"
echo "    Signed:  $SIGN_ID"
echo "    Status:  notarized + stapled + published"
echo "    Site:    https://sacdripper.priet.us/"
echo
echo "    Open with: open \"$APP_OUT\""
