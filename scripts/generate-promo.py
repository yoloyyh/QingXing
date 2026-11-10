#!/usr/bin/env python3
"""Compose standalone promo SVGs from the app's existing SwiftUI UI exports.

Run scripts/render-promo.py to export 4x native UI and generate these assets.
Source images live in .build/promo-reference/{health,ui,themes}.
The PNG UI is embedded in each SVG to preserve the native artwork and controls.
"""
import base64
from html import escape
from pathlib import Path
import shutil
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Resources/promo"
OUT.mkdir(parents=True, exist_ok=True)
REF = OUT / "app-renders"
REF.mkdir(exist_ok=True)
PAPER, INK, ACCENT, MUTED = "#F5F7F7", "#2B3D57", "#406B94", "#68747F"

SOURCES = {
    "full-dashboard.png": "health/full-dashboard-light.png",
    "health-ring-states.png": "health/health-ring-states.png",
    "adjustment.png": "health/adjustment-mist-light.png",
    "full-mist.png": "health/full-mist-light.png",
    "full-amber.png": "health/full-amber-light.png",
    "full-latte.png": "health/full-latte-light.png",
    "distance.png": "ui/distance-gentle.png",
    "head-down.png": "ui/owl-head-down.png",
    "theme-comparison.png": "themes/theme-comparison.png",
}
LOGICAL_SIZES = {
    "full-dashboard.png": (366, 718), "health-ring-states.png": (859, 318),
    "adjustment.png": (360, 334), "full-mist.png": (360, 416),
    "full-amber.png": (360, 416), "full-latte.png": (360, 416),
    "distance.png": (360, 363), "head-down.png": (278, 250),
    "theme-comparison.png": (954, 503),
}
for name, relative in SOURCES.items():
    source = ROOT / ".build/promo-reference" / relative
    data = source.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Expected a PNG UI render: {source}")
    width, height = struct.unpack(">II", data[16:24])
    minimum_w, minimum_h = LOGICAL_SIZES[name]
    if width < minimum_w * 4 or height < minimum_h * 4:
        raise ValueError(f"{name} is only {width} x {height}; run scripts/render-promo.py for 4x UI renders")
    shutil.copyfile(source, REF / name)


def rect(x, y, w, h, fill="white", radius=20, extra=""):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}" {extra}/>'


def text(x, y, value, size=20, color=INK, weight=400, anchor="start"):
    return f'<text x="{x}" y="{y}" font-size="{size}" fill="{color}" font-weight="{weight}" text-anchor="{anchor}">{escape(value)}</text>'


def png(name, x, y, w, h, rounded=False):
    data = base64.b64encode((REF / name).read_bytes()).decode("ascii")
    frame = rect(x, y, w, h, PAPER, 22, 'filter="url(#shadow)"') if rounded else ""
    return frame + f'<image x="{x}" y="{y}" width="{w}" height="{h}" preserveAspectRatio="xMidYMid meet" href="data:image/png;base64,{data}"/>'


