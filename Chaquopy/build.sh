#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
export ANDROID_HOME="${ANDROID_HOME:-/home/vscode/.cache/briefcase/tools/android_sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/home/vscode/.buildozer/android/platform/android-ndk-r25b}"
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-$ANDROID_NDK_HOME}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/home/vscode/.gradle}"
export PATH="/home/vscode/.local/bin:/home/vscode/.gradle/wrapper/dists/gradle-8.14.3-all/h9bud5ffjflfoe91ghcb596uv/gradle-8.14.3/bin:$PATH"

if [[ -d /usr/lib/jvm/java-17-openjdk-amd64 ]]; then
    export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
fi

if ! command -v gradle >/dev/null 2>&1; then
    echo "Error: Gradle 8.14.3 is not available in /home/vscode/.gradle." >&2
    exit 1
fi

gradle --no-daemon :app:assembleDebug

APK_SOURCE="app/build/outputs/apk/debug/app-debug.apk"
APK_OUTPUT="apk/chaquopy-rpc-debug.apk"
if [[ ! -s "$APK_SOURCE" ]]; then
    echo "Error: APK was not generated at $APK_SOURCE" >&2
    exit 1
fi

mkdir -p apk
cp -f "$APK_SOURCE" "$APK_OUTPUT"
echo "APK: $PWD/$APK_OUTPUT"