# 编译并安装 FluidVoice 到你的 Mac 上

这份教程将手把手教你如何将刚才修改过的源代码编译打包，变成一个可以直接在你的 MacBook 上运行的独立 `.app` 桌面软件。

为了保证一次成功，我们使用最稳定、最标准的方式：**通过官方的 Xcode 工具进行图形化编译和打包。**

---

### 第一步：准备工作
1. 请确保你的 Mac 上已经安装了 **Xcode**。如果没有安装，请前往 Mac App Store 搜索 "Xcode" 并免费下载安装。
2. 确保你有一个 **Apple ID**（也就是你平时登录 iCloud 或在 App Store 下载软件时用的免费账号）。**这不需要花一分钱**。

### 第二步：使用 Xcode 打开项目
1. 打开 Finder，找到你存放源代码的目录：`/Users/max/dev/FluidVoice`。
2. 找到名为 **`Fluid.xcodeproj`** 的文件（带有蓝色图标），双击打开它。
3. 第一次打开时，Xcode 会自动在后台获取相关的依赖包（Swift Packages），你可以稍等它加载完毕。

### 第三步：配置免费本地签名 (非常关键)
macOS 默认要求所有运行的桌面软件必须经过签名。我们可以**完全免费**使用你的普通 Apple ID 进行本地签名。
1. 在 Xcode 最左侧的目录树中，点击最顶部的蓝色项目图标 **`Fluid`**。
2. 在主窗口的左侧 **TARGETS** 列表中，选中 **`FluidVoice`**。
3. 点击主窗口顶部的 **`Signing & Capabilities`** 选项卡。
4. 勾选 **"Automatically manage signing"**。
5. 在下方的 **Team** 下拉菜单中，选择你的个人账号（例如 "你的名字 (Personal Team)"）。
   > *说明：如果 Team 菜单里没有选项，点击 "Add an Account..."，然后输入你的普通 Apple ID 和密码登录即可。登录后就会出现包含 "Personal Team" 的免费选项。*

### 第四步：编译并生成 App (Archive)
1. 在 Xcode 窗口的最顶部，你会看到一个类似 `FluidVoice > My Mac` 的设备选择器。点击它，确保目标设备选择了 **`Any Mac (Apple Silicon)`** 或者 **`My Mac`**。
2. 点击屏幕最顶部的苹果系统菜单栏，选择 **`Product`** -> **`Archive`**。
3. Xcode 现在会开始全面编译你的代码。这可能需要花费几分钟时间。编译完成后，屏幕上会出现 "Build Succeeded" 的提示。

### 第五步：导出并安装软件
1. 编译完成后，Xcode 会自动弹出一个名叫 **Organizer (归档管理器)** 的独立窗口。
2. 在该窗口中，确保刚刚生成的 FluidVoice 归档被选中，然后点击右侧的 **`Distribute App`** 按钮。
3. 接下来弹出的选项窗口中，选择 **`Custom`**，然后点击 **Next**。
4. 在下一步中，选择 **`Copy App`**（拷贝 App），点击 **Next**。
5. 选择一个你容易找到的导出位置（例如你的 **桌面 Desktop**），点击 **Export**。
6. 回到电脑桌面，你会看到一个导出的文件夹，里面包含了最终打包好的 **`FluidVoice.app`**。
7. 将这个 **`FluidVoice.app`** 拖拽到你的 **应用程序 (Applications)** 文件夹中。

🎉 **大功告成！** 
现在你可以按 `Command + 空格` 呼出 Spotlight 搜索，直接输入 FluidVoice，像正常软件一样打开它了！
之前为你修改好的“自动默认识别中文”和“本地隐私保护”功能，都已经在里面生效了。
