#!/usr/bin/env python
"""从系统里的 Noto Sans SC 生成项目专用子集字体。

为什么必须内嵌：ui_font 早期用 SystemFont 指向微软雅黑，换台机器（尤其是
导出的 exe 到了没装中文字体的环境）就会整屏「□□□□」。思源黑体是 SIL OFL
可商用授权，可以直接随包分发。

为什么子集化：全量 NotoSansSC-VF.ttf 17.7MB，一个只显示千把个字的游戏
没必要背这个体积。子集 = 项目用到的字符 + GB2312 全部汉字（6763 个，
覆盖日常用字，之后加中文文案不用重跑这一步）。

重新生成（新增文案后、或换字体文件时）：
    python tools/font/gen_font_subset.py
"""
import glob
import os
import subprocess
import sys

SRC = r"C:/Windows/Fonts/NotoSansSC-VF.ttf"
HERE = os.path.dirname(os.path.abspath(__file__))
CHARS = os.path.join(HERE, "chars.txt")
# 纯英文小写文件名（项目约定），Godot 侧按这个路径加载
OUT = os.path.join(HERE, "..", "..", "fonts", "NotoSansSC-Regular.ttf")

EXTRA = "★☆×·—…→←↑↓「」『』（）【】《》：；、，。！？％℃"


def gb2312_chars() -> set:
    """枚举 GB2312 双字节区，拿到 6763 个常用汉字（含符号）。"""
    out = set()
    for hi in range(0xB0, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                out.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return out


def project_chars() -> set:
    root = os.path.join(HERE, "..", "..")
    chars = {chr(i) for i in range(32, 127)}
    for pat in ("**/*.gd", "**/*.tscn", "**/*.cfg", "**/*.md"):
        for f in glob.glob(os.path.join(root, pat), recursive=True):
            try:
                s = open(f, encoding="utf-8").read()
            except Exception:
                continue
            for ch in s:
                if ord(ch) > 126:
                    chars.add(ch)
    chars |= set(EXTRA)
    return chars


def main() -> None:
    chars = project_chars() | gb2312_chars()
    text = "".join(sorted(chars))
    open(CHARS, "w", encoding="utf-8").write(text)
    print("字符集：%d 个（其中非 ASCII %d 个）" % (
        len(chars), len([c for c in chars if ord(c) > 126])))

    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    # 第一步：把可变字体钉在 wght=400（Regular）。
    # 不钉的话 NotoSansSC-VF 的默认实例是 wght=100(Thin) —— 汉字笔画细到
    # 42px 的标题都几乎看不见（实测标题区亮像素只有同尺寸英文的零头），
    # 而 Godot 侧又拿不到可变轴去调。宁可多一步，也不要一个看不见的字体。
    static = os.path.join(HERE, "_static_wght400.ttf")
    subprocess.run([
        sys.executable, "-m", "fontTools.varLib.instancer", SRC,
        "wght=400", "-o", static,
    ], check=True)

    subprocess.run([
        sys.executable, "-m", "fontTools.subset", static,
        "--text-file=" + CHARS,
        "--output-file=" + os.path.abspath(OUT),
        "--layout-features=",          # 游戏 UI 用不到复杂排版特性
        "--no-hinting",                # 像素风 + 大字号，hinting 只会让边缘糊
        "--drop-tables+=GSUB,GPOS,vmtx,vhea,VVAR",
        "--name-IDs=0,1,2,3,4,5,6",
        "--notdef-outline",
        "--recommended-glyphs",
    ], check=True)
    print("输出：%s（%.1f KB）" % (
        os.path.abspath(OUT), os.path.getsize(OUT) / 1024.0))


if __name__ == "__main__":
    main()
