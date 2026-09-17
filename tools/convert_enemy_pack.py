# -*- coding: utf-8 -*-
"""
敌人分化素材批量转换：GIF / 横条精灵表 / PNG 序列 -> 统一规格横条表（彩色 + 白剪影双输出）。

用法:
    python tools/convert_enemy_pack.py

输出:
    assets/sprites/enemies/<名字>.png        彩色表（主渲染，保留素材原色）
    assets/sprites/enemies_flash/<名字>.png  白剪影表（受击闪白层）
    控制台报告: 帧数 / 单元格尺寸 / 身体主色

处理链:
    1. 抽帧（GIF 逐帧、横条切块、PNG 序列合并、单帧直取）
    2. 背景抠除（纯蓝/纯黑软抠：距背景色越远 alpha 越高，兼顾抗锯齿边缘）
    3. 裁到内容 bbox，逐帧按内容高度归一化（不同敌人的目标显示尺寸不同）
    4. 白剪影（out = 亮度/主色亮度，保留暗部细节如眼睛）
    5. 统一单元格尺寸（取该敌人所有帧的最大宽高），居中，横条排列
"""
import os
import sys
from collections import Counter

from PIL import Image, ImageSequence

SRC_DIR = [
    r"C:\Users\xy_59\Desktop",
    r"C:\Users\xy_59\Desktop\死亡使者",
    r"C:\Users\xy_59\Desktop\斧头恶魔",
    r"C:\Users\xy_59\Downloads\像素风素材\游戏机\MV Icons Consoles\Individual Icons",
]
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "assets", "sprites", "enemies")
# 白剪影表（受击闪白层专用），与彩色表同规格同文件名
OUT_DIR_FLASH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                             "assets", "sprites", "enemies_flash")

# 名字 -> (来源文件, 抽帧方式, 目标内容高度px, 连通域过滤, 裁剪模式, 翻转, 限帧数)
# 连通域过滤: 0=不过滤; >0 时只保留面积 >= 该比例*最大连通域的成分（去孤立噪点）。
# 裁剪模式: union=全帧合并 bbox 后统一裁（保持帧间对齐，走路循环用）;
#           per=逐帧各自裁剪居中（飞行特效，精灵在画布上位置漂移的用）。
# 翻转: True=水平镜像。渲染器按"素材统一朝右"决定翻转时机（enemy_renderer.sync），
#       源素材朝左的必须在这里翻过来，否则敌人永远背对玩家走（用户实测踩过 3 次）。
# 限帧数: 0=全部; >0 只取前 N 帧（24 帧的大表抽前几帧做走路循环用）。
SPECS = [
    ("boss_compiler", r"骷髅王.gif",                    "gif",  44, 0,    "union", False, 0),  # 编译器反噬(最终Boss)
    ("virus",         r"死亡使者\Bringer-of-Death_Walk_#.png", "seq", 18, 0, "union", True,  0),  # 病毒总攻(8帧,源图朝左)
    ("oom",           r"骑士.png",                      "grid", 20, 0,    "union", False, 0),  # 内存不足(2x4网格8帧)
    ("bluescreen",    r"斧头恶魔\run_#.png",            "seq",  16, 0,    "union", False, 0),  # 蓝屏(6帧)
    ("elite_skull",   r"飞行骷髅.gif",                  "gif",  28, 0,    "union", False, 0),  # 精英怪(24帧, 带卫星弹)
    ("trojan",        r"console_29.png",                "png",  14, 0,    "union", False, 0),  # 木马
    ("mojibake",      r"飞行透露.gif",                  "gif",  14, 0.05, "per",   False, 0),  # 乱码(3帧, 精灵漂移)
    ("popup",         r"bee.gif",                       "gif",  14, 0,    "union", True,  0),  # 弹窗(8帧,源图朝左)
    ("junk_file",     r"骷髅兵.gif",                    "gif",  16, 0,    "union", False, 0),  # 垃圾文件(6帧)
    # 死循环：换成项目最早期的小恐龙素材（DinoSprites - vita，帧 0-5 是走路循环）。
    # 源图 24 帧里 14 帧朝左走路 + 攻击/受击/剪影等杂帧，只取前 6 帧最干净。
    ("infinite_loop", r"DinoSprites - vita.png",        "strip", 16, 0,   "union", True,  6),  # 死循环(小恐龙6帧,源图朝左)
    ("error_red",     r"小怪.png",                      "strip", 14, 0,   "union", True,  0),  # 报错红字(24帧32x32,源图朝左)
]


