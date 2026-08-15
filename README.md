# TelegramForHarmony

一个开源的**非官方 HarmonyOS NEXT Telegram 客户端**。使用 ArkTS/ArkUI 编写，
通过原生 N-API 桥接 [TDLib](https://core.telegram.org/tdlib)（Telegram 官方客户端库）。

## 功能

- 登录与账号：
  - 手机号登录、国家/地区区号选择与搜索、验证码和两步验证密码
  - 根据 TDLib 返回结果区分应用内验证码、短信、电话等验证码送达方式
  - 多账号登录、切换与退出；记住最后使用的账号并在下次启动时恢复
- 会话列表：
  - 文件夹、归档、未读角标、实时更新与连接状态提示
  - 新建群组、打开“我的收藏”
  - 正在直播的聊天显示动态头像角标
- 聊天页：
  - 富文本（链接、提及、代码、引用）、图片（低清 → 高清渐进加载）、
    图片/视频九宫格相册（瀑布流布局）
  - 视频流式播放（完整播放器控件）、贴纸（静态 WEBP、TGS 动画、WEBM 视频贴纸）、
    动态表情与自定义表情
  - 文件（下载 / 打开 / 另存）、链接预览、回复（可跳转原消息）、转发、
    表情回应、频道评论串、Bot 内联键盘、置顶消息、日期分隔与浮动日期条、
    未读分界定位
  - 消息多选：批量复制、删除（含“为所有人删除”）
  - 定时消息管理：查看待发送列表，可立即发送或删除
- 发送：文字、自定义表情、`@` 提及与 `/` 命令自动补全、照片与视频（含相册）、
  文件、音乐、语音消息、位置、联系人名片、投票（支持匿名与测验模式）、
  骰子/飞镖/篮球/足球/保龄球/老虎机（播放官方结果动画）
- 新建群组与频道；对联系人可发起端到端加密的秘密聊天
- 全屏媒体查看器：打开/关闭的 Hero 转场、左右滑动切换、缩略图条、保存到相册
- 全局搜索：11 个标签页（聊天/频道/应用/帖子/公开贴文/媒体/下载/链接/文件/音频/语音），
  支持左右滑动切换与滚动自动翻页
- 联系人与群组：
  - 联系人列表按在线状态排序，可搜索本地联系人和服务器可发现的陌生用户
  - 支持通过姓名或 `@用户名` 打开陌生用户私聊
  - 新建群组支持搜索、选择本地联系人或陌生用户，已选成员跨搜索保留
- 一对一语音/视频通话：
  - 基于 TDLib 信令与 tgcalls（InstanceV2）原生媒体，端到端加密
  - 拨出、来电接听/拒接，通话中静音、扬声器、开关摄像头、前后摄切换
  - 四个密钥校验 emoji、通话计时；通话期申请 voip 长时任务，切后台不断线
  - 通话记录页支持长按回拨
- 论坛话题（Topics）：
  - 话题群自动进入话题列表（未读角标、最后消息预览、置顶与关闭标记）
  - 话题内独立消息流；新建话题，长按管理置顶/关闭/重命名/删除
  - 话题信息与未读状态实时刷新
- 故事（Stories）：
  - 聊天列表顶部故事环，未读/已读环状态区分
  - 全屏查看器：分段进度条、照片定时与视频播放、点击左右切换、长按暂停、
    看完自动切换下一位，观看状态自动上报
- 本地通知与后台能力：
  - 应用在后台时新消息、来电经系统通知触达，点击直达对应会话
  - 静音、通知例外、消息预览等规则由 TDLib 通知管理器统一处理
  - 延迟任务定时补收（进程被系统回收期间），不做常驻保活
  - 后台播放设置：音乐、语音消息、视频、直播四类可独立开关
- 群组语音与频道直播：
  - 实时展示直播状态、在线人数与进入确认；状态随直播创建/结束自动更新
  - 普通视频聊天支持多人语音、多路摄像头/屏幕共享、活跃说话人和麦克风状态
  - 本机开麦、前后摄像头切换、摄像头与系统录屏同时推流
  - 无视频时自动收起视频区域；多路视频按网格展示，支持横竖屏自适应与全屏
  - 支持应用内直播悬浮窗、大小窗切换及返回完整直播页
  - 支持频道单向直播观看和实时互动消息；频道消息可直接显示并从直播页发送
  - 音视频断流后自动重连并恢复订阅、麦克风和说话状态
- 资料页：
  - 用户/Bot 详情（简介、用户名、商务信息、故事、Stars 礼物赠送、共同群组）
  - 群组/频道详情（简介、邀请链接、成员列表）
  - 个人资料：设置头像（拍照 / 相册 / 表情）、编辑账号（姓名、简介、用户名、生日）、
    动态头像与 emoji 状态、二维码名片
- 设置：
  - 账号信息、多账号入口、聊天设置、隐私与安全、通知、数据与存储、聊天文件夹
  - 设备与会话管理：查看当前/活跃会话、接受通话与私密聊天、终止会话、
    终止其他会话和不活跃会话自动退出时间
  - 省电模式：按电量阈值自动生效，可独立控制动态贴纸、动态表情、聊天特效、
    通话动画、视频/GIF 自动播放、粒子效果和平滑转场
- 深色模式：跟随系统切换

> 陌生用户搜索遵循 Telegram/TDLib 的服务端可发现性规则，通常只能找到拥有公开
> 用户名或已进入服务端搜索范围的用户，不能通过该功能枚举任意手机号。

## 目录结构

```
AppScope/            应用级配置（包名、图标）
entry/src/main/ets/
  tdkit/             TDLib N-API 桥、客户端、鉴权服务
  store/             不可变 store + 订阅机制（会话、消息、资料等）
  pages/             ArkUI 页面（登录、会话列表、聊天、资料、搜索……）
  services/          媒体流式播放、直播后台任务、语音录制与播放
  util/              解析/格式化工具（富文本、相册、日期……）
entry/src/main/cpp/  原生桥（libentry.so → libtdjson.so / libtgcalls_ohos.so）
entry/src/test/      单元测试（通过 scripts/run-local-tests.sh 运行）
scripts/             TDLib/tgcalls 拉取与编译脚本、本地测试门禁
```

## 构建

### 环境要求

- **DevEco Studio 6.0+**（项目 `compatibleSdkVersion 6.0.0(20)`、
  `targetSdkVersion 6.1.1(24)`），含自带的 OpenHarmony SDK/NDK
- `curl` 与 `file`（macOS/Linux 自带）

### 1. 获取原生库 `libtdjson.so` / `libtgcalls_ohos.so`

应用以预编译原生库的形式内置 TDLib 和 tgcalls，路径为
`entry/libs/arm64-v8a/`（合计约 50 MB，未提交到仓库）。`libentry.so` 同时链接
这两个库，**缺任何一个都会让构建停在 ninja 的
`missing and no known rule to make it`**。二选一：

**方式 A — 下载预编译产物（推荐）：**

```bash
bash scripts/fetch-libs.sh [tag]   # 两个库一起从本仓库的 GitHub Releases 下载
```

不带参数时脚本会自动解析最新的 Release。注意不要退回用滚动 tag
`tdlib-latest`：它的 `libtdjson.so` 保持更新，但 `libtgcalls_ohos.so` 落后于各个
版本化 Release，在两个库都必需之后已不适合作为默认值。

**方式 B — 从源码编译（较新的 Mac 上约 10-15 分钟）：**

```bash
# 需要 C++ 工具链与依赖：clang（Xcode CLT）、cmake、ninja、gperf、patchelf
export OHOS_NDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
bash scripts/build-tdlib.sh
```

该脚本端到端封装了
[`ErBWs/tdlib-ohos-build`](https://github.com/ErBWs/tdlib-ohos-build)：用 DevEco
NDK 为 arm64-v8a 交叉编译 OpenSSL（静态，`1_1_1w`）与 TDLib（release **1.8.65**），
在宿主机预先生成 TDLib 的 TL-schema 源码（交叉编译时必需），用 `patchelf` 把
SONAME 规范化为 `libtdjson.so`（不做这一步，原生桥会**静默**加载失败），
最后把产物拷贝到 `entry/libs/arm64-v8a/`。脚本还修复了上游构建脚本的若干 macOS
兼容性问题，且是幂等的 —— 可以放心重复执行。

### 2. 获取 `libtgcalls_ohos.so`

聊天/频道直播使用移植到 HarmonyOS 的 `tgcalls` 生成真实的 ICE/DTLS join payload，
并提供 RTC 与频道广播的音视频收发。当前支持普通视频聊天的本机开麦、前后摄像头
切换、系统录屏推流和多路远端摄像头/屏幕共享，同时支持 TDLib 分片直播及 RTMP
unified 直播观看；画面直接渲染到 ArkUI XComponent，音频通过 OHAudio 播放/采集。

如果上一步用了方式 A，这个库已经一并下载好了，本节可跳过。只有需要自行编译时才运行：

```bash
bash scripts/build-tgcalls-ohos.sh
```

脚本会把产物安装到 `entry/libs/arm64-v8a/libtgcalls_ohos.so`。首次运行需下载并
编译 WebRTC，耗时较长；版本固定和当前媒体能力边界见
[`scripts/tgcalls/README.md`](scripts/tgcalls/README.md)。

### 3. Telegram API 凭据

TDLib 需要你自己的 `api_id`/`api_hash` —— 本仓库不提供任何凭据。

1. 在 <https://my.telegram.org/apps> 注册一个应用。
2. 把 `entry/src/main/ets/tdkit/ApiCredentials.template.ets` 复制为同目录下的
   `ApiCredentials.ets`。
3. 用你自己的凭据生成打包后的常量，并把打印出来的三个常量粘贴进去：

   ```bash
   node scripts/gen-creds.mjs <api_id> <api_hash>
   ```

`ApiCredentials.ets` 已被 gitignore —— **切勿提交真实凭据**，一旦泄露请立即吊销重建。
这里的值只做混淆（并非加密），仅用于提高从安装包中随手提取的门槛。

### 4. 签名

`build-profile.json5` 中的 `signingConfigs` 为空。用 DevEco Studio 打开项目，通过
**File > Project Structure > Signing Configs > Support HarmonyOS Auto-Sign**
（需要华为开发者账号）在本地生成调试证书。任何签名材料都不需要提交或分享。

### 5. 构建与运行

用 DevEco Studio 打开并在 HarmonyOS NEXT 设备/模拟器上运行，或使用命令行：

```bash
hvigorw assembleHap --no-daemon
```

运行单元测试门禁：

```bash
./scripts/run-local-tests.sh    # 必须输出 "LOCAL TESTS: PASS"
```

该脚本会先跑 i18n 检查，再跑单测 —— 静态检查一秒出结果，不该排在两分钟的
测试构建后面。

### 6. 本地化

界面文案全部在资源文件里。源语言（简体中文）放在
`entry/src/main/resources/base/element/string.json`，译文放在语言限定词目录
（如 `en_US/element/string.json`）；复数在 `element/plural.json`。系统按设备
语言自动匹配，匹配不到时回落 `base`。设置 → 语言可以在「跟随系统 / 简体中文 /
English」之间切换。

**`$r()` 还是 `str()`。** 组件渲染的文案一律用 `$r('app.string.x')`：它是一个
`Resource`，ArkUI 在配置变更时会重新解析，所以切语言能当场生效。`str('x')`
返回的是普通字符串，构建时就定死了 —— 只在确实需要 `string` 的地方用：
`string` 类型的 `@State`、模型字段、比较、`.join()`、以及非 UI 代码。
`@Builder` 参数遇到类型冲突时把它放宽成 `ResourceStr`，不要把调用点改回
`str()`。

**模块级 `const` 不能装文案。** 常量在首次 import 时就构建了，那时字符串源
还没装好，语言会被冻在那一刻。改成函数（`fallbackCountries()` 而不是
`FALLBACK_COUNTRIES`）。

**不要拿显示文案当状态匹配。** `label.substring(0, 2)`、`text.includes('重试')`
这类写法在换语言的瞬间就失效，判断要落在结构化字段上。

只进 `console.*` 的诊断字符串不翻译，用 `// i18n-exempt: <理由>` 标注。

工具：

```bash
node scripts/i18n-extract.mjs               # 按域统计仍硬编码的中文文案
node scripts/i18n-extract.mjs --domain util # 某个域的明细与 key 建议
node scripts/i18n-lit.mjs <file>            # 列出单个文件的中文字面量与行号
node scripts/i18n-check.mjs                 # 门禁（已并入 run-local-tests.sh）
```

`i18n-check.mjs` 检查五件事：代码引用的 key 在 `base` 中存在；`base` 里的每个
key 都能在代码中找到引用；**资源值里不得残留 `${` 模板源，且各语言的占位符编号
集合必须一致**；语言目录没有 `base` 之外的孤儿 key、各语言缺哪些词条；
**已纳入门禁的目录中不得再出现中文字面量**。

第三条是补上的 —— 门禁、单测、编译器各自能看见一类错误，但谁都看不见
「`file_downloading` 的值是 `${sizeLabel} · 正在下载` 这段模板源本身」，这种
错误只会在设备上显形。

`scripts/i18n-config.mjs` 的 `MIGRATED` 现在覆盖全部源码目录 —— 新建目录要一并
加进去，否则门禁会悄悄跳过它。key 命名 `<域>_<组件>_<语义>`，如
`chat_forward_title`。

## 状态与声明

- 开发中；界面以尽量贴近官方 Android 客户端为目标。
- 这是一个**非官方**客户端。请使用你自己的 API 凭据，并遵守
  [Telegram API 服务条款](https://core.telegram.org/api/terms)。

## 许可证

[Apache License 2.0](LICENSE)
