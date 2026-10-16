# 小黄毛影音（安卓版）

个人视频播放器，供自用和同事朋友小范围分享。不上架、不收费、无广告、无账号，不上传任何数据。

需求依据：《小黄毛影音播放器 产品需求文档 V1.1》。

## 首版已实现（P0）

| 编号 | 功能 | 说明 |
|---|---|---|
| F01 | 相册与文件导入 | 系统照片选择器（Android 11+ 有扩展版本时）/ 文档选择器；复制到 App 内，显示进度；可取消、重试；空间检查（文件大小 + 100 MB）；按"文件名＋大小"提示重复 |
| F02 | 外部打开 | “用其他应用打开”和“分享”视频文件；分享链接时提示暂不支持 |
| F03 | 媒体库与继续观看 | 继续观看卡片、最近观看（最多 200 条）、最近添加、收藏；搜索、排序、筛选、改名、多选连续播放、删除 |
| F05 | 播放控制与手势 | 单击、双击 ±10 秒、左右滑动调进度、左侧亮度、右侧音量、长按 2 倍速、锁屏、画面比例、倍速（变速不变调）、播放时屏幕常亮 |
| F06 | 字幕与音轨 | 内封字幕和音轨切换；外挂 SRT / ASS；UTF-8 / UTF-16 / GBK(GB18030) 自动识别，可手动切换（含 Big5）；字幕时间 ±0.1 秒；字号三档 |
| F07 | 中断与数据 | 切后台、来电、其他 App 播放声音、拔耳机都会暂停；每 5 秒保存进度；清缓存、清记录、删除全部 |
| F08 | AB 循环 | 设 A、设 B、0.5 秒微调、拖出区间自动退出、按视频保存并可恢复 |

ASS 字幕目前按纯文本显示（保留文字，不显示特效）。

## 代码结构

```
lib/
  main.dart              入口、底部导航、外部分享处理
  store.dart             媒体库、观看记录、偏好（library.json）
  import_service.dart    导入队列
  native.dart            安卓原生能力封装
  pages/                 观看、媒体库、设置、导入面板、播放器
  widgets/               缩略图、进度条等
android/app/src/main/kotlin/.../MainActivity.kt
                         选择器、带进度复制、缩略图、字幕编码、亮度音量、音频焦点
tool/patch_android.py    构建时补充安卓配置（最低 Android 10、签名）
```

`android/` 下只提交了自己写的文件，其余由 `flutter create` 在构建时生成。

## 构建

推送到 `main` 分支后，GitHub Actions 自动构建，安装包发布在本仓库的 **Releases** 里。

本地构建（需要 Flutter SDK 和 Android SDK）：

```bash
flutter create --platforms=android --org com.vaneyi --project-name xhmplayer .
python3 tool/patch_android.py
flutter build apk --release --target-platform android-arm64
```

## 正式签名

未配置签名时，每次构建都会用一次性的调试签名，新版本不能覆盖安装旧版本。
配置方法：在仓库 **Settings → Secrets and variables → Actions** 添加
`XHM_KEYSTORE_B64`（密钥库文件的 base64）、`XHM_KEYSTORE_PASSWORD`、`XHM_KEY_ALIAS`、`XHM_KEY_PASSWORD`。
密钥库丢失后无法再覆盖升级，请备份。

## 开源许可

播放组件 media_kit（MIT），内含 libmpv、FFmpeg（LGPL 等）。App 内“设置 → 关于与开源声明”列出全部许可。