def write(name, width, height, title, parts):
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 {width} {height}" width="{width}" height="{height}" role="img" aria-labelledby="title desc">
<title id="title">{escape(title)}</title>
<desc id="desc">轻醒宣传素材。App 界面来自现有 SwiftUI 视图的本机渲染，展示示例状态。画面不包含摄像头照片。</desc>
<defs><filter id="shadow" x="-20%" y="-15%" width="140%" height="140%"><feDropShadow dx="0" dy="8" stdDeviation="12" flood-color="#2B3D57" flood-opacity=".08"/></filter>
<marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0 0 L8 4 L0 8 Z" fill="{ACCENT}"/></marker></defs>
<g font-family="-apple-system, BlinkMacSystemFont, 'PingFang SC', 'Microsoft YaHei', sans-serif">
{rect(0, 0, width, height, PAPER, 28)}
{''.join(parts)}</g></svg>'''
    (OUT / name).write_text(svg, encoding="utf-8")


def header(kicker, title, subtitle):
    return [text(64, 48, "轻醒 · QingXing / " + kicker, 18, ACCENT, 600),
            text(64, 104, title, 40, INK, 600), text(64, 141, subtitle, 19, MUTED)]


def foot(y, note="界面由 App 原生视图直接渲染 · 数值与状态为演示示例"):
    return text(64, y, note, 14, MUTED)


p = header("01", "认真工作，也记得坐舒服。", "提醒距离、轻轻抬头，陪你在休息后满血再出发。")
p += [text(96, 185, "主窗口 · 满血状态", 17, ACCENT, 600),
      png("full-dashboard.png", 96, 207, 366, 719, True),
      text(628, 185, "距离提醒 · 大眼睛和晕圈", 17, ACCENT, 600),
      png("distance.png", 602, 207, 360, 364, True),
      text(628, 623, "低头提醒 · 轻轻抬起头", 17, ACCENT, 600),
      png("head-down.png", 644, 645, 278, 251, True), foot(967)]
write("qingxing-01.svg", 1100, 995, "轻醒真实主窗口与距离、低头提醒", p)

p = header("02", "休息给你充能，调整值得庆祝。", "健康环随工作与休息变化，每次确认调整都会收到小伙伴的回应。")
p += [png("health-ring-states.png", 64, 176, 972, 360),
      png("adjustment.png", 90, 564, 360, 334, True),
      text(546, 623, "调整成功 +1", 34, ACCENT, 600),
      text(546, 667, "坐回舒服的位置，复查确认后再庆祝。", 20),
      text(546, 709, "今日调整、今日充满分别累计，", 20, MUTED),
      text(546, 741, "让每次小小的改变都看得见。", 20, MUTED),
      text(546, 811, "满血状态会保留，准备好再出发。", 19, ACCENT, 500), foot(939)]
write("qingxing-02.svg", 1100, 970, "真实健康环三阶段与调整奖励卡片", p)

p = header("03", "给小伙伴，换个喜欢的颜色。", "雾蓝、琥珀棕、奶咖 · 健康环、猫头鹰与按钮同步换色。")
themes = [("mist", "雾蓝", 64, "#406B94", "#A3C4D9", "#F5F7F7"),
          ("amber", "琥珀棕", 402, "#784A29", "#D4A86E", "#FAF5E8"),
          ("latte", "奶咖", 740, "#99544D", "#D9BAA1", "#FAF2F0")]
for key, label, x, accent, feather, paper in themes:
    p += [text(x + 148, 208, label, 25, accent, 600, "middle"),
          png("full-" + key + ".png", x, 232, 296, 342.044, True),
          text(x + 148, 616, "主色 · 羽毛 · 背景", 16, MUTED, anchor="middle")]
    for offset, color in enumerate([accent, feather, paper]):
        p.append(rect(x + 91 + offset * 42, 635, 30, 30, color, 10,
                      'stroke="#2B3D57" stroke-opacity=".12"'))
p += [foot(721, "三种主题均为 App 的原生满血提醒卡片 · 保留真实配色、猫头鹰和健康环")]
write("qingxing-03.svg", 1100, 752, "轻醒三种主题的真实满血提醒卡片", p)

p = header("04", "看一眼就好，画面留在本机。", "摄像头按轮次开启，检测结束后关闭并释放。")
p += [rect(64, 179, 972, 73, "white", 18),
      text(94, 225, "不录制 · 不保存 · 不上传摄像头画面", 27, ACCENT, 600)]
for x, big, label, detail1, detail2 in [
    (64, "5 秒", "每轮检测上限", "结束后关闭摄像头", "没看清时会说明无法判断"),
    (402, "30 分钟", "平时的检测间隔", "确认偏近后每 5 分钟复查", "确认恢复后回到半小时"),
    (740, "本机", "画面在内存中分析", "保存设置、校准与数字记录", "摄像头画面不写入磁盘")]:
    p += [rect(x, 282, 296, 244, "white", 22),
          text(x + 24, 345, big, 37, ACCENT, 600), text(x + 24, 389, label, 22, INK, 600),
          text(x + 24, 450, detail1, 17, MUTED), text(x + 24, 481, detail2, 17, MUTED)]
p += [text(64, 585, "只在你授权后使用摄像头", 25, INK, 600),
      text(64, 624, "无需麦克风、屏幕录制、文件或键鼠权限，也不读取其他应用。", 20, MUTED),
      text(64, 672, "不使用摄像头，也可以单独开启工作与休息计时。", 20, ACCENT),
      foot(733, "轻醒 · macOS 14+ · 原生 SwiftUI · 按你的节奏来")]
write("qingxing-04.svg", 1100, 766, "轻醒检测节奏与本机处理说明", p)

p = [text(54, 49, "看一眼就好，摄像头不用一直开。", 28, INK, 600)]
for x, big, detail in [(54, "等待 30 分钟", "摄像头关闭"), (430, "检测最多 5 秒", "仅本轮开启摄像头"), (806, "结束并关闭", "按本轮结果安排下次检测")]:
    p += [rect(x, 90, 240, 100, "white", 18), text(x + 20, 129, big, 22, ACCENT, 600),
          text(x + 20, 165, detail, 16, MUTED)]
for x1, x2 in [(305, 417), (681, 793)]:
    p.append(f'<path d="M{x1} 140 H{x2}" fill="none" stroke="{ACCENT}" stroke-width="2.5" marker-end="url(#arrow)"/>')
for end_x in [292, 780]:
    p.append(f'<path d="M926 191 V220 H{end_x} V254" fill="none" stroke="{ACCENT}" stroke-opacity=".55" stroke-width="2" marker-end="url(#arrow)"/>')
p += [rect(54, 265, 475, 105, "#E7EEF3", 18), text(78, 306, "结果正常 / 已确认恢复", 22, ACCENT, 600),
      text(78, 342, "回到每 30 分钟检测一次", 18, MUTED),
      rect(571, 265, 475, 105, "#F3EBE1", 18), text(595, 306, "确认偏近 → 每 5 分钟复查", 22, "#A46C33", 600),
      text(595, 342, "持续偏近时增强提醒，恢复后回到半小时", 17, MUTED),
      foot(413, "间隔采样：摄像头关闭期间不会即时感知姿势变化；也可以手动立即检测。")]
write("check-rhythm.svg", 1100, 444, "轻醒间隔检测与距离复查流程", p)
write("health-ring.svg", 859, 318, "App 原生健康环：该充电、充能 50%、满血 100%",
      [png("health-ring-states.png", 0, 0, 859, 318)])

cards = [("qingxing-01", "主窗口与提醒"), ("qingxing-02", "健康环与调整奖励"),
         ("qingxing-03", "三种主题"), ("qingxing-04", "检测节奏与隐私"),
         ("check-rhythm", "检测节奏图"), ("health-ring", "健康环阶段图")]
sections = "".join(f'<section id="{key}"><div class="section-head"><h2>{label}</h2><a href="{key}.svg?v=4x" target="_blank">打开 SVG ↗</a></div><img class="promo" src="{key}.svg?v=4x" alt="{label}"></section>' for key, label in cards)
references = "".join(f'<figure><img src="app-renders/{name}?v=4x" alt="{label}"><figcaption>{label} · App 原生视图 · <a href="app-renders/{name}?v=4x" target="_blank">打开高清原图 ↗</a></figcaption></figure>' for name, label in [
    ("full-dashboard.png", "主窗口"), ("distance.png", "距离提醒"), ("head-down.png", "低头提醒"), ("theme-comparison.png", "主题对照")])
html = f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>轻醒 · 高清宣传素材预览</title>
<style>*{{box-sizing:border-box}}body{{margin:0;background:{PAPER};color:{INK};font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}}main{{max-width:1160px;padding:48px 28px;margin:auto}}h1{{font-size:32px;margin:0 0 14px}}p{{line-height:1.8;color:{MUTED}}}nav{{display:flex;flex-wrap:wrap;gap:12px;margin:24px 0 32px}}a{{color:{ACCENT};text-decoration:none}}nav a{{padding:9px 15px;background:white;border:1px solid #DAE3E9;border-radius:20px}}section{{margin:0 0 32px;background:white;border:1px solid #E0E6EB;border-radius:22px;padding:20px;scroll-margin-top:20px}}.section-head{{display:flex;justify-content:space-between;align-items:center;gap:12px}}h2{{font-size:19px;margin:0 0 18px}}.promo{{display:block;width:100%;height:auto;border-radius:16px}}details{{padding:22px;border:1px solid #DAE3E9;border-radius:18px;background:white}}summary{{cursor:pointer;font-weight:600}}.references{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px;margin-top:24px}}figure{{margin:0}}figure img{{display:block;max-width:100%;max-height:650px;width:auto;margin:auto}}figcaption{{text-align:center;padding-top:12px;color:{MUTED};font-size:13px}}footer{{margin-top:28px;font-size:13px;color:{MUTED}}}@media(max-width:650px){{main{{padding:28px 14px}}h1{{font-size:26px}}section{{padding:12px}}.references{{grid-template-columns:1fr}}.section-head{{align-items:baseline}}.section-head a{{font-size:13px}}}}@media print{{nav,details,.section-head a,header p{{display:none}}main{{padding:0}}section{{border:0;break-inside:avoid;break-after:page;padding:0}}}}</style></head><body><main>
<header><h1>轻醒 · QingXing</h1><p>认真工作，也记得坐舒服。<br>六张宣传图统一沿用 App 的主题。界面部分已按 4 倍分辨率从当前 SwiftUI 视图重新渲染，包含示例状态和提醒演示。可点击“打开 SVG”放大查看。</p></header>
<nav>{''.join(f'<a href="#{key}">{label}</a>' for key, label in cards)}</nav>{sections}
<details><summary>展开真实 App 渲染结果，逐项对照</summary><div class="references">{references}</div></details>
<footer>SVG 内已嵌入 4 倍分辨率界面图像，可独立打开。<a href="轻醒-宣传素材.zip">下载宣传素材包</a> · <a href="https://github.com/yoloyyh/QingXing">GitHub</a></footer>
</main></body></html>'''
(OUT / "index.html").write_text(html, encoding="utf-8")
(OUT / "打开宣传页.command").write_text('#!/bin/bash\ncd "$(dirname "$0")"\nopen index.html\n', encoding="utf-8")
(OUT / "打开宣传页.command").chmod(0o755)

with zipfile.ZipFile(OUT / "轻醒-宣传素材.zip", "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(OUT.rglob("*")):
        if path.is_file() and path.suffix != ".zip":
            archive.write(path, path.relative_to(OUT))
print("Generated six standalone SVGs, native UI references, preview HTML and ZIP in Resources/promo")
