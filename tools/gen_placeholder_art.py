##
## 生成占位美术资源。
##
## 为什么要程序化生成而不是手画：第一批素材的作用是"跑通贴图链路"，
## 之后会被正式美术整批替换掉。手画 6 张再全部推翻，成本比写这个脚本高。
##
## 运行：python tools/gen_placeholder_art.py（项目根执行）
## 产物：assets/sprites/*.png
##
## 铁律：全部输出白色不透明剪影。颜色由 instance_color 乘法染色，
## 彩色贴图会让受击闪白失效。
##

import os
from PIL import Image, ImageDraw

SIZE = 16
WHITE = (255, 255, 255, 255)
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sprites")


def new_canvas(w=SIZE, h=SIZE):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def flatten(img):
    """消除抗锯齿：任何非全透明的像素一律拍成纯白。
    PIL 的 line/ellipse 会产生半透明边缘，在 Nearest 采样下会变成脏边。"""
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y][3] > 0:
                px[x, y] = WHITE
    return img


def save(img, name):
    path = os.path.join(OUT_DIR, name)
    img.save(path)
    print("  %-22s %dx%d" % (name, img.width, img.height))


##
## 小 Bug：俯视的小虫子，4 帧爬行循环。
##
## 腿部用"行波"而不是简单的左右交替 —— 后者 4 个相位里 0 和 2 会完全一样，
## 实际只有 2 帧。行波让四条腿依次抬起，4 帧各不相同，看得出方向感。
##
LEG_WAVE = [
    [1, -1, 1],
    [1, 1, -1],
    [-1, 1, -1],
    [-1, -1, 1],
]
BOB = [0, 0, 1, 1]      # 身体随步态轻微起伏


def bug_frame(phase: int) -> Image.Image:
    img = new_canvas()
    d = ImageDraw.Draw(img)
    bob = BOB[phase]
    wave = LEG_WAVE[phase]

    # 腿：三条，从身体两侧向外下方伸出，末端 y 随步态偏移
    for i in range(3):
        by = 6 + i * 2 + bob
        ey = by + wave[i]
        d.line([(5, by), (2, ey)], fill=WHITE)
        d.line([(10, by), (13, ey)], fill=WHITE)

    # 身体与头
    d.ellipse([5, 4 + bob, 10, 11 + bob], fill=WHITE)
    d.ellipse([6, 1 + bob, 9, 5 + bob], fill=WHITE)

    # 触角
    d.line([(7, 2 + bob), (4, 0 + bob)], fill=WHITE)
    d.line([(8, 2 + bob), (11, 0 + bob)], fill=WHITE)

    return flatten(img)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("生成占位美术 → %s" % OUT_DIR)

    for i in range(4):
        save(bug_frame(i), "enemy_bug_%d.png" % i)

    print("")
    print("小 Bug 共 4 帧，腿部为行波步态（0/2 帧与 1/3 帧均不相同）。")
    print("全部为白色剪影 —— 受击闪白靠 instance_color 乘法染色，图上不能带颜色。")


if __name__ == "__main__":
    main()
