#!/bin/bash
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Regenerates the Xcode project and builds the app (Debug).
#
# Works on a clean clone with no Apple account: Debug signs ad-hoc, so no
# certificate, team membership or provisioning profile is needed. To build
# under your own team, pass it through: build.sh DEVELOPMENT_TEAM=XXXXXXXXXX
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate

# macOS ties Accessibility and microphone grants to the code signature. An
# ad-hoc signature changes on every rebuild, so each build lost its grants and
# the app re-ran the permission wizard. When a stable Apple Development
# identity is in the keychain, sign Debug with it so grants survive rebuilds.
# Override with SIGN_IDENTITY=- to force ad-hoc, or pass CODE_SIGN_IDENTITY=…
signing_args=()
identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development/ { print $2; exit }')}"
if [[ -n "${identity}" && "${identity}" != "-" ]]; then
  # The certificate's OU is its team; it must match DEVELOPMENT_TEAM or
  # xcodebuild refuses the identity.
  team="$(security find-certificate -c "${identity}" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')"
  echo "Signing Debug with: ${identity} (team ${team:-unknown})"
  signing_args=(CODE_SIGN_IDENTITY="${identity}" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="${team}")
fi

# Some corporate-managed git configs set safe.bareRepository=explicit, which
# breaks SPM's bare clone cache.
exec env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild build \
    -project VoiceIQ.xcodeproj \
    -scheme VoiceIQ \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -quiet "${signing_args[@]}" "$@"
