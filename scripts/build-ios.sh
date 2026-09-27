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

# Regenerates the Xcode project and builds the iOS app, keyboard and Live
# Activity for the Simulator (Debug, signed ad-hoc).
#
# A device build needs your team: build-ios.sh DEVICE=1 DEVELOPMENT_TEAM=XXXXXXXXXX

set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate

destination='generic/platform=iOS Simulator'
extra=()
for arg in "$@"; do
  case "$arg" in
    DEVICE=1) destination='generic/platform=iOS' ;;
    *) extra+=("$arg") ;;
  esac
done

exec env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild build \
    -project VoiceIQ.xcodeproj \
    -scheme VoiceIQiOS \
    -configuration Debug \
    -destination "${destination}" \
    -quiet ${extra[@]+"${extra[@]}"}
