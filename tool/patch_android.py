"""在 `flutter create` 生成安卓工程后，补上本项目需要的设置：
最低 Android 10、正式签名、混淆保留规则。找不到要改的位置时直接报错。"""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
kts = root / "android/app/build.gradle.kts"
if not kts.exists():
    sys.exit("android/app/build.gradle.kts not found")
s = kts.read_text(encoding="utf-8")

s, n = re.subn(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 29", s)
if n != 1 and "minSdk = 29" not in s:
    sys.exit("minSdk line not found")

if "XHM_KEYSTORE" not in s:
    signing = '''
    signingConfigs {
        create("release") {
            val ks = System.getenv("XHM_KEYSTORE")
            if (ks != null && file(ks).exists()) {
                storeFile = file(ks)
                storePassword = System.getenv("XHM_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("XHM_KEY_ALIAS")
                keyPassword = System.getenv("XHM_KEY_PASSWORD")
            }
        }
    }

    buildTypes {'''
    s, n = re.subn(r"\n\s*buildTypes \{", signing, s, count=1)
    if n != 1:
        sys.exit("buildTypes block not found")
    s, n = re.subn(
        r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        'signingConfig = if (System.getenv("XHM_KEYSTORE") != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")\n'
        '            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")',
        s, count=1)
    if n != 1:
        sys.exit("release signingConfig line not found")

kts.write_text(s, encoding="utf-8")
(root / "android/app/proguard-rules.pro").write_text(
    "-keep class com.alexmercerind.** { *; }\n"
    "-keep class is.xyz.mpv.** { *; }\n"
    "-keep class com.vaneyi.xhmplayer.** { *; }\n"
    "-dontwarn com.google.android.play.core.**\n",
    encoding="utf-8")
print(s)
