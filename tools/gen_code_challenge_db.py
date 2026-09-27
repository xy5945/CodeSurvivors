# -*- coding: utf-8 -*-
"""生成 core/code_challenge_db.gd —— 升级打码的 C++ 题库。

设计约定（改动前先读）：
  1. 只存 std（标准）档的片段。easy/hard 在运行时派生，避免同一段代码写三遍：
       easy = 去掉纯括号行后「最长的那一行」（核心语句，适合低龄/入门）
       hard = Lv6 及以上额外包一层 main 结构（完整程序，适合要长练习的班）
  2. 代码里不放中文。等宽字体只子集了 ASCII，中文会变豆腐块，
     中文讲解走 tip 字段（在代码块外面显示）。
  3. 缩进统一 4 空格。缩进是 C++ 的教学点，但校验时会宽容（见 CodeChallenge.normalize）。
"""
import io

# 主题 -> {等级: (代码行列表, 一句话讲解)}
DB = {
    "whip": {  # 分支长鞭 —— if / else 分支
        1: (["if"], "分支的开头：条件成立才执行"),
        2: (["int n = 0;"], "定义一个整数变量 n"),
        3: (["if (n > 0) n++;"], "条件成立时 n 加一"),
        4: (["if (n > 0) { n--; }"], "大括号包住要做的事"),
        5: (["if (n > 10) {", "    n = 10;", "}"], "超过上限就压回上限"),
        6: (["if (n % 2 == 0) {", "    cout << \"even\";", "} else {", "    cout << \"odd\";", "}"],
            "用 % 取余判断奇偶"),
        7: (["int n = 7;", "if (n % 2 == 0) {", "    cout << \"even\";", "} else {",
             "    cout << \"odd\";", "}"], "二选一：if 走一条，else 走另一条"),
        8: (["int n = 0;", "for (int i = 1; i <= 10; i++) {", "    if (i % 2 == 0) {",
             "        n = n + i;", "    }", "}", "cout << n;"], "循环里套分支：只累加偶数"),
    },
    "orbit": {  # 循环护盾 —— for 循环
        1: (["for"], "循环的开头：重复做同一件事"),
        2: (["int i = 0;"], "循环变量 i 从 0 开始"),
        3: (["i++;"], "i 自己加一，等价于 i = i + 1"),
        4: (["for (int i = 0; i < 10; i++)"], "三个部分：起点、条件、步进"),
        5: (["for (int i = 0; i < 10; i++) {", "    cout << i;", "}"], "把 0 到 9 依次打印出来"),
        6: (["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "}"],
            "累加：把每次的 i 加进 s"),
        7: (["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "}",
             "cout << s;"], "算完再输出 1 到 10 的和"),
        8: (["int s = 0;", "for (int i = 0; i <= 100; i++) {", "    if (i % 3 == 0) {",
             "        s = s + i;", "    }", "}", "cout << s << endl;"], "0 到 100 里能被 3 整除的数之和"),
    },
    "broadcast": {  # 广播冲击波 —— 输出
        1: (["cout"], "输出的开头：把内容送到屏幕"),
        2: (["int x = 1;"], "先准备一个要输出的数"),
        3: (["cout << x;"], "两个小于号表示「流向」屏幕"),
        4: (["cout << x << endl;"], "endl 表示换行"),
        5: (["cout << \"hi\";", "cout << endl;"], "字符串要加双引号"),
        6: (["int x = 5;", "cout << \"x = \";", "cout << x << endl;"], "文字和数字可以拼着输出"),
        7: (["for (int i = 0; i < 3; i++) {", "    cout << \"wave \" << i << endl;", "}"],
            "循环里输出，一次发三波"),
        8: (["int n = 3;", "for (int i = 1; i <= n; i++) {", "    cout << \"wave \" << i << endl;",
             "}", "cout << \"done\" << endl;"], "输出结束后再报一句完成"),
    },
    "judgment": {  # 随机数审判 —— rand
        1: (["rand"], "随机数函数：每次结果都可能不同"),
        2: (["int r = 0;"], "准备一个变量装随机数"),
        3: (["r = rand();"], "取一个随机数存进 r"),
        4: (["int r = rand() % 6;"], "% 6 把范围压到 0 到 5，像掷骰子"),
        5: (["int r = rand() % 6;", "cout << r;"], "掷一次骰子并输出结果"),
        6: (["int r = rand() % 100;", "if (r < 50) {", "    cout << \"low\";", "}"],
            "随机结果参与判断"),
        7: (["int r = rand() % 100;", "if (r < 50) {", "    cout << \"low\";", "} else {",
             "    cout << \"high\";", "}"], "随机 + 二选一"),
        8: (["int n = 0;", "for (int i = 0; i < 10; i++) {", "    if (rand() % 2 == 0) {",
             "        n++;", "    }", "}", "cout << n << endl;"], "扔十次硬币，数正面朝上的次数"),
    },
    "blade": {  # 递归飞刃 —— 函数
        1: (["int"], "函数的返回值类型"),
        2: (["return 0;"], "return 把结果送回去"),
        3: (["int f(int n)"], "函数头：名字、参数、返回类型"),
        4: (["int f(int n) { return n; }"], "最简单的函数：原样返回"),
        5: (["int f(int n) {", "    return n * 2;", "}"], "函数里做一次运算再返回"),
        6: (["int add(int a, int b) {", "    return a + b;", "}"], "两个参数的函数"),
        7: (["int f(int n) {", "    if (n <= 1) {", "        return 1;", "    }",
             "    return n * f(n - 1);", "}"], "自己调用自己，这就是递归"),
        8: (["int sum(int n) {", "    int s = 0;", "    for (int i = 1; i <= n; i++) {",
             "        s = s + i;", "    }", "    return s;", "}"], "用函数算出 1 到 n 的和"),
    },
    "pointer": {  # 指针追踪 —— 指针
        1: (["int* p;"], "星号表示这是一个指针变量"),
        2: (["int n = 5;"], "先有一个普通的整数"),
        3: (["int* p = &n;"], "& 取地址，让 p 指向 n"),
        4: (["cout << *p;"], "*p 表示「p 指向的那个值」"),
        5: (["int n = 5;", "int* p = &n;", "cout << *p;"], "指过去再读出来"),
        6: (["int n = 5;", "int* p = &n;", "*p = *p + 1;", "cout << n;"], "通过指针改值，n 也跟着变"),
        7: (["void up(int* p) {", "    *p = *p + 1;", "}"], "把指针传进函数才能改到外面"),
        8: (["int n = 0;", "int* p = &n;", "for (int i = 0; i < 5; i++) {", "    *p = *p + i;",
             "}", "cout << n << endl;"], "循环里通过指针累加"),
    },
    "volley": {  # 多线程齐射 —— 数组 + 循环
        1: (["int a[5];"], "数组：一排编号的格子"),
        2: (["a[0] = 1;"], "下标从 0 开始，不是 1"),
        3: (["cout << a[0];"], "按下标取出来"),
        4: (["for (int i = 0; i < 5; i++)"], "用循环走遍每个下标"),
        5: (["int a[5] = {1, 2, 3, 4, 5};", "cout << a[0];"], "定义时直接给初值"),
        6: (["int a[5] = {1, 2, 3, 4, 5};", "for (int i = 0; i < 5; i++) {", "    cout << a[i];",
             "}"], "遍历数组全部输出"),
        7: (["int a[5] = {1, 2, 3, 4, 5};", "int s = 0;", "for (int i = 0; i < 5; i++) {",
             "    s = s + a[i];", "}", "cout << s;"], "把数组里的数全加起来"),
        8: (["int a[5] = {2, 4, 6, 8, 10};", "int s = 0;", "for (int i = 0; i < 5; i++) {",
             "    if (a[i] % 4 == 0) {", "        s = s + a[i];", "    }", "}",
             "cout << s << endl;"], "只累加符合条件的元素"),
    },
    "gc": {  # 垃圾回收 —— 数组与内存
        1: (["int n = 0;"], "先准备一个计数变量"),
        2: (["int a[10];"], "申请十个整数的空间"),
        3: (["a[i] = 0;"], "按下标写入"),
        4: (["for (int i = 0; i < 10; i++)"], "循环覆盖全部下标"),
        5: (["int a[10];", "for (int i = 0; i < 10; i++) {", "    a[i] = 0;", "}"],
            "把数组全部清零"),
        6: (["int a[10];", "a[0] = 1;", "a[1] = 1;", "for (int i = 2; i < 10; i++) {",
             "    a[i] = a[i - 1] + a[i - 2];", "}"], "后面的数由前面两个相加得到"),
        7: (["int a[10];", "a[0] = 1;", "a[1] = 1;", "for (int i = 2; i < 10; i++) {",
             "    a[i] = a[i - 1] + a[i - 2];", "}", "cout << a[9];"], "算出最后一个数并输出"),
        8: (["int a[10] = {0};", "int n = 0;", "for (int i = 0; i < 10; i++) {", "    a[i] = i * i;",
             "    n = n + a[i];", "}", "cout << n << endl;"], "存平方数，同时累加"),
    },
    "buffer": {  # 缓冲区溢出 —— 边界
        1: (["int i = 0;"], "下标从 0 开始"),
        2: (["i < 10;"], "循环条件：不能等于 10"),
        3: (["if (i < 10)"], "先判断再取，防止越界"),
        4: (["while (i < 10)"], "条件成立就一直做"),
        5: (["int i = 0;", "while (i < 10) {", "    i++;", "}"], "while 版本的计数循环"),
        6: (["int a[10];", "for (int i = 0; i < 10; i++) {", "    a[i] = i;", "}"],
            "写满十格，一格不多"),
        7: (["int a[10];", "int n = 0;", "for (int i = 0; i < 10; i++) {", "    a[i] = i * 2;",
             "    n++;", "}", "cout << n;"], "边写边数，最后输出个数"),
        8: (["int a[10];", "int s = 0;", "for (int i = 0; i < 10; i++) {", "    a[i] = i + 1;",
             "    if (a[i] > 5) {", "        s = s + a[i];", "    }", "}",
             "cout << s << endl;"], "越界是 bug，条件要写死"),
    },
    "breakpoint": {  # 断点调试 —— 输出中间过程
        1: (["int k = 0;"], "准备一个观察用的变量"),
        2: (["k = k + 1;"], "手动往前推一步"),
        3: (["cout << k;"], "把当前值打印出来看"),
        4: (["cout << \"step \" << k;"], "输出时带上说明文字"),
        5: (["cout << \"step 1\";", "cout << endl;"], "一步一步打点"),
        6: (["for (int i = 0; i < 3; i++) {", "    cout << \"step \" << i << endl;", "}"],
            "每轮循环都留一个记号"),
        7: (["int s = 0;", "for (int i = 1; i <= 5; i++) {", "    s = s + i;",
             "    cout << s << endl;", "}"], "每加一次就打印，看过程"),
        8: (["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;",
             "    cout << i << \" : \" << s << endl;", "}", "cout << \"sum = \" << s << endl;"],
            "把每一步和最后结果都打出来"),
    },
    "forever": {  # 永真力场 —— while
        1: (["while"], "条件成立就一直重复"),
        2: (["int n = 0;"], "准备一个会被改变的变量"),
        3: (["while (n < 5)"], "条件写在括号里"),
        4: (["while (n < 5) { n++; }"], "别忘让 n 变大，否则停不下来"),
        5: (["while (n < 5) {", "    n++;", "}"], "循环体必须能推进条件"),
        6: (["int n = 0;", "while (n < 5) {", "    n = n + 2;", "}", "cout << n;"],
            "步长可以是 2"),
        7: (["int n = 0;", "while (n < 100) {", "    n = n + 7;", "}", "cout << n << endl;"],
            "一直加到超过 100"),
        8: (["int n = 0;", "int c = 0;", "while (n < 100) {", "    n = n + 3;", "    c++;", "}",
             "cout << c << endl;"], "顺便数一共加了多少次"),
    },
    "rebuild": {  # 全量重编译 —— 完整程序
        1: (["int main()"], "程序从 main 开始执行"),
        2: (["return 0;"], "返回 0 表示正常结束"),
        3: (["int x = 1;"], "在 main 里定义变量"),
        4: (["cout << x << endl;"], "输出后换行"),
        5: (["int a = 3;", "int b = 4;", "cout << a + b;"], "先算再输出"),
        6: (["int a = 3;", "int b = 4;", "int c = a * b;", "cout << c << endl;"], "中间结果存进新变量"),
        7: (["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "}",
             "cout << s << endl;"], "完整的累加程序"),
        8: (["int s = 0;", "for (int i = 0; i <= 100; i++) {", "    s = s + i;", "}",
             "cout << s << endl;"], "求 0 到 100 所有整数的和"),
    },
    "general": {  # 被动 / 进化 / 兜底
        1: (["int"], "整数类型"),
        2: (["int n = 0;"], "定义变量并给初值"),
        3: (["n = n + 1;"], "自增的写法"),
        4: (["cout << n << endl;"], "输出并换行"),
        5: (["int n = 0;", "n = n + 1;", "cout << n;"], "改完立刻看结果"),
        6: (["int s = 0;", "for (int i = 0; i < 5; i++) {", "    s = s + i;", "}"], "小循环做累加"),
        7: (["int s = 0;", "for (int i = 0; i < 5; i++) {", "    s = s + i;", "}",
             "cout << s << endl;"], "累加后输出"),
        8: (["int s = 0;", "for (int i = 0; i <= 100; i++) {", "    s = s + i;", "}",
             "cout << s << endl;"], "求 0 到 100 所有整数的和"),
    },
}


