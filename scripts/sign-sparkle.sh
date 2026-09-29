#!/bin/bash
# Xcode build phase (project.yml "Sign Sparkle helpers"). Removes Sparkle's XPC
# services, which only sandboxed apps use, and signs Autoupdate, Updater.app and
# the framework with the app's identity and hardened runtime. Xcode signs the
# app after this phase. https://sparkle-project.org/documentation/sandboxing/
set -euo pipefail

framework="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/Sparkle.framework"
if [[ ! -d "$framework" ]]; then
  echo "error: Sparkle.framework is not embedded at $framework" >&2
  exit 1
fi

rm -rf "$framework/Versions/B/XPCServices" "$framework/XPCServices"

# Unsigned builds (CODE_SIGNING_ALLOWED=NO) still need a valid framework seal
# after the XPC services are removed, so they fall back to ad-hoc.
identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
[[ -n "$identity" ]] || identity="-"
flags=(--force --sign "$identity" --options runtime)
if [[ "$identity" != "-" && "${OTHER_CODE_SIGN_FLAGS:-}" == *--timestamp* ]]; then
  flags+=(--timestamp)
fi

codesign "${flags[@]}" "$framework/Versions/B/Autoupdate"
codesign "${flags[@]}" "$framework/Versions/B/Updater.app"
codesign "${flags[@]}" "$framework"