def find_file(name: str, kind: str) -> str:
    probe = name.replace("#", "1") if kind == "seq" else name
    for d in SRC_DIR:
        p = os.path.join(d, probe)
        if os.path.exists(p):
            return os.path.join(d, name)
    raise FileNotFoundError(name)


def extract_frames(path: str, kind: str, max_frames: int = 0) -> list:
    if kind == "seq":
        frames = []
        i = 1
        while True:
            p = path.replace("#", str(i))
            if not os.path.exists(p):
                break
            frames.append(Image.open(p).convert("RGBA"))
            i += 1
        return frames[:max_frames] if max_frames else frames
    im = Image.open(path)
    if kind == "gif":
        frames = []
        for i in range(im.n_frames):
            im.seek(i)
            frames.append(im.convert("RGBA"))
        return frames[:max_frames] if max_frames else frames
    if kind == "grid":
        im = im.convert("RGBA")
        w, h = im.size
        # 2 列 x 4 行，行优先；每格尺寸 = 图宽/2 x 图高/4
        cw, chh = w // 2, h // 4
        out = []
        for r in range(4):
            for c in range(2):
                out.append(im.crop((c * cw, r * chh, (c + 1) * cw, (r + 1) * chh)))
        return out[:max_frames] if max_frames else out
    if kind == "strip":
        im = im.convert("RGBA")
        fw = im.size[1]  # 方形帧: 高即帧宽
        n = im.size[0] // fw
        if max_frames:
            n = min(n, max_frames)
        return [im.crop((i * fw, 0, (i + 1) * fw, im.size[1])) for i in range(n)]
    # png 单帧
    return [Image.open(path).convert("RGBA")]


def key_background(frame: Image.Image, bg, t0: float, t1: float) -> Image.Image:
    """软抠背景：dist<=t0 全透明，dist>=t1 不动，中间线性过渡（吃掉抗锯齿边）。"""
    out = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    src, dst = frame.load(), out.load()
    w, h = frame.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = src[x, y]
            if a == 0:
                continue
            dist = ((r - bg[0]) ** 2 + (g - bg[1]) ** 2 + (b - bg[2]) ** 2) ** 0.5
            if dist <= t0:
                continue
            if dist < t1:
                a = int(a * (dist - t0) / (t1 - t0))
            dst[x, y] = (r, g, b, a)
    return out


