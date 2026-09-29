#!/bin/bash
# Makes this Mac able to run scripts/release.sh: puts the Developer ID
# Application identity in the release keychain and installs the
# "VoiceiQ macOS Developer ID" profile. Idempotent.
#
#   P12=~/Downloads/DeveloperID.p12 P12_PASSWORD=… scripts/setup-mac-signing.sh
#   P12=~/Desktop/Certificates.p12 P12_PASSWORD= scripts/setup-mac-signing.sh   # exported without a password
#   scripts/setup-mac-signing.sh          # profile only, or check what is missing
#
# Where the .p12 comes from: on a Mac that already signs releases, Keychain
# Access › My Certificates › "Developer ID Application: …" › Export (.p12,
# with a password). macOS asks for the login password to export, so this is
# done at that Mac, not over SSH. The API key cannot create a Developer ID
# certificate; Apple allows that only to the Account Holder.
#
# The identity goes into ~/Library/Keychains/voiceiq-signing.keychain-db,
# created here if needed and unlocked by the release scripts with
# ~/.voiceiq-signing/keychain.pass, because the login keychain is locked in SSH
# and agent sessions. See docs/RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID=G8K3545FJ2
PROFILE_NAME="VoiceiQ macOS Developer ID"
ASC_PROFILE="${ASC_PROFILE:-voiceiq}"
KEYCHAIN="$HOME/Library/Keychains/voiceiq-signing.keychain-db"
PASS_FILE="$HOME/.voiceiq-signing/keychain.pass"
PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

fail() { echo "error: $*" >&2; exit 1; }

echo "▸ Release keychain"
mkdir -p "$(dirname "$PASS_FILE")"
chmod 700 "$(dirname "$PASS_FILE")"
if [[ ! -f "$PASS_FILE" ]]; then
  (umask 077; openssl rand -hex 16 > "$PASS_FILE")
fi
if [[ ! -f "$KEYCHAIN" ]]; then
  security create-keychain -p "$(cat "$PASS_FILE")" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"   # no auto-lock
  echo "  created $KEYCHAIN"
fi
security unlock-keychain -p "$(cat "$PASS_FILE")" "$KEYCHAIN"
# Keep it in the search list so codesign and xcodebuild find the identity.
current=$(security list-keychains -d user | tr -d '"' | xargs)
if [[ " $current " != *" $KEYCHAIN "* ]]; then
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$KEYCHAIN" $current
fi

has_identity() {
  security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "Developer ID Application: .*($TEAM_ID)"
}

echo "▸ Developer ID Application identity"
if has_identity; then
  echo "  present"
elif [[ -n "${P12:-}" ]]; then
  [[ -f "$P12" ]] || fail "P12 file not found: $P12"
  [[ -n "${P12_PASSWORD+set}" ]] || fail "P12_PASSWORD is unset (use P12_PASSWORD= for a .p12 exported without one)"
  security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
  # Let codesign use the key without a dialog.
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(cat "$PASS_FILE")" "$KEYCHAIN" >/dev/null
  has_identity || fail "the .p12 did not contain a Developer ID Application identity for $TEAM_ID"
  echo "  imported"
else
  echo "  missing: export it as a .p12 from a Mac that signs releases and rerun with P12=… P12_PASSWORD=…"
fi

echo "▸ Provisioning profile \"$PROFILE_NAME\""
mkdir -p "$PROFILES_DIR"
installed=0
for file in "$PROFILES_DIR"/*.provisionprofile; do
  [[ -e "$file" ]] || continue
  if security cms -D -i "$file" 2>/dev/null | plutil -extract Name raw -o - - 2>/dev/null | grep -qx "$PROFILE_NAME"; then
    installed=1
  fi
done
if [[ $installed == 1 ]]; then
  echo "  installed"
else
  command -v asc >/dev/null || fail "asc is missing: brew install asc, then scripts/setup-asc.sh"
  id=$(asc --profile "$ASC_PROFILE" profiles list --profile-type MAC_APP_DIRECT --output json \
    | python3 -c 'import json,sys; print(next((p["id"] for p in json.load(sys.stdin)["data"] if p["attributes"]["name"] == sys.argv[1]), ""))' "$PROFILE_NAME")
  [[ -n "$id" ]] || fail "no profile named \"$PROFILE_NAME\" in the account (docs/RELEASING.md)"
  tmp=$(mktemp)
  asc --profile "$ASC_PROFILE" profiles download --id "$id" --output "$tmp" >/dev/null
  uuid=$(security cms -D -i "$tmp" | plutil -extract UUID raw -o - -)
  mv "$tmp" "$PROFILES_DIR/$uuid.provisionprofile"
  echo "  installed $uuid"
fi

echo "▸ Notarization credentials"
if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  echo "  APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD and APPLE_TEAM_ID are set"
else
  echo "  missing: export APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD and APPLE_TEAM_ID (see docs/RELEASING.md), e.g. in ~/.zshrc"
fi

has_identity && echo "✓ this Mac can run scripts/release.sh" \
  || { echo "✗ not ready: the Developer ID identity is missing" >&2; exit 1; }
