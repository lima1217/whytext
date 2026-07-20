#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="WhyText"
APP_ID="com.whytext.local"
ICON_PATH="$ROOT_DIR/Resources/AppIcon.icns"
LOCAL_SIGNING_IDENTITY="WhyText Local Code Signing"
LOCAL_SIGNING_PASSWORD="whytext-local-signing"

CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/clang-module-cache}"
SWIFTPM_CACHE_PATH="${SWIFTPM_CACHE_PATH:-/tmp/swiftpm-cache}"

find_codesigning_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/^[[:space:]]*[0-9]+\\) [A-F0-9]+ "(.+)".*$/\\1/p' \
    | awk '
      /^Developer ID Application:/ { print; exit }
      /^Apple Development:/ { candidate = candidate ? candidate : $0 }
      END { if (candidate) print candidate }
    '
}

has_codesigning_identity() {
  local identity="$1"
  security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$identity\""
}

create_local_codesigning_identity() {
  if has_codesigning_identity "$LOCAL_SIGNING_IDENTITY"; then
    return
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    echo "No code signing identity found and openssl is unavailable." >&2
    echo "Install an Apple Development certificate, or install openssl so this script can create a local signing identity." >&2
    exit 1
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  cat > "$tmpdir/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = v3_req
prompt = no

[ dn ]
CN = $LOCAL_SIGNING_IDENTITY
O = WhyText Local

[ v3_req ]
basicConstraints = critical,CA:true
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

  openssl req \
    -new \
    -newkey rsa:2048 \
    -x509 \
    -days 3650 \
    -nodes \
    -keyout "$tmpdir/key.pem" \
    -out "$tmpdir/cert.pem" \
    -config "$tmpdir/openssl.cnf" >/dev/null 2>&1

  openssl pkcs12 \
    -legacy \
    -export \
    -out "$tmpdir/identity.p12" \
    -inkey "$tmpdir/key.pem" \
    -in "$tmpdir/cert.pem" \
    -name "$LOCAL_SIGNING_IDENTITY" \
    -passout "pass:$LOCAL_SIGNING_PASSWORD" >/dev/null 2>&1

  security import "$tmpdir/identity.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$LOCAL_SIGNING_PASSWORD" \
    -A \
    -T /usr/bin/codesign >/dev/null

  security add-trusted-cert \
    -d \
    -r trustRoot \
    -p codeSign \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    "$tmpdir/cert.pem" >/dev/null
}

build_arch() {
  local arch="$1"
  local build_path="$ROOT_DIR/.build/universal-$arch"
  echo "Building $APP_NAME (release, $arch)..." >&2
  CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_PATH" \
    swift build -c release --arch "$arch" \
    --cache-path "$SWIFTPM_CACHE_PATH" \
    --scratch-path "$build_path" >/dev/null
  local bin_dir
  bin_dir=$(CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_PATH" \
    swift build -c release --arch "$arch" \
    --cache-path "$SWIFTPM_CACHE_PATH" \
    --scratch-path "$build_path" \
    --show-bin-path)
  local bin_path="$bin_dir/$APP_NAME"
  if [[ ! -f "$bin_path" ]]; then
    echo "Binary not found: $bin_path" >&2
    exit 1
  fi
  printf '%s\n' "$bin_path"
}

ARM64_BIN="$(build_arch arm64)"
X86_64_BIN="$(build_arch x86_64)"

DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Creating universal binary..."
lipo -create -output "$MACOS_DIR/$APP_NAME" "$ARM64_BIN" "$X86_64_BIN"
chmod +x "$MACOS_DIR/$APP_NAME"

if [[ -f "$ICON_PATH" ]]; then
  cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"
else
  echo "Warning: icon file not found at $ICON_PATH" >&2
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$APP_ID</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.1</string>
  <key>CFBundleVersion</key>
  <string>5</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

SIGNING_IDENTITY="${CODESIGN_IDENTITY:-$(find_codesigning_identity)}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  create_local_codesigning_identity
  SIGNING_IDENTITY="$LOCAL_SIGNING_IDENTITY"
fi

# Remove quarantine and sign with a stable identity. TCC privacy grants, such as
# Accessibility, are tied to the app identity; ad-hoc signatures change with
# every build and can make macOS forget an existing grant.
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
codesign --force --deep --timestamp=none --sign "$SIGNING_IDENTITY" "$APP_DIR"

echo "Built: $APP_DIR"
echo "Architectures: $(lipo -archs "$MACOS_DIR/$APP_NAME")"
echo "Signed with: $SIGNING_IDENTITY"
echo "Run: open \"$APP_DIR\""
