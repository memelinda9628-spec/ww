#!/usr/bin/env bash
# =============================================================================
# UniFFI Bindings Generator
# =============================================================================
# 前置条件：已通过 cargo build --features uniffi 生成 .swift/.h/.modulemap
#
# 产出：
#   SocialApp/Generated/*.swift               → Swift 绑定（纯文本，SPM 直接编译）
#   MatrixFFI/{module}/include/{module}FFI.h    → C header
#   MatrixFFI/{module}/include/module.modulemap → modulemap
#   MatrixFFI/{module}/stub.c                   → C 桩实现（自动注入 3 个共享函数）
#
# 用法：
#   cd social-app-ios
#   bash scripts/generate_ffi.sh [generated_dir]
#
#   generated_dir: uniffi-bindgen 输出目录（默认 /tmp/uniffi-out）
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GEN_DIR="${1:-/tmp/uniffi-out}"

MODULES=(
    matrix_sdk_ffi
    matrix_sdk
    matrix_sdk_base
    matrix_sdk_common
    matrix_sdk_crypto
    matrix_sdk_ui
)

SWIFT_OUT="${PROJECT_DIR}/SocialApp/Generated"
FFI_OUT="${PROJECT_DIR}/MatrixFFI"

echo "=== 源目录: ${GEN_DIR} ==="

# ---------- 1. 放置 Swift ----------
echo "[1/3] Swift → ${SWIFT_OUT}"
mkdir -p "${SWIFT_OUT}"
for m in "${MODULES[@]}"; do
    src="${GEN_DIR}/${m}.swift"
    if [ -f "$src" ]; then
        cp "$src" "${SWIFT_OUT}/${m}.swift"
        echo "  ✓ ${m}.swift"
    else
        echo "  ⚠ ${m}.swift 未找到"
    fi
done

# ---------- 2. 放置 C header + modulemap ----------
echo "[2/3] C headers → ${FFI_OUT}"
for m in "${MODULES[@]}"; do
    inc="${FFI_OUT}/${m}/include"
    mkdir -p "$inc"

    h="${GEN_DIR}/${m}FFI.h"
    [ -f "$h" ] && cp "$h" "${inc}/${m}FFI.h"

    mm="${GEN_DIR}/${m}FFI.modulemap"
    [ -f "$mm" ] && cp "$mm" "${inc}/module.modulemap"

    echo "  ✓ ${m}"
done

# ---------- 3. 生成 stub.c（Python 脚本保证可靠） ----------
echo "[3/3] 生成 stub.c（自动注入 3 个共享函数）"
python3 "${SCRIPT_DIR}/generate_stubs.py"
echo ""
echo "=== 完成 ==="
echo "验证: cd social-app-ios && swift build -v"