def gd_str(s: str) -> str:
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


lines = []
lines.append('class_name CodeChallengeDB')
lines.append('extends RefCounted')
lines.append('##')
lines.append('## 升级打码的 C++ 题库（纯数据，由 tools 下的生成脚本产出，不要手改）。')
lines.append('##')
lines.append('## 只存「标准档」片段，轻松档/严格档由 CodeChallenge 在运行时派生：')
lines.append('##   轻松 = 去掉纯括号行后最长的那一行')
lines.append('##   严格 = Lv6 及以上再包一层 main 结构')
lines.append('##')
lines.append('## 代码一律 ASCII（等宽字体只子集了 ASCII），中文讲解放 TIPS。')
lines.append('## 缩进统一 4 空格。')
lines.append('')
lines.append('')
lines.append('## 主题 -> 等级 -> 代码行数组')
lines.append('const FRAG := {')

for theme in DB:
    lines.append('\t"%s": {' % theme)
    for lv in range(1, 9):
        code, _tip = DB[theme][lv]
        items = ", ".join(gd_str(c) for c in code)
        lines.append('\t\t%d: [%s],' % (lv, items))
    lines.append('\t},')
lines.append('}')
lines.append('')
lines.append('')
lines.append('## 主题 -> 等级 -> 一句话讲解（显示在代码块外，用中文字体）')
lines.append('const TIPS := {')
for theme in DB:
    lines.append('\t"%s": {' % theme)
    for lv in range(1, 9):
        _code, tip = DB[theme][lv]
        lines.append('\t\t%d: %s,' % (lv, gd_str(tip)))
    lines.append('\t},')
