# -*- coding: utf-8 -*-
"""
把外部 4 帧横排精灵图转换为项目可用的白色剪影贴图。

用法:
    python tools/convert_sprite.py <输入png> <输出前缀> [帧数=4]

为什么转白色剪影而不是保留原色：
    受击闪白靠 MultiMesh 的 instance_color 实现，它是乘法混合 ——
    彩色贴图乘任何颜色只会变暗，闪白直接失效。
    所以贴图统一转成灰度剪影（亮部→白、暗部→黑），颜色由渲染器染。
    归一化系数取"身体主色亮度"，这样渲染器把 BASE_COLOR 设成原始主色，
    染出来的效果和原图几乎一致。
"""
import sys
import hashlib

from PIL import Image


def main() -> None:
    src, dst_prefix = sys.argv[1], sys.argv[2]
    frames = int(sys.argv[3]) if len(sys.argv) > 3 else 4

    im = Image.open(src).convert("RGBA")
    w, h = im.size
    assert w % frames == 0, "宽度 %d 不能整除 %d 帧" % (w, frames)
    fw = w // frames

    # 1. 确定身体主色：取"亮度高于全体中位数"的颜色里出现最多的。
    #    不能直接取出现最多的 —— 描边色像素数往往最多但很暗（Dino 素材
    #    的暗橄榄描边就是），拿它归一化会把整个身体钳制成白团，丢掉内部细节。
    from collections import Counter
    cnt = Counter()
    for f in range(frames):
        fr = im.crop((f * fw, 0, (f + 1) * fw, h))
        for r, g, b, a in fr.getdata():
            if a > 200:
                cnt[(r, g, b)] += 1
    all_lums = sorted(
        0.299 * r + 0.587 * g + 0.114 * b
        for (r, g, b), c in cnt.items() for _ in range(c)
    )
    median_lum = all_lums[len(all_lums) // 2]
    body, _ = max(
        ((col, c) for col, c in cnt.items()
         if 0.299 * col[0] + 0.587 * col[1] + 0.114 * col[2] > median_lum),
        key=lambda kv: kv[1],
    )
    body_lum = 0.299 * body[0] + 0.587 * body[1] + 0.114 * body[2]
    print("身体主色 RGB%s  亮度 %.1f（中位亮度 %.1f）" % (str(body), body_lum, median_lum))

    # 2. 逐帧转白色剪影：out = luminance / body_luminance，钳制到 [0,1]
    for f in range(frames):
        fr = im.crop((f * fw, 0, (f + 1) * fw, h)).load()
        out = Image.new("RGBA", (fw, h), (0, 0, 0, 0))
        op = out.load()
        for y in range(h):
            for x in range(fw):
                r, g, b, a = fr[x, y]
                if a == 0:
                    continue
                lum = 0.299 * r + 0.587 * g + 0.114 * b
                v = min(1.0, lum / body_lum)
                gray = round(v * 255)
                op[x, y] = (gray, gray, gray, a)
        path = dst_prefix + "_%d.png" % f
        out.save(path)
        print("已保存 %s  md5=%s" % (path, hashlib.md5(out.tobytes()).hexdigest()[:8]))


if __name__ == "__main__":
    main()
