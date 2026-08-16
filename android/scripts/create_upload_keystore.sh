#!/usr/bin/env bash
# Create a Play Store upload keystore + local android/key.properties for First Sign.
# Never prints or commits passwords. Run from repo root or any directory:
#   bash android/scripts/create_upload_keystore.sh

set -euo pipefail

ANDROID_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEYSTORE_PATH="$ANDROID_DIR/upload-keystore.jks"
KEY_PROPS_PATH="$ANDROID_DIR/key.properties"
ALIAS="upload"

find_keytool() {
  if command -v keytool >/dev/null 2>&1; then
    command -v keytool
    return
  fi
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/keytool" ]]; then
    echo "$JAVA_HOME/bin/keytool"
    return
  fi
  echo "keytool not found. Install a JDK and ensure keytool is on PATH (or set JAVA_HOME)." >&2
  exit 1
}

echo ""
echo "First Sign — create Play Store upload keystore"
echo "Android dir: $ANDROID_DIR"
echo "Keystore:    $KEYSTORE_PATH"
echo "Alias:       $ALIAS"
echo ""

if [[ -f "$KEYSTORE_PATH" ]]; then
  echo "Refusing to overwrite existing keystore: $KEYSTORE_PATH" >&2
  echo "Back it up, then delete/move it only if you intend to replace it." >&2
  exit 1
fi

KEYTOOL="$(find_keytool)"
echo "Using keytool: $KEYTOOL"
echo ""
echo "You will be prompted for passwords and certificate fields."
echo "Store passwords in a password manager — losing them blocks app updates."
echo ""

read -r -s -p "Keystore store password: " STORE_PASSWORD
echo ""
read -r -s -p "Key password (often same as store password): " KEY_PASSWORD
echo ""

if [[ -z "$STORE_PASSWORD" || -z "$KEY_PASSWORD" ]]; then
  echo "Passwords cannot be empty." >&2
  exit 1
fi

read -r -p "Your name / organization (CN) [First Sign]: " CN
CN="${CN:-First Sign}"
read -r -p "Organizational unit (OU) [Mobile]: " OU
OU="${OU:-Mobile}"
read -r -p "Organization (O) [First Sign]: " O
O="${O:-First Sign}"
read -r -p "City (L) [New York]: " L
L="${L:-New York}"
read -r -p "State (ST) [NY]: " ST
ST="${ST:-NY}"
read -r -p "Country code (C) [US]: " C
C="${C:-US}"

DNAME="CN=$CN, OU=$OU, O=$O, L=$L, ST=$ST, C=$C"

echo ""
echo "Generating keystore (validity ~27 years)..."

"$KEYTOOL" -genkeypair -v \
  -keystore "$KEYSTORE_PATH" \
  -storetype JKS \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias "$ALIAS" \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "$DNAME"

# storeFile is relative to android/app/ (see app/build.gradle.kts)
cat >"$KEY_PROPS_PATH" <<EOF
storePassword=$STORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$ALIAS
storeFile=../upload-keystore.jks
EOF

unset STORE_PASSWORD KEY_PASSWORD

echo ""
echo "Done."
echo "  Keystore:       $KEYSTORE_PATH  (gitignored)"
echo "  key.properties: $KEY_PROPS_PATH  (gitignored)"
echo ""
echo "Next steps:"
echo "  1. Back up upload-keystore.jks + passwords offline (password manager / secure storage)."
echo "  2. From the Flutter project root:"
echo "       flutter build appbundle --release"
echo "  3. Upload build/app/outputs/bundle/release/app-release.aab to Play Console."
echo "  4. Enroll in Play App Signing if prompted (Google holds the app signing key)."
echo ""
echo "Verify git will not track secrets:"
echo "  git check-ignore -v android/key.properties android/upload-keystore.jks"
echo ""
