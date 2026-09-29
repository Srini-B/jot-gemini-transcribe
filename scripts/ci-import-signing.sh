#!/bin/bash
# CI only: puts a signing identity and its provisioning profiles where
# scripts/release.sh and scripts/release-ios.sh look for them, on a fresh
# GitHub-hosted runner.
#
#   P12_BASE64=... P12_PASSWORD=... scripts/ci-import-signing.sh "Profile name" ...
#
# The identity goes into ~/Library/Keychains/voiceiq-signing.keychain-db with a
# random password in ~/.voiceiq-signing/keychain.pass, the same layout the Mac
# mini uses. Profiles are downloaded by name with asc (ASC_* variables).
set -euo pipefail

: "${P12_BASE64:?}" "${P12_PASSWORD:?}"
keychain="$HOME/Library/Keychains/voiceiq-signing.keychain-db"
pass_file="$HOME/.voiceiq-signing/keychain.pass"
mkdir -p "$(dirname "$pass_file")"
chmod 700 "$(dirname "$pass_file")"

if [[ ! -f "$keychain" ]]; then
  openssl rand -hex 24 > "$pass_file"
  chmod 600 "$pass_file"
  security create-keychain -p "$(cat "$pass_file")" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  existing=$(security list-keychains -d user | tr -d '"')
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$keychain" $existing
fi
security unlock-keychain -p "$(cat "$pass_file")" "$keychain"

p12=$(mktemp)
trap 'rm -f "$p12"' EXIT
printf '%s' "$P12_BASE64" | base64 --decode > "$p12"
security import "$p12" -k "$keychain" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(cat "$pass_file")" "$keychain" >/dev/null

profiles_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profiles_dir"
for name in "$@"; do
  id=$(asc profiles list --name "$name" --profile-state ACTIVE --output json \
    | python3 -c 'import json,sys; data=json.load(sys.stdin)["data"]; print(data[0]["id"] if data else "")')
  [[ -n "$id" ]] || { echo "error: no active provisioning profile named '$name'" >&2; exit 1; }
  file=$(mktemp)
  asc profiles download --id "$id" --output "$file" >/dev/null
  uuid=$(security cms -D -i "$file" | plutil -extract UUID raw -o - -)
  platforms=$(security cms -D -i "$file" | plutil -extract Platform.0 raw -o - - 2>/dev/null || true)
  extension=mobileprovision
  [[ "$platforms" == *OSX* ]] && extension=provisionprofile
  mv "$file" "$profiles_dir/$uuid.$extension"
  echo "installed profile '$name' ($uuid.$extension)"
done

security find-identity -v -p codesigning "$keychain"
