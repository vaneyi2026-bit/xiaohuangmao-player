"""在模拟器上跑一遍主要流程并截图（GitHub Actions 中执行）。

流程：启动 → 外部打开导入测试视频 → 首页 → 播放（手势提示、控制条、AB 循环、面板）
→ 返回看继续观看卡片 → 媒体库 → 设置 → 深色模式。
"""
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

PKG = "com.vaneyi.xhmplayer"
OUT = "shots"
os.makedirs(OUT, exist_ok=True)
log = open(os.path.join(OUT, "smoke.log"), "w", encoding="utf-8")


def say(*a):
    msg = " ".join(str(x) for x in a)
    print(msg, flush=True)
    log.write(msg + "\n")
    log.flush()


def adb(*args, check=False, timeout=60):
    r = subprocess.run(["adb", *args], capture_output=True, timeout=timeout)
    if check and r.returncode != 0:
        say("adb failed:", args, r.stderr.decode(errors="ignore"))
    return r


def sh(cmd, timeout=60):
    return adb("shell", cmd, timeout=timeout).stdout.decode(errors="ignore").strip()


def shot(name):
    r = adb("exec-out", "screencap", "-p", timeout=30)
    with open(os.path.join(OUT, f"{name}.png"), "wb") as f:
        f.write(r.stdout)
    say("shot", name, len(r.stdout))


def screen():
    m = re.search(r"(\d+)x(\d+)", sh("wm size"))
    w, h = int(m.group(1)), int(m.group(2))
    d = int(re.search(r"(\d+)", sh("wm density")).group(1)) / 160
    # 当前方向
    rot = sh("dumpsys input | grep -m1 -i 'SurfaceOrientation'")
    if re.search(r"SurfaceOrientation:\s*[13]", rot):
        w, h = h, w
    return w, h, d


def tap(x, y):
    sh(f"input tap {int(x)} {int(y)}")
    time.sleep(0.6)


def dump():
    for _ in range(3):
        sh("rm -f /sdcard/ui.xml")
        sh("uiautomator dump /sdcard/ui.xml", timeout=40)
        x = sh("cat /sdcard/ui.xml")
        if x.startswith("<?xml"):
            try:
                return ET.fromstring(x)
            except ET.ParseError:
                pass
        time.sleep(1)
    return None


def find(pattern, root=None):
    root = root if root is not None else dump()
    if root is None:
        return None
    for n in root.iter("node"):
        label = (n.get("text") or "") + " | " + (n.get("content-desc") or "")
        if re.search(pattern, label):
            b = [int(v) for v in re.findall(r"\d+", n.get("bounds", ""))]
            if len(b) == 4:
                return ((b[0] + b[2]) / 2, (b[1] + b[3]) / 2)
    return None


def tap_text(pattern, wait=10):
    end = time.time() + wait
    while time.time() < end:
        p = find(pattern)
        if p:
            tap(*p)
            say("tap", pattern, p)
            return True
        time.sleep(1)
    say("NOT FOUND:", pattern)
    return False


def wait_text(pattern, wait=60):
    end = time.time() + wait
    while time.time() < end:
        if find(pattern):
            return True
        time.sleep(2)
    say("TIMEOUT waiting for", pattern)
    return False


def main():
    apk = sys.argv[1]
    say(adb("install", "-r", apk, timeout=240).stdout.decode(errors="ignore"))
    sh("settings put system screen_off_timeout 600000")
    sh("cmd uimode night no")
    adb("logcat", "-c")
    sh(f"am start -n {PKG}/.MainActivity")
    time.sleep(8)
    shot("01_首页_空")

    # 外部打开：模拟“用其他应用打开”
    adb("push", "lesson.mkv", "/data/local/tmp/lesson.mkv", check=True, timeout=120)
    sh("chmod 644 /data/local/tmp/lesson.mkv")
    sh(f"am start -a android.intent.action.VIEW -t video/x-matroska -d file:///data/local/tmp/lesson.mkv -n {PKG}/.MainActivity")
    wait_text("导入完成", 90)
    time.sleep(2)
    shot("02_导入面板")
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    time.sleep(3)
    shot("03_首页_有视频")

    # 播放
    if not tap_text("播放 lesson", 15):
        tap_text("lesson", 5)
    time.sleep(6)
    shot("04_播放_手势提示")
    if not tap_text("知道了", 8):
        w, h, d = screen()
        tap(w / 2, h / 2 + 150 * d)
    time.sleep(2)
    w, h, d = screen()
    say("screen", w, h, d)
    shot("05_播放中")
    tap(w / 2, h / 2)  # 显示控制条
    time.sleep(0.8)
    shot("06_控制条")
    # AB：先设 A，等 3 秒设 B
    ab = (w - (8 + 48 + 48 + 52 + 28) * d, h - (6 + 24) * d)
    tap(*ab)
    time.sleep(3)
    tap(w / 2, h / 2)
    time.sleep(0.5)
    tap(*ab)
    time.sleep(1.2)
    shot("07_AB循环")
    # 面板
    tap(w / 2, h / 2)
    time.sleep(0.5)
    tap(w - (8 + 24) * d, (8 + 24) * d)
    time.sleep(2)
    shot("08_播放面板")
    adb("shell", "input", "swipe", str(int(w / 2)), str(int(h * 0.55)), str(int(w / 2)), str(int(h * 0.1)), "400")
    time.sleep(1)
    shot("09_播放面板_字幕音轨")
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    time.sleep(1)
    # 长按 2 倍速
    adb("shell", "input", "swipe", str(int(w / 2)), str(int(h / 2)), str(int(w / 2)), str(int(h / 2)), "2500", timeout=30)
    # 退出播放器
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    time.sleep(1)
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    time.sleep(3)
    shot("10_首页_继续观看")
    tap_text(r"(^|\| )媒体库(\s|$)", 8)
    time.sleep(2)
    shot("11_媒体库")
    tap_text(r"(^|\| )设置(\s|$)", 8)
    time.sleep(2)
    shot("12_设置")
    sh("cmd uimode night yes")
    time.sleep(3)
    tap_text(r"(^|\| )观看(\s|$)", 8)
    time.sleep(2)
    shot("13_首页_深色")

    lc = adb("logcat", "-d", timeout=60).stdout.decode(errors="ignore")
    with open(os.path.join(OUT, "logcat.txt"), "w", encoding="utf-8") as f:
        f.write(lc)
    crashes = [l for l in lc.splitlines() if "FATAL EXCEPTION" in l or ("E flutter" in l) or "AndroidRuntime" in l]
    say("crash/flutter-error lines:", len(crashes))
    for l in crashes[:80]:
        say(l)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # 截图失败不影响发布
        say("SMOKE ERROR", repr(e))
