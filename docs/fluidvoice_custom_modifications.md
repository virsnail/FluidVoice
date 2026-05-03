# FluidVoice 自定义修改记录

> **用途**：本文档记录了对原始 FluidVoice 项目（altic-dev/Fluid-oss）所做的全部自定义修改。
> 当你从上游同步最新代码后，可凭此文档快速重新应用这些修改。

---

## 目录

1. [隐私保护：关闭遥测外发](#1-隐私保护关闭遥测外发)
2. [语音识别：强制使用中文](#2-语音识别强制使用中文)
3. [麦克风优先级列表](#3-麦克风优先级列表)  
   3.1 [SettingsStore - 新增存储字段](#31-settingsstore---新增存储字段)  
   3.2 [ASRService - 设备选择逻辑重写](#32-asrservice---设备选择逻辑重写)  
   3.3 [InputDevicePriorityListView - 新增 UI 组件](#33-inputdeviceprioritylistview---新增-ui-组件)  
   3.4 [SettingsView - 替换 Input Device 下拉菜单](#34-settingsview---替换-input-device-下拉菜单)
4. [禁用自动升级功能](#4-禁用自动升级功能)  
   4.1 [AppDelegate - 禁用自动/手动检查](#41-appdelegate---禁用自动手动检查)  
   4.2 [MenuBarManager - 移除菜单项](#42-menubarmanager---移除菜单项)  
   4.3 [SettingsView - 替换升级按钮为只读版本信息](#43-settingsview---替换升级按钮为只读版本信息)
5. [编译并安装教程](#5-编译并安装教程)
6. [并发修复：NetworkTransport](#6-并发修复networktransport)

---

## 1. 隐私保护：关闭遥测外发

**文件**：`Sources/Fluid/Analytics/AnalyticsConfig.swift`

### 原始代码（第 7-17 行）

```swift
struct AnalyticsConfig {
    static let defaultEUHost = "https://eu.i.posthog.com"
    // ...
}
```

### 修改后代码

```swift
struct AnalyticsConfig {
    // 已修改：将 PostHog 遥测地址改为 localhost，确保数据不离开本机
    static let defaultEUHost = "http://localhost:12345"
    // ...
}
```

**说明**：将所有 PostHog 统计请求重定向到本机端口 12345（未监听），数据永远不会发出。

---

## 2. 语音识别：强制使用中文

### 2.1 文件：`Sources/Fluid/Services/AppleSpeechProvider.swift`

**原始代码（第 25-28 行）**：

```swift
private var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale.current)
```

**修改后代码**：

```swift
// 固定使用中文（zh-CN），不随系统语言变化
private var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
```

同样修改了第 72-75 行的 `init()` 处的初始化，将 `Locale.current` 替换为 `Locale(identifier: "zh-CN")`。

### 2.2 文件：`Sources/Fluid/Services/AppleSpeechAnalyzerProvider.swift`

**原始代码（第 39-50 行）**：

```swift
let locale = Locale.current
let languageCode = locale.language.languageCode?.identifier ?? "en"
```

**修改后代码**：

```swift
// 固定识别语言为中文
let locale = Locale(identifier: "zh-CN")
let languageCode = "zh"
```

并在第 120-126、147-157 行的语言支持检测代码中，将 `Locale.current` 替换为 `Locale(identifier: "zh-CN")`。

---

## 3. 麦克风优先级列表

> **背景**：原始 FluidVoice 会在检测到 AirPods/蓝牙设备接入时自动切换麦克风，导致用户无法控制麦克风的使用顺序。
> 本次修改为用户提供了一个可手动排序的麦克风优先级列表，app 在每次 STT 开始时按列表顺序选择第一个可用设备。

---

### 3.1 SettingsStore - 新增存储字段

**文件**：`Sources/Fluid/Persistence/SettingsStore.swift`

#### 新增属性（约第 1293-1305 行，插入在 `preferredInputDeviceUID` 之后）

```swift
/// 原始代码（无此属性）

// ── 新增代码 ──
/// Ordered list of input device UIDs representing the user's preferred microphone priority.
/// The app will always use the first available device in this list at the moment recording starts.
/// Devices not in this list are placed at the end (appended dynamically when first seen).
var inputDevicePriorityList: [String] {
    get { self.defaults.stringArray(forKey: Keys.inputDevicePriorityList) ?? [] }
    set {
        objectWillChange.send()  // ← 关键：通知 SwiftUI 更新界面
        self.defaults.set(newValue, forKey: Keys.inputDevicePriorityList)
    }
}
```

> ⚠️ **重点**：setter 必须调用 `objectWillChange.send()`，否则 SwiftUI 列表视图在用户点击排序箭头后不会刷新（这是修复箭头排序无效 bug 的关键）。

#### 新增 Key 常量（约第 3588 行）

```swift
// 原始代码
static let preferredInputDeviceUID = "PreferredInputDeviceUID"
static let preferredOutputDeviceUID = "PreferredOutputDeviceUID"

// 修改后代码
static let preferredInputDeviceUID = "PreferredInputDeviceUID"
static let inputDevicePriorityList = "InputDevicePriorityList"   // ← 新增
static let preferredOutputDeviceUID = "PreferredOutputDeviceUID"
```

---

### 3.2 ASRService - 设备选择逻辑重写

**文件**：`Sources/Fluid/Services/ASRService.swift`

#### 3.2.1 `bindPreferredInputDeviceIfNeeded()` 方法（约第 1158-1220 行）

**原始逻辑**：
1. 如果 `syncAudioDevicesWithSystem == true`，直接返回（使用系统默认）
2. 读取单个 `preferredInputDeviceUID`，找到后绑定

**修改后逻辑**：
```swift
@discardableResult
private func bindPreferredInputDeviceIfNeeded() -> Bool {
    guard SettingsStore.shared.syncAudioDevicesWithSystem == false else {
        return true  // 使用系统默认
    }

    let priorityList = SettingsStore.shared.inputDevicePriorityList
    if !priorityList.isEmpty {
        let currentDevices = AudioDevice.listInputDevices()
        // ← 新增：按优先级列表顺序，找到第一个当前已连接的设备
        for uid in priorityList {
            if let device = currentDevices.first(where: { $0.uid == uid }) {
                let ok = self.setEngineInputDevice(deviceID: device.id, deviceUID: device.uid, deviceName: device.name)
                if ok {
                    SettingsStore.shared.preferredInputDeviceUID = device.uid  // 同步兼容字段
                    return true
                }
            }
        }
        return self.tryBindToSystemDefaultInput()  // 列表中无可用设备，回退到系统默认
    }

    // 优先级列表为空：沿用原有 preferredInputDeviceUID 单选逻辑（向后兼容）
    // ... 原有代码不变 ...
}
```

#### 3.2.2 `handleDeviceListChanged()` 方法（约第 1884-1960 行）

**原始代码中的自动蓝牙切换逻辑（已删除）**：

```swift
// ← 这段代码被删除：
// Check for newly connected Bluetooth devices (auto-switch)
for device in currentDevices {
    if device.name.localizedCaseInsensitiveContains("airpods") ||
        device.name.localizedCaseInsensitiveContains("bluetooth")
    {
        if !cachedUIDs.contains(device.uid) {
            SettingsStore.shared.preferredInputDeviceUID = device.uid  // ← 自动覆盖用户设置！
            // ...自动切换...
        }
    }
}
```

**修改后逻辑**：
```swift
let priorityList = SettingsStore.shared.inputDevicePriorityList
if !priorityList.isEmpty {
    // 找出优先级最高的当前可用设备
    let available = currentDevices.filter { priorityList.contains($0.uid) }
    let sorted = available.sorted {
        (priorityList.firstIndex(of: $0.uid) ?? Int.max) <
        (priorityList.firstIndex(of: $1.uid) ?? Int.max)
    }
    if let bestDevice = sorted.first {
        let currentPriority = /* 当前已绑定设备的优先级 */
        if bestDevice.uid != currentDevice?.uid, bestPriority < currentPriority {
            // 有更高优先级的设备接入了，切换过去
            SettingsStore.shared.preferredInputDeviceUID = bestDevice.uid
            // 如果正在录音则走 audioRouteRecovery，否则直接绑定
        }
    }
    // 新设备追加到列表末尾（让用户决定排序）
    for device in currentDevices where !cachedUIDs.contains(device.uid) && !updatedList.contains(device.uid) {
        updatedList.append(device.uid)
    }
} else {
    // 没有优先级列表：保留原有 preferredUID 逻辑，但不再有蓝牙自动切换
}
```

---

### 3.3 InputDevicePriorityListView - 新增 UI 组件

**文件**：`Sources/Fluid/UI/InputDevicePriorityListView.swift`（**新建文件**）

这是一个纯 SwiftUI 组件，实现了麦克风优先级列表的可视化和交互。

#### 关键结构

```swift
struct InputDevicePriorityListView: View {
    @Binding var inputDevices: [AudioDevice.Device]   // 从父级 SettingsView 传入，保持实时同步
    @ObservedObject private var settings = SettingsStore.shared  // 监听 inputDevicePriorityList 变化

    // 构建显示列表：优先级列表中的设备在前（按序），未在列表中的连接设备追加在末尾
    private var displayItems: [PriorityItem] { ... }

    var body: some View {
        VStack {
            // 标题行 + "Initialize" / "Reset" 按钮
            HStack { ... }

            // 设备列表（带序号、绿/灰连接状态圆点、上下箭头）
            VStack(spacing: 0) {
                ForEach(Array(displayItems.enumerated()), id: \.element.uid) { index, item in
                    PriorityRowView(
                        item: item,
                        rank: index + 1,
                        isTopRanked: index == 0,
                        onMoveUp: index > 0 ? { self.move(uid: item.uid, direction: .up) } : nil,
                        onMoveDown: index < displayItems.count - 1 ? { self.move(uid: item.uid, direction: .down) } : nil
                    )
                }
            }
        }
    }

    // 排序逻辑：修改 settings.inputDevicePriorityList（由 objectWillChange 触发 UI 刷新）
    private func move(uid: String, direction: MoveDirection) {
        var list = settings.inputDevicePriorityList
        // 先把所有 displayItems 确保都在 list 中
        for item in displayItems where !list.contains(item.uid) {
            list.append(item.uid)
        }
        guard let idx = list.firstIndex(of: uid) else { return }
        switch direction {
        case .up where idx > 0:    list.swapAt(idx, idx - 1)
        case .down where idx < list.count - 1: list.swapAt(idx, idx + 1)
        default: return
        }
        settings.inputDevicePriorityList = list  // ← 触发 objectWillChange → 界面刷新
    }
}
```

#### 子视图 `PriorityRowView`

```swift
private struct PriorityRowView: View {
    let item: PriorityItem   // uid, name, isConnected
    let rank: Int
    let isTopRanked: Bool
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")           // 序号
            Circle()                  // 🟢 已连接 / ⚫ 未连接
                .fill(item.isConnected ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading) {
                Text(item.name)
                if isTopRanked && item.isConnected {
                    Text("Active — used for recording")
                        .foregroundStyle(Color.accentColor)  // ← 注意：必须用 Color.accentColor，不能用 .accentColor（编译错误）
                }
            }
            Spacer()
            // ↑↓ 排序箭头
            Button { onMoveUp?() } label: { Image(systemName: "chevron.up") }
            Button { onMoveDown?() } label: { Image(systemName: "chevron.down") }
        }
    }
}
```

---

### 3.4 SettingsView - 替换 Input Device 下拉菜单

**文件**：`Sources/Fluid/UI/SettingsView.swift`（约第 949-1095 行）

**原始代码**：Audio Devices 卡片中有一个 `Picker` 下拉菜单用于选择 Input Device。

**修改后**：将该 Picker 替换为 `InputDevicePriorityListView` 组件：

```swift
// 原始代码（已删除）：
// HStack {
//     Text("Input Device")
//     Picker("", selection: self.$selectedInputUID) { ... }
// }

// 修改后代码：
// --- Microphone Priority List ---
InputDevicePriorityListView(inputDevices: self.$inputDevices)
```

Output Device 的 Picker 保持不变。

---

### 3.5 MenuBarManager - 菜单栏 Microphone 菜单重构

**文件**：`Sources/Fluid/Services/MenuBarManager.swift`（约第 331-417 行）

**原始代码**：系统托盘菜单中有一个 `Microphone` 子菜单，用户可以点击展开并在其中选择麦克风。

**修改后代码**：由于我们在设置中引入了统一的“麦克风优先级列表”，为避免状态冲突和逻辑重复，将托盘区的 Microphone 子菜单移除。将其替换为一个静态的、只读的菜单项，用于**实时显示当前正在（或将要）使用的麦克风名称**（每次点击展开菜单时，都会基于优先级列表和当前已连接设备重新验证并显示）。

```swift
// 原始代码（已删除）：
// let microphoneSubmenu = NSMenu(title: "Microphone")
// let microphoneMenuItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
// microphoneMenuItem.submenu = microphoneSubmenu
// menu.addItem(microphoneMenuItem)

// 修改后代码（替换为只读文本）：
let microphoneMenuItem = NSMenuItem(title: "Microphone: ...", action: nil, keyEquivalent: "")
microphoneMenuItem.isEnabled = false  // 设为只读标签
menu.addItem(microphoneMenuItem)
```

并在 `refreshMicrophoneMenu()` 中加入了异步实时验证逻辑：
```swift
private func refreshMicrophoneMenu() {
    self.microphoneMenuItem?.title = "Microphone: checking…"
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        // 实时获取当前已连接设备，并查找在优先级列表中排名最高的设备
        let inputDevices = AudioDevice.listInputDevices()
        let priorityList = SettingsStore.shared.inputDevicePriorityList
        // ... (寻找 bestDevice) ...
        DispatchQueue.main.async { [weak self] in
            if let device = bestDevice {
                self.microphoneMenuItem?.title = "Mic: \(device.name)"
            }
        }
    }
}
```

---

## 4. 禁用自动升级功能

> **目标**：停止 app 的自动升级和手动升级行为，但保留版本号显示，以便用户知道是否有新版本。

---

### 4.1 AppDelegate - 禁用自动/手动检查

**文件**：`Sources/Fluid/AppDelegate.swift`

#### `applicationDidFinishLaunching` (约第 44-48 行)

```swift
// 原始代码（已注释）：
// self.checkForUpdatesAutomatically()
// self.schedulePeriodicUpdateChecks()

// 修改后代码：
// ── Update checks DISABLED for private build ──
// To re-enable: un-comment the two lines below.
// self.checkForUpdatesAutomatically()
// self.schedulePeriodicUpdateChecks()
```

#### `schedulePeriodicUpdateChecks()` (约第 143-153 行)

```swift
// 原始代码（已注释）：
// self.updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
//     self?.checkForUpdatesAutomatically()
// }

// 修改后代码：
private func schedulePeriodicUpdateChecks() {
    // ── DISABLED for private build ──
}
```

#### `checkForUpdatesManually()` (约第 157-209 行)

整个函数体替换为：

```swift
@objc func checkForUpdatesManually() {
    // ── DISABLED for private build ──
    // Auto-update and manual-update features are disabled.
    // Version display is retained in Preferences → App Updates.
    DebugLogger.shared.info("checkForUpdatesManually() called but update is disabled for this build.", source: "AppDelegate")
}
```

#### `checkForUpdatesAutomatically()` (约第 213-268 行)

整个函数体替换为：

```swift
private func checkForUpdatesAutomatically() {
    // ── DISABLED for private build ──
    DebugLogger.shared.debug("Automatic update check is disabled for this build.", source: "AppDelegate")
}
```

---

### 4.2 MenuBarManager - 移除菜单项

**文件**：`Sources/Fluid/Services/MenuBarManager.swift`

#### `buildMenuStructure()` (约第 338-358 行)

```swift
// 原始代码（已注释）：
// let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates(_:)), ...)
// menu.addItem(updateItem)
// let rollbackMenuItem = NSMenuItem(title: "Rollback to Previous Version...", ...)
// menu.addItem(rollbackMenuItem)

// 修改后代码：
// ── Check for Updates: DISABLED for private build ──
// Un-comment below to re-enable:
// let updateItem = NSMenuItem(title: "Check for Updates...", ...)
// menu.addItem(updateItem)
// ── Rollback: DISABLED ──
// ...
```

`updateMenuItemsText()` 中的 `self.rollbackMenuItem?.isEnabled = ...` 也一并注释。

---

### 4.3 SettingsView - 替换升级按钮为只读版本信息

**文件**：`Sources/Fluid/UI/SettingsView.swift`（约第 330-509 行）

**原始代码**：
- "Automatic Updates" 开关
- "Beta Releases" 开关
- "Check for Updates" 按钮
- "Release Notes" 按钮
- "Rollback" 按钮
- "Get Previous Builds" 按钮

**修改后代码**（保留版本号，删除所有操作按钮）：

```swift
VStack(alignment: .leading, spacing: 6) {
    Text("App Updates")
        .font(.body).fontWeight(.medium)

    // 始终显示当前版本
    Text("Current version: \(self.currentAppVersion)")
        .font(.caption).foregroundStyle(.tertiary)

    // 显示上次从服务器检查的时间（只读）
    if let lastCheck = SettingsStore.shared.lastUpdateCheckDate {
        Text("Last server check: \(lastCheck.formatted(...))")
            .font(.caption).foregroundStyle(.tertiary)
    }

    Text("⚠️ Auto-update & manual-update disabled. Version info above is for reference only.")
        .font(.caption).foregroundStyle(.secondary)

    /* ── DISABLED: Automatic Updates toggle ──
    ...所有原始代码保留在注释中，便于将来恢复...
    ── END DISABLED ── */
}
```

---

## 5. 编译并安装教程

请参阅：[`docs/compile_and_install_tutorial.md`](./compile_and_install_tutorial.md)

---

## 6. 并发修复：NetworkTransport

**文件**：`~/Library/Developer/Xcode/DerivedData/Fluid-*/SourcePackages/checkouts/swift-sdk/Sources/MCP/Base/Transports/NetworkTransport.swift`

> ⚠️ **重要**：此文件位于 Xcode 的自动生成目录，在 Xcode 清理或更新 Package 依赖后会被重置！
> 每次执行 `File → Packages → Reset Package Caches` 后，需要重新应用此修复。

**问题**：Swift 6 严格并发检查下，`send()` 和 `receiveData()` 方法中用 `var sendContinuationResumed = false` 局部变量跨异步边界存取，违反 isolation 规则。

**修复方案**：引入线程安全的 `ResumptionTracker` 类：

```swift
// 新增辅助类（在 NetworkTransport actor 定义之前）
@unchecked Sendable
private final class ResumptionTracker {
    private let lock = NSLock()
    private var _resumed = false

    var isResumed: Bool {
        lock.withLock { _resumed }
    }

    /// Returns true if this is the first call (i.e., not yet resumed)
    func markResumedIfNeeded() -> Bool {
        lock.withLock {
            if _resumed { return false }
            _resumed = true
            return true
        }
    }
}

// 在 send() 的 completion 闭包中：
let tracker = ResumptionTracker()
completion: .contentProcessed { [weak self] error in
    guard let self = self else { return }
    Task { [weak self] in
        guard let self = self else { return }
        if tracker.markResumedIfNeeded() {
            self.sendContinuation?.resume()
        }
    }
}
```

---

*文档最后更新：2026-05-03*  
*修改者：Max（基于 FluidVoice altic-dev/Fluid-oss 私有定制版本）*