lines.append('}')
lines.append('')
lines.append('')
lines.append('## 升级项 id -> 主题名。武器用自己的 id；被动、进化、未登记的都走 general。')
lines.append('const THEME_OF := {')
for theme in DB:
    if theme == "general":
        continue
    lines.append('\t"%s": "%s",' % (theme, theme))
lines.append('}')
lines.append('')
lines.append('')
lines.append('## 取某主题某等级的代码行（没有就退回 general 的同级，再没有就空数组）')
lines.append('static func frag(theme: String, level: int) -> Array:')
lines.append('\tvar by_lv: Dictionary = FRAG.get(theme, {})')
lines.append('\tif not by_lv.has(level):')
lines.append('\t\tby_lv = FRAG.get("general", {})')
lines.append('\tif not by_lv.has(level):')
lines.append('\t\treturn []')
lines.append('\treturn (by_lv[level] as Array).duplicate()')
lines.append('')
lines.append('')
lines.append('## 取讲解文案')
lines.append('static func tip(theme: String, level: int) -> String:')
lines.append('\tvar by_lv: Dictionary = TIPS.get(theme, {})')
lines.append('\tvar s := ""')
lines.append('\tif by_lv.has(level):')
lines.append('\t\ts = str(by_lv[level])')
lines.append('\tif s == "":')
lines.append('\t\tvar g: Dictionary = TIPS.get("general", {})')
lines.append('\t\tif g.has(level):')
lines.append('\t\t\ts = str(g[level])')
lines.append('\treturn s')
lines.append('')
lines.append('')
lines.append('## 升级项 id 对应的主题')
lines.append('static func theme_of(upgrade_id: String) -> String:')
lines.append('\tif THEME_OF.has(upgrade_id):')
lines.append('\t\treturn str(THEME_OF[upgrade_id])')
lines.append('\treturn "general"')
lines.append('')

out = "\n".join(lines)
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'core', 'code_challenge_db.gd')
io.open(p, 'w', encoding='utf-8', newline='\n').write(out)
print('已写入', p)
print('主题数', len(DB), '· 题目数', sum(len(v) for v in DB.values()), '· 文件行数', out.count('\n'))
