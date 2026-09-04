#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Reuse the SDK, NDK, Gradle cache, and Python tools bundled in /home/vscode.
export HOME="${HOME:-/home/vscode}"
export PATH="/home/vscode/.local/bin:/home/vscode/.venv/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-/home/vscode/.buildozer/android/platform/android-sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/home/vscode/.buildozer/android/platform/android-ndk-r25b}"
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-$ANDROID_NDK_HOME}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/home/vscode/.gradle}"

if [[ -d /usr/lib/jvm/java-17-openjdk-amd64 ]]; then
    export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
fi

BRIEFCASE="/workspaces/kivy8/BeeWare/.venv/bin/briefcase"
if [[ ! -x "$BRIEFCASE" ]]; then
    echo "Error: Briefcase is missing at $BRIEFCASE" >&2
    exit 1
fi

if [[ ! -d build/beewaredemo/android/gradle ]]; then
    "$BRIEFCASE" create android --no-input
else
    "$BRIEFCASE" update android --no-input
fi

"$BRIEFCASE" build android --no-input

APK_PATH="$(find build/beewaredemo/android -type f -name '*.apk' -print -quit)"
if [[ -z "$APK_PATH" ]]; then
    echo "Error: Briefcase did not produce an APK." >&2
    exit 1
fi

echo "APK: $PWD/$APK_PATH"
