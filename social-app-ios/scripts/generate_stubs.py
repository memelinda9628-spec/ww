#!/usr/bin/env python3
"""
从 C header 文件生成 stub.c 桩实现文件，并自动注入 3 个共享 FFI 函数。

用法: python3 generate_stubs.py
运行在 social-app-ios/ 项目根目录下。
"""
import os, re, sys

FFI_DIR = "FFI"
SHARED_FUNCTIONS = """
// === 共享 FFI 函数 (UniFFI 运行时依赖，必须存在) ===
RustBuffer ffi_{module}_rustbuffer_from_bytes(ForeignBytes bytes, RustCallStatus *_Nonnull out_status
) {
    return (RustBuffer){{0}};
}

void ffi_{module}_rustbuffer_free(RustBuffer buf, RustCallStatus *_Nonnull out_status
) {
}

uint32_t ffi_{module}_uniffi_contract_version(void
) {
    return 0;
}
"""

def extract_function_declarations(header_path):
    """从 C header 提取函数声明，返回 (return_type, func_name, full_signature) 列表"""
    with open(header_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 找到所有函数声明: 返回类型 函数名(参数...);
    # 返回类型可能是: void, uint64_t, RustBuffer, ForeignBytes 等
    pattern = re.compile(
        r'^\s*(void|uint\d+_t|int\d+_t|RustBuffer|ForeignBytes)\s+'
        r'(ffi_\w+|uniffi_\w+)\s*'
        r'\([^)]*\)\s*;',
        re.MULTILINE
    )
    
    funcs = []
    for m in pattern.finditer(content):
        ret_type = m.group(1)
        func_name = m.group(2)
        full_decl = m.group(0).rstrip(";").strip()
        funcs.append((ret_type, func_name, full_decl))
    
    return funcs


def generate_stub(header_path, stub_path, module):
    funcs = extract_function_declarations(header_path)
    
    lines = [f'#include "{module}FFI.h"', ""]
    
    for ret_type, func_name, full_decl in funcs:
        # 跳过共享函数（后面单独处理）
        if func_name in (
            f"ffi_{module}_rustbuffer_from_bytes",
            f"ffi_{module}_rustbuffer_free",
            f"ffi_{module}_uniffi_contract_version",
        ):
            continue
        
        lines.append(full_decl)
        lines.append(" {")
        
        if ret_type in ("uint64_t", "int64_t", "uint32_t", "int32_t", "uint16_t", "uint8_t"):
            lines.append("    return 0;")
        elif ret_type == "RustBuffer":
            lines.append("    return (RustBuffer){0};")
        elif ret_type == "ForeignBytes":
            lines.append("    return (ForeignBytes){0};")
        # void: no return
        
        lines.append("}")
        lines.append("")
    
    # 追加共享函数
    shared = SHARED_FUNCTIONS.format(module=module)
    lines.append(shared.strip())
    lines.append("")
    
    with open(stub_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main():
    if not os.path.isdir(FFI_DIR):
        print(f"错误: 找不到 {FFI_DIR}/ 目录，请在 social-app-ios/ 根目录运行")
        sys.exit(1)

    modules = sorted(os.listdir(FFI_DIR))
    for module in modules:
        mod_dir = os.path.join(FFI_DIR, module)
        if not os.path.isdir(mod_dir):
            continue
        
        header = os.path.join(mod_dir, "include", f"{module}FFI.h")
        stub = os.path.join(mod_dir, "stub.c")
        
        if not os.path.isfile(header):
            print(f"  ⚠ {module}: header 不存在，跳过")
            continue
        
        generate_stub(header, stub, module)
        func_count = len(extract_function_declarations(header))
        print(f"  ✓ {module}/stub.c ({func_count} 个函数)")


if __name__ == "__main__":
    main()