def keep_main_components(frame: Image.Image, frac: float) -> Image.Image:
    """8 连通域标注，丢掉面积 < frac*最大面积的成分（孤立噪点）。"""
    w, h = frame.size
    src = frame.load()
    seen = bytearray(w * h)
    comps = []  # (面积, 像素列表)
    for start in range(w * h):
        if seen[start] or src[start % w, start // w][3] == 0:
            continue
        stack = [start]
        seen[start] = 1
        pix = []
        while stack:
            idx = stack.pop()
            pix.append(idx)
            cx, cy = idx % w, idx // w
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        j = ny * w + nx
                        if not seen[j] and src[nx, ny][3] != 0:
                            seen[j] = 1
                            stack.append(j)
        comps.append(pix)
    if not comps:
        return frame
    mx = max(len(c) for c in comps)
    out = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    dst = out.load()
    for c in comps:
        if len(c) < frac * mx:
            continue
        for idx in c:
            dst[idx % w, idx // w] = src[idx % w, idx // w]
    return out


def union_bbox(frames: list):
    bx = None
    for f in frames:
        b = f.getbbox()
        if b is None:
            continue
        bx = b if bx is None else (
            min(bx[0], b[0]), min(bx[1], b[1]), max(bx[2], b[2]), max(bx[3], b[3]))
    return bx


def trim_and_scale(frame: Image.Image, box, target_h: int) -> Image.Image:
    c = frame.crop(box)
    w, h = c.size
    s = target_h / h
    nw, nh = max(1, round(w * s)), target_h
    return c.resize((nw, nh), Image.LANCZOS)


def sample_body_color(frames: list):
    cnt = Counter()
    for f in frames:
        for r, g, b, a in f.getdata():
            if a > 200:
                cnt[(r, g, b)] += 1
    if not cnt:
        return (255, 255, 255)
    lums = sorted(0.299 * r + 0.587 * g + 0.114 * b
                  for (r, g, b), c in cnt.items() for _ in range(c))
    med = lums[len(lums) // 2]
    body, _ = max(((col, c) for col, c in cnt.items()
                   if 0.299 * col[0] + 0.587 * col[1] + 0.114 * col[2] > med),
                  key=lambda kv: kv[1])
    return body


def to_silhouette(frame: Image.Image, body_lum: float) -> Image.Image:
    out = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    src, dst = frame.load(), out.load()
    w, h = frame.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = src[x, y]
            if a == 0:
                continue
            v = min(1.0, (0.299 * r + 0.587 * g + 0.114 * b) / body_lum)
            gray = round(v * 255)
            dst[x, y] = (gray, gray, gray, a)
    return out


def ascii_preview(frame: Image.Image, cols: int = 18) -> str:
    """帧 0 的 ASCII 预览，肉眼确认形状没抠坏。"""
    im = frame.resize((cols, max(1, int(cols * frame.size[1] / frame.size[0] * 0.5))), Image.LANCZOS)
    px = im.load()
    rows = []
    for y in range(im.size[1]):
        row = ""
        for x in range(im.size[0]):
            a = px[x, y][3]
            lum = 0.299 * px[x, y][0] + 0.587 * px[x, y][1] + 0.114 * px[x, y][2]
            row += " " if a < 60 else ("#" if lum > 170 else ("+" if lum > 90 else "."))
        rows.append(row)
    return "\n".join(rows)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    report = []
    for name, src, kind, target_h, comp_frac, trim_mode, flip, max_frames in SPECS:
        path = find_file(src, kind)
        frames = extract_frames(path, kind, max_frames)

        # 背景色：取首帧角落；透明则无需抠；蓝色系软抠阈带宽些，黑色系窄些防吃暗描边
        c0 = frames[0].getpixel((0, 0))
        if c0[3] < 20:
            bg, t0, t1 = None, 0, 0
        elif c0[2] > c0[0]:  # 蓝/青背景
            bg, t0, t1 = c0[:3], 34, 96
        else:                # 黑背景
            bg, t0, t1 = c0[:3], 30, 72
        if bg is not None:
            frames = [key_background(f, bg, t0, t1) for f in frames]
        if comp_frac > 0:
            frames = [keep_main_components(f, comp_frac) for f in frames]
        if flip:
            frames = [f.transpose(Image.FLIP_LEFT_RIGHT) for f in frames]

        if trim_mode == "per":
            # 飞行特效：精灵在画布上漂移，逐帧各自裁剪（帧间对齐交给居中）
            frames = [trim_and_scale(f, f.getbbox(), target_h) for f in frames]
        else:
            box = union_bbox(frames)
            if box is None:
                print("!! %s 没有内容，跳过" % name)
                continue
            frames = [trim_and_scale(f, box, target_h) for f in frames]

        body = sample_body_color(frames)
        body_lum = 0.299 * body[0] + 0.587 * body[1] + 0.114 * body[2]

        # 双输出：彩色表（主渲染，保留素材原色）+ 白剪影表（受击闪白层）。
        # 彩色版不能靠 instance_color 染色/闪白（乘法混合只能变暗），
        # 闪白由渲染器把受击实例改画到白剪影层实现 —— 两表共用同一几何。
        frames_color = frames
        frames_white = [to_silhouette(f, body_lum) for f in frames]

        # 统一单元格：取所有帧最大宽高（偶数），内容居中
        cw = max(f.size[0] for f in frames_color)
        ch = max(f.size[1] for f in frames_color)
        cw += cw % 2
        ch += ch % 2

        for out_dir, fl in ((OUT_DIR, frames_color), (OUT_DIR_FLASH, frames_white)):
            os.makedirs(out_dir, exist_ok=True)
            sheet = Image.new("RGBA", (cw * len(fl), ch), (0, 0, 0, 0))
            for i, f in enumerate(fl):
                sheet.paste(f, (i * cw + (cw - f.size[0]) // 2, (ch - f.size[1]) // 2), f)
            sheet.save(os.path.join(out_dir, name + ".png"))

        n = len(frames_color)
        print("== %s  %d帧  单元格%dx%d  主色RGB%s" % (name, n, cw, ch, str(body)))
        print(ascii_preview(frames_color[0]))
        report.append((name, n, cw, ch, body))

    print("\n===== 汇总（主色仅作参考，彩色渲染不再依赖染色） =====")
    for name, n, cw, ch, body in report:
        print("%-14s %2d帧 cell=%dx%d  BASE_COLOR=Color(%.2f, %.2f, %.2f)" % (
            name, n, cw, ch, body[0] / 255, body[1] / 255, body[2] / 255))


if __name__ == "__main__":
    main()
