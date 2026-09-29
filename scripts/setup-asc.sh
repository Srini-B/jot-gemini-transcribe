#!/bin/bash
# One-time setup of the App Store Connect CLI (asc, https://asccli.sh) on a
# release Mac, so scripts/release-ios.sh can upload without a browser.
#
# With a key downloaded from App Store Connect → Users and Access →
# Integrations → App Store Connect API → Team Keys (App Manager role):
#
#   KEY_FILE=~/Downloads/AuthKey_XXXXXXXXXX.p8 ISSUER_ID=… scripts/setup-asc.sh
#
# Or let asc create the key through an Apple web session (prompts for the
# Admin's password and a two-factor code):
#
#   APPLE_ID=admin@example.com scripts/setup-asc.sh
#
# The key is moved to ~/.asc/keys and registered as the asc profile "voiceiq".

set -euo pipefail

TEAM_ID=G8K3545FJ2
APP_ID=6816685189
PROFILE=voiceiq
KEY_DIR="$HOME/.asc/keys"

if ! command -v asc >/dev/null; then
  echo "▸ Installing asc"
  brew install asc
fi
asc telemetry disable >/dev/null

if asc --profile "$PROFILE" apps view --id "$APP_ID" --output json >/dev/null 2>&1; then
  echo "✓ asc profile \"$PROFILE\" already reaches app $APP_ID"
  exit 0
fi

mkdir -p "$KEY_DIR" && chmod 700 "$KEY_DIR"

if [[ -n "${KEY_FILE:-}" ]]; then
  : "${ISSUER_ID:?set ISSUER_ID (shown above the Team Keys table)}"
  key_id=$(basename "$KEY_FILE" .p8); key_id=${key_id#AuthKey_}
  mv "$KEY_FILE" "$KEY_DIR/AuthKey_$key_id.p8"
  issuer_id=$ISSUER_ID
else
  : "${APPLE_ID:?set KEY_FILE and ISSUER_ID, or APPLE_ID of an Admin or Account Holder}"
  echo "▸ Signing in to Apple (password and two-factor code are prompted)"
  asc web auth login --apple-id "$APPLE_ID" --public-provider-id "$TEAM_ID"
  echo "▸ Creating the team API key"
  created=$(asc web api-keys create --apple-id "$APPLE_ID" --name "VoiceiQ release" \
    --role APP_MANAGER --output-dir "$KEY_DIR" --output json)
  key_id=$(python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("data",d); print(d.get("keyId") or d.get("id") or "")' <<<"$created")
  issuer_id=$(python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("data",d); print(d.get("issuerId") or "")' <<<"$created")
  [[ -n "$key_id" ]] || { echo "error: no key ID in asc's output:" >&2; echo "$created" >&2; exit 1; }
  [[ -n "$issuer_id" ]] || read -r -p "Issuer ID (shown above the Team Keys table): " issuer_id
fi
chmod 600 "$KEY_DIR/AuthKey_$key_id.p8"

echo "▸ Registering key $key_id as asc profile \"$PROFILE\""
login=(asc auth login --name "$PROFILE" --key-id "$key_id" --issuer-id "$issuer_id"
       --private-key "$KEY_DIR/AuthKey_$key_id.p8" --network)
# The login keychain is locked in SSH and agent sessions; asc then keeps the
# profile in ~/.asc/config.json (mode 0600) instead.
"${login[@]}" 2>/dev/null || "${login[@]}" --bypass-keychain

asc --profile "$PROFILE" apps view --id "$APP_ID" --output table
echo "✓ asc is ready. Release with: scripts/release-ios.sh"
