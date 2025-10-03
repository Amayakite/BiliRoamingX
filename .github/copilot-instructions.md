## BiliRoamingX · Copilot 指南（面向 AI 代理，简明版）

本仓库基于 ReVanced，为哔哩哔哩注入增强功能；产物包括补丁包 JAR（patch-bundle）与集成 APK（integrations.apk），并含原生 Hook（Dobby）。

### 架构与数据流
- 模块：
  - patches（Kotlin/JVM 11）：定义补丁与生成补丁包；输出 patches.jar 与 patches.json。
  - integrations/app（Android App）：运行时代理/资源与原生库 `libbiliroamingx.so`。
  - integrations/dummy（编译期桩）、integrations/extend（库）、integrations/ksp（KSP 处理器）、build-logic（统一版本与构建配置）。
- 流程：ReVanced 读取 patches.jar 中的 `@Patch` → 修改宿主字节码 → 调用 `integrations.apk` 中代理类（如 `Lapp/revanced/bilibili/...`）→ 原生通过 Dobby Hook；资源补丁通过资源合并。

### 构建与产物（根目录执行）
- 开发构建：`./gradlew distDev`（minify 且关闭 full R8，较快）。发布构建：`./gradlew dist`。
- 输出至 `build/`：`BiliRoamingX-integrations-<ver>.apk`、`BiliRoamingX-patches-<ver>.jar`（含 classes.dex）与 `patches.json`、`mapping.txt`。
- dist 会把 APK 的 `lib/**` 拷贝到 JAR 的 `bilibili/lib/**`（见根 `build.gradle.kts` 的 dist 任务）。
- 前置：提供 d8（设置 ANDROID_HOME 或 `local.properties` 的 `sdk.dir`）；clone 时使用 `--recurse-submodules` 以包含 `integrations/libs/Dobby`。

### 版本/构建约束与差异
- 统一参数见 `build-logic/src/main/kotlin/Versions.kt`：compile/target SDK 35、minSdk 24、NDK 26.3、CMake 3.22.1、JVM 17（仅 patches 使用 JVM 11）。
- `integrations/app` versionName 取自根 `gradle.properties` 的 `version`；versionCode = m*1_000_000 + s*1_000 + f。
- CMake：`integrations/app/src/main/jni/CMakeLists.txt` 链接 Dobby 子模块。

### 开发补丁（patches 模块）
- 新增补丁：继承 `BytecodePatch` 或 `ResourcePatch` 并用 `@Patch` 声明 `name/compatiblePackages/use/dependencies` 等。
- 目标定位：在 `.../fingerprints` 定义 Fingerprint；在 `execute(BytecodeContext)` 内用扩展方法做插桩。
- 注入调用：以 Smali 形式调用 integrations 代理，例如 `MainActivityPatch` 调用
  `Lapp/revanced/bilibili/patches/main/MainActivityDelegate;->onCreate(...)V`。
- 代表路径（示例）：`.../misc/integrations/patch/MainActivityPatch.kt`、`.../misc/config/patch/ConfigPatch.kt`、`.../misc/json/patch/PegasusPatch.kt`。

### 集成侧约定（integrations/app）
- 代理实现位于 `integrations/app/src/main/java/app/revanced/bilibili/**`（如 `patches/json/PegasusPatch.java`、`patches/main/MainActivityDelegate`）。务必与补丁注入的方法签名完全一致。
- buildTypes：`dev` 与 `release` 均 minify；`distDev` 关闭 full R8。打包排除 `libc++_shared.so` 与部分 META-INF/kotlin 资源。
- 依赖：HiddenApiBypass、kotlinx-serialization、AndroidX DocumentFile（排除 annotation）。KSP 代码为生成物，勿直接修改（默认在各模块 `build/generated/...`）。

### 外部打包与快速验证
- 用 revanced-cli 合并：`java -jar revanced-cli.jar patch --merge integrations.apk --patch-bundle patches.jar --signing-levels 1,2,3 bilibili.apk`。
- 快速验证：微调某个代理/补丁 → 运行 `distDev` → 检查 `build/` 产物存在并体积合理 → 使用上面命令对目标 bilibili.apk 试合并。

### 常见陷阱（优先排查）
- 未配置 Android SDK/d8 → `Android sdk not found.`；未拉取子模块 → Dobby 缺失导致原生构建失败。
- 代理方法签名不匹配 → 运行时崩溃或 NPE；产物重命名/路径变更 → dist 无法归并或 JAR 丢失 `bilibili/lib/**`。

### 关键参考文件/目录
- 根构建与归并：`build.gradle.kts`；补丁生成：`patches/build.gradle.kts` 与 `patches/src/main/kotlin/app/revanced/generator/*`。
- Dobby：`integrations/libs/Dobby/**`；原生 CMake：`integrations/app/src/main/jni/CMakeLists.txt`。

如需补充（例如具体 KSP 产物路径、更多代表性补丁位置、调试/日志最佳实践），请告诉我以便完善本指南。
