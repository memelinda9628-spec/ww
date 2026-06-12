# QrCodeData 编译错误修复说明

## 问题

GitHub Actions CI 构建报错：

```
cannot find 'QrCodeData' in scope
```

报错位置：`QRLoginService.swift:166`

## 根因

`Generated/` 目录（包含 matrix-rust-sdk FFI 绑定文件，定义了 `QrCodeData` 等类型）位于 `social-app-ios/` 项目根目录下。而 `Package.swift` 中 `SocialApp` target 的 `path` 设置为 `"SocialApp/"`，SPM 只编译 target 路径以内的源文件，不会编译路径外的 `Generated/` 目录内容，导致 `QrCodeData` 类型不可见。

```
social-app-ios/
├── Generated/          ← SPM 不会编译此目录（不在 target path 内）
│   ├── *.swift
│   ├── *.h
│   └── *.modulemap
├── SocialApp/          ← target path = "SocialApp/"
│   └── ...
└── Package.swift
```

## 修复

将 `Generated/` 全部 18 个文件（6 个 `.swift` + 6 个 `.h` + 6 个 `.modulemap`）从 `social-app-ios/Generated/` 移动到 `social-app-ios/SocialApp/Generated/`，使其位于 SPM target 的编译范围内。

```
social-app-ios/
├── SocialApp/
│   ├── Generated/      ← 移入 target path 内，SPM 正常编译
│   │   ├── *.swift
│   │   ├── *.h
│   │   └── *.modulemap
│   └── ...
└── Package.swift
```

## 结果

- Commit: `bbf7dbf`
- Message: `将 Generated/ FFI 绑定移入 SocialApp/ target 根目录，修复 SPM 编译范围`
- 已推送至 `origin/main`
