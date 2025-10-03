## BiliRoamingX · Copilot 指南（面向 AI 代理）

本仓库是基于 ReVanced 的 B 站 Android 增强方案，包含补丁包（patch-bundle JAR）与集成 APK（integrations.apk），以及原生 Hook（Dobby）。请遵循下列要点高效协作。

### 架构速览
- 模块划分
  - patches（Kotlin/JVM）：补丁定义与生成。输出补丁包 JAR 与 patches.json。
  - integrations/app（Android App）：运行时集成代码与资源、原生库（libbiliroamingx.so）。补丁将注入对该 APK 中代理/委托方法的调用。
  - integrations/dummy：仅编译期依赖的桩与三方 API（如 gRPC、AndroidX），供其他模块 compileOnly 参照。
  - integrations/extend：供 integrations/app 使用的库模块。
  - integrations/ksp：KSP 符号处理器，构建时生成所需代码（勿直接修改生成物）。
  - build-logic：统一 Android/NDK/CMake/JVM 版本与 buildType（含 dev）。
- 关键数据流
  1) ReVanced 加载 patches.jar 中的 @Patch 声明并修改宿主（B 站）字节码；
  2) 被修改的方法调用 integrations.apk 内的代理方法（如 Lapp/revanced/bilibili/patches/...）；
  3) 原生层通过 Dobby 进行 Hook；资源补丁通过 resources 合并。

### 构建与产物
- 快速开发构建：`./gradlew distDev`（禁用 full R8，较快）。
- 发布构建：`./gradlew dist`。
- 产物归并到顶层 `build/`：
  - APK：`BiliRoamingX-<module>-<version>.apk`（来自 `:integrations:app`）。
  - JAR：`BiliRoamingX-patches-<version>.jar`（含 classes.dex）。
  - patches.json：补丁元数据清单。
  - 注意：根任务会把 APK 的 `lib/**` 拷贝进 JAR 的 `bilibili/lib/**`（见根 `build.gradle.kts` 的 dist 任务）。
- 前置条件：为 `:patches:buildDexJar` 提供 d8（Android SDK）。需设置 ANDROID_HOME 或在 `local.properties` 写入 `sdk.dir`。

### 版本与构建约束
- 统一参数见 `build-logic/src/main/kotlin/Versions.kt`：compile/target SDK 35、minSdk 24、NDK 26.3、CMake 3.22.1、JVM 17（patches 模块使用 11）。
- `integrations/app` 的 `versionName` 来自 `gradle.properties` 的 `version`，versionCode 由主/次/修订按 m*1_000_000 + s*1_000 + f 计算。
- CMake 在 `integrations/app/src/main/jni/CMakeLists.txt`，链接 `integrations/libs/Dobby` 子模块（clone 时务必 `--recurse-submodules`）。

### 补丁开发约定（patches 模块）
- 典型形态：对象继承 `BytecodePatch` 或 `ResourcePatch`，使用 `@Patch` 声明 `name/description/compatiblePackages/use/dependencies` 等。
- 定位目标：`.../fingerprints` 内定义 Fingerprint；`execute(BytecodeContext)` 中通过扩展方法进行插桩（见 `patches/.../utils/Extenstions.kt`）。
- 注入调用到 integrations：以 Smali 形式插入调用，如 MainActivityPatch 将调用 `Lapp/revanced/bilibili/patches/main/MainActivityDelegate;->onCreate(...)V`。
- 资源补丁示例：`all/misc/packagename/ChangePackageNamePatch.kt`、`all/misc/debugging/EnableAndroidDebuggingPatch.kt`（默认 `use = false`）。

### 集成侧约定（integrations/app 模块）
- 被补丁调用的代理/委托实现位于 `integrations/app/src/main/java/app/revanced/bilibili/**`（例如 `patches/json/PegasusPatch.java`、`patches/main/MainActivityDelegate`）。保持方法签名与补丁注入一致。
- 构建特性：
  - buildTypes 包含 `dev` 与 `release`，两者均 minify；`distDev` 下强制关闭 full R8（见 R8Task 设置）。
  - 打包排除 `libc++_shared.so` 与部分 META-INF/kotlin 资源，避免与宿主重复。
  - 依赖：HiddenApiBypass、kotlinx-serialization、AndroidX DocumentFile（排除 annotation）。

### 常见问题与陷阱
- 未配置 Android SDK 导致 d8 不可用：`Android sdk not found.` → 设置 ANDROID_HOME 或 `local.properties`。
- 未递归拉取子模块导致 Dobby 缺失：构建原生失败 → `git clone --recurse-submodules ...`。
- 产物重命名/路径不符会导致根 dist 任务无法归并或 JAR 未包含 `bilibili/lib/**`。

### 外部打包（供使用者）
- 参考 README：使用自定义 revanced-cli 合并补丁与集成 APK。
  `java -jar revanced-cli.jar patch --merge integrations.apk --patch-bundle patches.jar --signing-levels 1,2,3 bilibili.apk`

### 快速定位与参考
- 根构建与归并逻辑：`build.gradle.kts`（dist/distDev）。
- 补丁生成：`patches/build.gradle.kts`（buildDexJar、generatePatchesFiles）与 `patches/src/main/kotlin/app/revanced/generator/*`。
- 代表性补丁：
  - `.../misc/integrations/patch/MainActivityPatch.kt`（主界面代理），
  - `.../misc/config/patch/ConfigPatch.kt`（配置代理），
  - `.../misc/json/patch/PegasusPatch.kt`、`.../misc/copy/patch/CopyEnhancePatch.kt`。

如果上述任何部分不清晰（尤其是补丁与集成方法签名匹配、dist 归并细节、KSP 产物位置），请指出我来补充或修正。
