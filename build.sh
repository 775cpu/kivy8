#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# ---------- 解析命令行参数 ----------
usage() {
    echo "Usage: $0 [--color|-c|--icon] <COLOR>"
    echo "  COLOR:  (R,G,B) 或 RRGGBB (例如 (67,20,80) 或 F1F2F3)"
    echo "  If no color is provided, the icon color step is skipped."
    exit 1
}

COLOR_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --color|-c|--icon)
            if [[ -z "${2:-}" ]]; then
                echo "Error: $1 requires a color value."
                usage
            fi
            COLOR_ARG="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            echo "Unexpected argument: $1"
            usage
            ;;
    esac
done

# ---------- 颜色处理（仅在提供颜色参数时执行） ----------
if [[ -n "$COLOR_ARG" ]]; then
    echo "Color argument provided: $COLOR_ARG"

    # 颜色转换函数
    parse_color() {
        local input="$1"
        local r g b
        input="$(echo "$input" | tr -d ' ')"
        if [[ "$input" =~ ^\(([0-9]+),([0-9]+),([0-9]+)\)$ ]]; then
            r="${BASH_REMATCH[1]}"
            g="${BASH_REMATCH[2]}"
            b="${BASH_REMATCH[3]}"
        elif [[ "$input" =~ ^([0-9A-Fa-f]{6})$ ]]; then
            r=$((16#${input:0:2}))
            g=$((16#${input:2:2}))
            b=$((16#${input:4:2}))
        else
            echo "Error: Invalid color format '$1'. Expected (R,G,B) or RRGGBB." >&2
            exit 1
        fi
        if (( r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255 )); then
            echo "Error: RGB values must be between 0 and 255." >&2
            exit 1
        fi
        echo "$r $g $b"
        printf "#%02X%02X%02X\n" "$r" "$g" "$b"
    }

    read -r R G B < <(parse_color "$COLOR_ARG" | head -n1)
    HEX_COLOR="$(parse_color "$COLOR_ARG" | tail -n1)"
    echo "Parsed color: R=$R G=$G B=$B  ->  $HEX_COLOR"

    # ---------- 生成 splash.png ----------
    echo "Generating splash.png with color ($R,$G,$B)..."
    python3 -c "
import rpc, io, PIL.Image
bmp_bin = rpc.get_bmp_bytes(rgb=($R, $G, $B), size=(64,64))
img = PIL.Image.open(io.BytesIO(bmp_bin))
img.save('android_src/splash.png')
"

    # ---------- 更新 buildozer.spec ----------
    SPEC_FILE="buildozer.spec"
    if [[ ! -f "$SPEC_FILE" ]]; then
        echo "Error: $SPEC_FILE not found in current directory." >&2
        exit 1
    fi
    echo "Updating $SPEC_FILE with presplash_color = $HEX_COLOR ..."
    sed -i "s/^\([[:space:]]*android\.presplash_color[[:space:]]*=[[:space:]]*\).*/\1$HEX_COLOR/" "$SPEC_FILE"
else
    echo "No color provided, skipping icon color update (splash.png and spec)."
fi

# ---------- 检查 cmake ----------
if ! command -v cmake &>/dev/null; then
    echo "正在配置上海时区..."
    sudo ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    echo "Asia/Shanghai" | sudo tee /etc/timezone > /dev/null

    # 2. 配置 24 小时制时间 (LC_TIME=C)
    sed -i '/export LC_TIME=/d' ~/.profile
    echo 'export LC_TIME=C' >> ~/.profile
    export LC_TIME=C

    # 3. 安装 cmake
    echo "cmake 未安装，正在安装..."
    sudo apt-get update && sudo apt-get install -y cmake
fi

# ---------- 修复 python-for-android 的 pip 升级冲突 ----------
P4A_BUILD_FILE=".buildozer/android/platform/python-for-android/pythonforandroid/build.py"
if [ -f "$P4A_BUILD_FILE" ]; then
    python3 - <<'PY' "$P4A_BUILD_FILE"
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = '''        # Prepare base environment and upgrade pip:
        base_env = dict(copy.copy(os.environ))
        base_env["PYTHONPATH"] = ctx.get_site_packages_dir(arch)
        info('Upgrade pip to latest version')
        shprint(sh.bash, '-c', (
            "source venv/bin/activate && pip install -U pip"
        ), _env=copy.copy(base_env))
'''
new = '''        # Prepare base environment without forcing an in-venv pip upgrade.
        # This avoids breaking python-for-android's own pip/resolvelib stack
        # in the temporary build virtualenv.
        base_env = dict(copy.copy(os.environ))
        base_env["PYTHONPATH"] = ctx.get_site_packages_dir(arch)
        info('Skipping pip upgrade in build venv')
'''
if old in text:
    path.write_text(text.replace(old, new))
    print(f"Patched {path}")
else:
    print(f"No matching patch block found in {path}")
PY
fi

# ---------- 可重复构建配置 ----------
FIXED_TIME=1609459200   # 2021-01-01 00:00:00 UTC
export SOURCE_DATE_EPOCH=$FIXED_TIME
export PYTHONHASHSEED=0

# 固定项目源文件的时间戳
echo "固定项目源文件的时间戳..."
find . \
    -path ./.buildozer -prune -o \
    -path ./__pycache__ -prune -o \
    -path ./bin -prune -o \
    -name '*.py' -exec touch -d "@$FIXED_TIME" {} \;

# ---------- 检查并准备 OpenCV 预编译库 ----------
OPENCV_DIR=""
for candidate in \
    "android_src/jni/opencv-mobile-4.10.0-android" \
    "android_src/jni/opencv-mobile-4.9.0-android"; do
    if [ -f "$candidate/sdk/native/staticlibs/arm64-v8a/libopencv_core.a" ]; then
        OPENCV_DIR="$candidate"
        break
    fi
done

if [ -z "$OPENCV_DIR" ]; then
    echo "OpenCV 预编译静态库缺失，正在下载..."
    OPENCV_URL="https://ghfast.top/https://github.com/nihui/opencv-mobile/releases/download/v27/opencv-mobile-4.9.0-android.zip"
    mkdir -p android_src/jni
    wget "$OPENCV_URL" -O /tmp/opencv-mobile.zip
    unzip  /tmp/opencv-mobile.zip -d android_src/jni/
    rm /tmp/opencv-mobile.zip
    OPENCV_DIR="android_src/jni/opencv-mobile-4.9.0-android"
    echo "OpenCV 下载并解压完成。"
else
    echo "OpenCV 静态库已存在: $OPENCV_DIR"
fi

# ---------- 检查 ncnn 预编译库 ----------
NCNN_DIR="android_src/jni/ncnn-20240410-android-vulkan"
NCNN_STATIC_LIB="$NCNN_DIR/arm64-v8a/lib/libncnn.a"
GLSLANG_STATIC_LIB="$NCNN_DIR/arm64-v8a/lib/libOSDependent.a"
if [ ! -f "$NCNN_STATIC_LIB" ] || [ ! -f "$GLSLANG_STATIC_LIB" ]; then
    echo "ncnn 预编译静态库缺失，正在下载..."
    NCNN_URL="https://github.com/Tencent/ncnn/releases/download/20240410/ncnn-20240410-android-vulkan.zip"
    wget "$NCNN_URL" -O /tmp/ncnn-20240410-android-vulkan.zip
    unzip -o /tmp/ncnn-20240410-android-vulkan.zip -d android_src/jni/
    rm /tmp/ncnn-20240410-android-vulkan.zip
fi
if [ ! -f "$NCNN_STATIC_LIB" ] || [ ! -f "$GLSLANG_STATIC_LIB" ]; then
    echo "Error: ncnn ARM64 静态库准备失败。" >&2
    exit 1
fi
echo "ncnn 静态库已就绪: $NCNN_DIR"

# ---------- 打包 APK ----------
TS=$(date +%Y%m%d_%H%M%S)
OUT_DIR="bin"
mkdir -p "$OUT_DIR"

# 清理旧 APK
find "$OUT_DIR" -maxdepth 1 -type f \( -name 'hualing-0.1-arm64-v8a-debug.apk' -o -name 'hualing-0.1-arm64-v8a-debug-*.apk' \) -delete

echo "Building Android APK..."
ANDROID_PROJECT_DIR=".buildozer/android/platform/build-arm64-v8a/dists/hualing"
JNI_BUILD_DIR="$ANDROID_PROJECT_DIR/build/yolo_jni"
JNI_LIB_DIR="$ANDROID_PROJECT_DIR/libs/arm64-v8a"
SRC_LIB_DIR="android_src/libs/arm64-v8a"
NDK_ROOT="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-/home/vscode/.buildozer/android/platform/android-ndk-r25b}}"

# ---------- 预下载 freetype，绕过 Savannah 502/504 ----------
FREETYPE_CACHE_DIR=".buildozer/android/platform/build-arm64-v8a/packages/freetype"
FREETYPE_ARCHIVE="$FREETYPE_CACHE_DIR/freetype-2.14.1.tar.gz"
SAVANNAH_FREETYPE_URL="https://download.savannah.gnu.org/releases/freetype/freetype-2.14.1.tar.gz"
SOURCEFORGE_FREETYPE_URL="https://downloads.sourceforge.net/project/freetype/freetype2/2.14.1/freetype-2.14.1.tar.gz"
mkdir -p "$FREETYPE_CACHE_DIR"

if [ -f "$FREETYPE_ARCHIVE" ] && ! tar -tzf "$FREETYPE_ARCHIVE" >/dev/null 2>&1; then
    echo "检测到损坏的 freetype 缓存，删除后重新下载。"
    rm -f "$FREETYPE_ARCHIVE"
fi

if [ ! -f "$FREETYPE_ARCHIVE" ]; then
    echo "使用 curl -vvv 探测 Savannah freetype 下载地址..."
    if curl -vvv -fL --connect-timeout 10 --max-time 60 -o /dev/null "$SAVANNAH_FREETYPE_URL"; then
        echo "Savannah 可用，下载 freetype。"
        FREETYPE_URL="$SAVANNAH_FREETYPE_URL"
        curl -fL --retry 2 --retry-all-errors "$SAVANNAH_FREETYPE_URL" -o "$FREETYPE_ARCHIVE"
    else
        echo "Savannah 返回错误（常见为 502/504），切换 SourceForge 镜像。"
        FREETYPE_URL="$SOURCEFORGE_FREETYPE_URL"
        curl -fL --retry 3 --retry-all-errors "$SOURCEFORGE_FREETYPE_URL" -o "$FREETYPE_ARCHIVE"
    fi
else
    FREETYPE_URL="$SOURCEFORGE_FREETYPE_URL"
fi

if ! tar -tzf "$FREETYPE_ARCHIVE" >/dev/null 2>&1; then
    echo "Error: freetype archive is missing or invalid: $FREETYPE_ARCHIVE" >&2
    exit 1
fi
echo "freetype 源码包已就绪: $FREETYPE_ARCHIVE"

P4A_FREETYPE_RECIPE=".buildozer/android/platform/python-for-android/pythonforandroid/recipes/freetype/__init__.py"
patch_freetype_recipe() {
    local url="$1"
    if [ ! -f "$P4A_FREETYPE_RECIPE" ]; then
        return 0
    fi
    sed -i -E "s#^[[:space:]]*url = .*freetype-\{version\}\.tar\.gz.*#    url = '$url'#" "$P4A_FREETYPE_RECIPE"
    echo "p4a freetype recipe 使用: $url"
}

patch_freetype_recipe "$FREETYPE_URL"

download_freetype_mirror() {
    rm -f "$FREETYPE_CACHE_DIR/freetype-2.14.1.tar.gz" \
        "$FREETYPE_CACHE_DIR/.mark-freetype-2.14.1.tar.gz"
    echo "自动切换 SourceForge 下载 freetype..."
    curl -fL --retry 3 --retry-all-errors "$SOURCEFORGE_FREETYPE_URL" -o "$FREETYPE_ARCHIVE"
    tar -tzf "$FREETYPE_ARCHIVE" >/dev/null
    patch_freetype_recipe "$SOURCEFORGE_FREETYPE_URL"
}

run_buildozer_with_network_fallback() {
    local log_file pid status saw_freetype_failure
    log_file="$(mktemp)"
    saw_freetype_failure=0

    set +e
    stdbuf -oL -eL buildozer -v android debug > >(tee "$log_file") 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if grep -Eiq 'Savannah.*freetype|freetype.*Savannah|HTTP Error (502|504)|502 Bad Gateway|504 Gateway' "$log_file"; then
            saw_freetype_failure=1
            echo "检测到 Buildozer 输出中的 freetype/Savannah 网络错误，终止本轮并切换镜像。"
            kill "$pid" 2>/dev/null || true
            break
        fi
        sleep 1
    done
    wait "$pid"
    status=$?
    set -e
    rm -f "$log_file"

    if [ "$saw_freetype_failure" -eq 1 ]; then
        download_freetype_mirror
        return 75
    fi
    return "$status"
}

if [ ! -d "$NDK_ROOT" ]; then
    echo "Error: Android NDK not found at $NDK_ROOT" >&2
    for attempt in {1..5}; do
        echo "=====第${attempt}次尝试准备 Android 工具链====="
        if run_buildozer_with_network_fallback; then
            break
        fi
        if [ "$attempt" -eq 5 ]; then
            echo "Error: Buildozer 未能准备 Android 工具链。" >&2
            exit 1
        fi
        echo "构建工具下载失败，5 秒后重试。"
    done
    NDK_ROOT="$(find .buildozer/android/platform -maxdepth 1 -type d -name 'android-ndk-*' -print -quit)"
    if [ -z "$NDK_ROOT" ] || [ ! -d "$NDK_ROOT" ]; then
        echo "Error: Buildozer 未能准备 Android NDK。" >&2
        exit 1
    fi
fi

mkdir -p "$JNI_BUILD_DIR" "$JNI_LIB_DIR" "$SRC_LIB_DIR" "$ANDROID_PROJECT_DIR/src/main/assets"
cp -f android_src/assets/yolov8n.param "$ANDROID_PROJECT_DIR/src/main/assets/yolov8n.param"
cp -f android_src/assets/yolov8n.bin "$ANDROID_PROJECT_DIR/src/main/assets/yolov8n.bin"
echo "Packed YOLO assets to $ANDROID_PROJECT_DIR/src/main/assets"

# 设置 OpenCV_DIR 供 CMake 使用
export OpenCV_DIR="$PWD/$OPENCV_DIR/sdk/native/jni"

cmake -S android_src/jni -B "$JNI_BUILD_DIR" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-24 \
    -DANDROID_STL=c++_shared \
    -DANDROID_CPP_FEATURES=exceptions \
    -DANDROID_ALLOW_UNDEFINED_SYMBOLS=TRUE \
    -DOpenCV_DIR="$OpenCV_DIR"
cmake --build "$JNI_BUILD_DIR" -j4

cp "$JNI_BUILD_DIR/libyolo_jni.so" "$JNI_LIB_DIR/libyolo_jni.so"
cp "$JNI_BUILD_DIR/libyolo_jni.so" "$SRC_LIB_DIR/libyolo_jni.so"
LIBCXX_SHARED="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
if [ ! -f "$LIBCXX_SHARED" ]; then
    echo "Error: libc++_shared.so not found at $LIBCXX_SHARED" >&2
    exit 1
fi
cp "$LIBCXX_SHARED" "$JNI_LIB_DIR/libc++_shared.so"
cp "$LIBCXX_SHARED" "$SRC_LIB_DIR/libc++_shared.so"
echo "Packed native library to $JNI_LIB_DIR/libyolo_jni.so"
echo "Packed libc++ runtime to $JNI_LIB_DIR/libc++_shared.so"

for attempt in {1..5}; do
    if run_buildozer_with_network_fallback; then
        status=0
        break
    else
        status=$?
    fi
    if [ "$status" -eq 75 ] && [ "$attempt" -lt 5 ]; then
        echo "freetype 镜像已切换，重新执行 Buildozer（第${attempt}次失败）。"
        continue
    fi
    echo "Error: Buildozer 构建失败，退出码 $status。" >&2
    exit "$status"
done

SRC="$OUT_DIR/hualing-0.1-arm64-v8a-debug.apk"
DST="$OUT_DIR/hualing-0.1-arm64-v8a-debug-${TS}.apk"

if [ -f "$SRC" ]; then
    cp "$SRC" "$DST"
    echo "Created $DST"
else
    echo "Error: expected APK not found at $SRC" >&2
    exit 1
fi