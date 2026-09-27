#!/bin/zsh
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

# Rebuilds CVoiceIQAEC.xcframework: WebRTC's audio processing module (AEC3)
# from the PulseAudio packaging at a pinned revision, plus bridge/voiceiq_aec.cc,
# as one static library for arm64 and x86_64, macOS 14.
#
# Needs git, python3, ninja, and network access. Output replaces
# CVoiceIQAEC.xcframework next to this script; commit it.
set -euo pipefail

REVISION=d0569cfa50c1858ee279d77b3fc8870be6902441
HERE=${0:A:h}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git clone --quiet https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing.git "$WORK/src"
git -C "$WORK/src" checkout --quiet "$REVISION"
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet meson
export PATH="$WORK/venv/bin:$PATH"

for ARCH in arm64 x86_64; do
  cat > "$WORK/$ARCH.ini" <<EOF
[binaries]
c = 'clang'
cpp = 'clang++'
ar = 'ar'
[built-in options]
c_args = ['-arch', '$ARCH', '-mmacosx-version-min=14.0']
cpp_args = ['-arch', '$ARCH', '-mmacosx-version-min=14.0']
c_link_args = ['-arch', '$ARCH', '-mmacosx-version-min=14.0']
cpp_link_args = ['-arch', '$ARCH', '-mmacosx-version-min=14.0']
[host_machine]
system = 'darwin'
cpu_family = '$( [[ $ARCH == arm64 ]] && echo aarch64 || echo x86_64 )'
cpu = '$ARCH'
endian = 'little'
EOF
  (cd "$WORK/src" && meson setup "$WORK/build-$ARCH" --cross-file "$WORK/$ARCH.ini" \
     --default-library=static --buildtype=release --force-fallback-for=abseil-cpp >/dev/null)
  # The examples need CoreFoundation at link time; only the libraries matter.
  ninja -k 0 -C "$WORK/build-$ARCH" >/dev/null || true
  clang++ -arch "$ARCH" -mmacosx-version-min=14.0 -std=c++17 -O2 -DWEBRTC_POSIX -DWEBRTC_MAC \
    -I"$WORK/src/webrtc" -I"$WORK/src/subprojects/abseil-cpp-20240722.0" \
    -c "$HERE/bridge/voiceiq_aec.cc" -o "$WORK/voiceiq_aec-$ARCH.o"
  libtool -static -o "$WORK/libvoiceiqaec-$ARCH.a" "$WORK/voiceiq_aec-$ARCH.o" \
    $(find "$WORK/build-$ARCH/webrtc" "$WORK/build-$ARCH/subprojects" -name '*.a' | sort)
done

lipo -create "$WORK/libvoiceiqaec-arm64.a" "$WORK/libvoiceiqaec-x86_64.a" -output "$WORK/libvoiceiqaec.a"
mkdir -p "$WORK/headers"
cp "$HERE/bridge/voiceiq_aec.h" "$WORK/headers/"
cat > "$WORK/headers/module.modulemap" <<EOF
module CVoiceIQAEC {
    header "voiceiq_aec.h"
    link "c++"
    export *
}
EOF
rm -rf "$HERE/CVoiceIQAEC.xcframework"
xcodebuild -create-xcframework -library "$WORK/libvoiceiqaec.a" -headers "$WORK/headers" \
  -output "$HERE/CVoiceIQAEC.xcframework" >/dev/null
cp "$WORK/src/webrtc/LICENSE" "$HERE/Notices/WebRTC-LICENSE"
cp "$WORK/src/webrtc/PATENTS" "$HERE/Notices/WebRTC-PATENTS" 2>/dev/null || true
cp "$WORK/src/COPYING" "$HERE/Notices/webrtc-audio-processing-COPYING"
cp "$WORK/src/webrtc/third_party/pffft/LICENSE" "$HERE/Notices/PFFFT-LICENSE"
cp "$WORK/src/webrtc/modules/third_party/fft/LICENSE" "$HERE/Notices/FFT-LICENSE"
cp "$WORK/src/webrtc/common_audio/third_party/ooura/LICENSE" "$HERE/Notices/Ooura-LICENSE"
cp "$WORK/src/webrtc/common_audio/third_party/spl_sqrt_floor/LICENSE" "$HERE/Notices/SPLSqrtFloor-LICENSE"
cp "$WORK/src/subprojects/abseil-cpp-20240722.0/LICENSE" "$HERE/Notices/Abseil-LICENSE"
echo "Built $HERE/CVoiceIQAEC.xcframework from $REVISION"
