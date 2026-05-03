#!/bin/bash
set -euo pipefail

# Fetches the vendored sacd_extract binary into SACDRipper/Resources/.
# Idempotent: skips the download if the binary already exists and matches
# the pinned SHA-256.
#
# Run once after cloning, and any time the pinned version changes.

# --- Pinned vendor binary ------------------------------------------------
# Version of EuFlo's sacd-ripper fork that we ship. Bump together with
# SACD_EXTRACT_SHA256 when upgrading.
SACD_EXTRACT_VERSION="0.3.9.3-173"
SACD_EXTRACT_SHA256="6dbfe5c68a2503d8645f75aaf7328a3b318987a35eb48a3137f65e1168be415d"

# Where the binary lives in our GitHub Releases. Edit GITHUB_REPO once after
# you create the repo; the rest is derived. The release tag is created
# manually one time per vendor version and never deleted.
GITHUB_REPO="${GITHUB_REPO:-prietus/sacd-extract}"
SACD_EXTRACT_URL="${SACD_EXTRACT_URL:-https://github.com/${GITHUB_REPO}/releases/download/vendor-sacd_extract-${SACD_EXTRACT_VERSION}/sacd_extract}"

# -------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="$REPO_ROOT/SACDRipper/Resources/sacd_extract"

verify_sha() {
    local file="$1"
    local actual
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    [ "$actual" = "$SACD_EXTRACT_SHA256" ]
}

if [ -f "$DEST" ] && verify_sha "$DEST"; then
    echo "==> sacd_extract already present and verified — nothing to do."
    exit 0
fi

mkdir -p "$(dirname "$DEST")"

echo "==> Downloading sacd_extract ${SACD_EXTRACT_VERSION} from"
echo "    ${SACD_EXTRACT_URL}"
TMP="$(mktemp -t sacd_extract.XXXXXX)"
trap 'rm -f "$TMP"' EXIT
curl -fL --retry 3 -o "$TMP" "$SACD_EXTRACT_URL"

echo "==> Verifying SHA-256..."
if ! verify_sha "$TMP"; then
    actual="$(shasum -a 256 "$TMP" | awk '{print $1}')"
    echo "ERROR: SHA-256 mismatch." >&2
    echo "  expected: $SACD_EXTRACT_SHA256" >&2
    echo "  actual:   $actual" >&2
    exit 1
fi

mv "$TMP" "$DEST"
chmod +x "$DEST"
trap - EXIT

echo "==> sacd_extract installed at $DEST"
