# -*- coding: utf-8 -*-
"""生成 core/code_challenge_db.gd —— 升级打码的 C++ 题库。

设计约定（改动前先读）：
  1. 只存 std（标准）档的片段。easy/hard 在运行时派生，避免同一段代码写三遍：
       easy = 去掉纯括号行后「最长的那一行」（核心语句，适合低龄/入门）
       hard = Lv6 及以上额外包一层 main 结构（完整程序，适合要长练习的班）
  2. 代码里不放中文。等宽字体只子集了 ASCII，中文会变豆腐块，
     中文讲解走 tip 字段（在代码块外面显示）。
  3. 缩进统一 4 空格。缩进是 C++ 的教学点，但校验时会宽容（见 CodeChallenge.normalize）。
  4. Lv5 起每级有多道「变体」，出题时随机抽一道：同一个升级项反复升到满级
     不会永远打同一段代码。变体之间难度和长度要接近，别差出一截。
     题目来源以 GESP C++ 1-4 级和 NOIP 入门题为主（求和、阶乘、素数、闰年、
     水仙花数、鸡兔同笼、辗转相除、数位拆分、数组最值、图形打印……）。
"""
import io
import os

# 主题 -> {等级: [(代码行列表, 一句话讲解), ...]}
# 单变体的等级也写成列表，生成时统一处理。
DB = {
    "whip": {  # 分支长鞭 —— if / else 分支
        1: [(["if"], "分支的开头：条件成立才执行")],
        2: [(["int n = 0;"], "定义一个整数变量 n")],
        3: [(["if (n > 0) n++;"], "条件成立时 n 加一")],
        4: [(["if (n > 0) { n--; }"], "大括号包住要做的事")],
        5: [
            (["if (n > 10) {", "    n = 10;", "}"], "超过上限就压回上限"),
            (["if (n < 0) {", "    n = -n;", "}"], "负数变正数，这就是取绝对值"),
        ],
        6: [
            (["if (n % 2 == 0) {", "    cout << \"even\";", "} else {", "    cout << \"odd\";", "}"],
             "用 % 取余判断奇偶"),
            (["if (y % 4 == 0 && y % 100 != 0) {", "    cout << \"leap\";", "} else {",
              "    cout << \"no\";", "}"], "两个条件同时满足用 &&"),
        ],
        7: [
            (["int n = 7;", "if (n % 2 == 0) {", "    cout << \"even\";", "} else {",
              "    cout << \"odd\";", "}"], "二选一：if 走一条，else 走另一条"),
            (["int s = 85;", "if (s >= 90) {", "    cout << \"A\";", "} else if (s >= 60) {",
              "    cout << \"B\";", "} else {", "    cout << \"C\";", "}"],
             "else if 可以接着往下分"),
            (["int a = 3;", "int b = 9;", "if (a > b) {", "    cout << a;", "} else {",
              "    cout << b;", "}"], "比大小：谁大就输出谁"),
        ],
        8: [
            (["int n = 0;", "for (int i = 1; i <= 10; i++) {", "    if (i % 2 == 0) {",
              "        n = n + i;", "    }", "}", "cout << n;"], "循环里套分支：只累加偶数"),
            (["int n = 13;", "int f = 0;", "for (int i = 2; i < n; i++) {",
              "    if (n % i == 0) {", "        f = 1;", "    }", "}", "if (f == 0) {",
              "    cout << \"prime\";", "}"], "用标记变量判断素数"),
            (["int a = 3, b = 9, c = 5;", "int m = a;", "if (b > m) {", "    m = b;", "}",
              "if (c > m) {", "    m = c;", "}", "cout << m << endl;"],
             "打擂台：一个个比出最大值"),
        ],
    },
    "orbit": {  # 循环护盾 —— for 循环
        1: [(["for"], "循环的开头：重复做同一件事")],
        2: [(["int i = 0;"], "循环变量 i 从 0 开始")],
        3: [(["i++;"], "i 自己加一，等价于 i = i + 1")],
        4: [(["for (int i = 0; i < 10; i++)"], "三个部分：起点、条件、步进")],
        5: [
            (["for (int i = 0; i < 10; i++) {", "    cout << i;", "}"], "把 0 到 9 依次打印出来"),
            (["for (int i = 1; i <= 5; i++) {", "    cout << i * i;", "}"], "循环里先算再输出"),
        ],
        6: [
            (["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "}"],
             "累加：把每次的 i 加进 s"),
            (["int s = 1;", "for (int i = 1; i <= 5; i++) {", "    s = s * i;", "}"],
             "累乘：这就是阶乘"),
        ],
        7: [
            (["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "}",
              "cout << s;"], "算完再输出 1 到 10 的和"),
            (["for (int i = 9; i >= 0; i--) {", "    cout << i << endl;", "}"],
             "循环也能倒着走，i--"),
            (["int s = 0;", "for (int i = 1; s <= 100; i++) {", "    s = s + i;", "}",
              "cout << s;"], "循环条件里也可以用变量"),
        ],
        8: [
            (["int s = 0;", "for (int i = 0; i <= 100; i++) {", "    if (i % 3 == 0) {",
              "        s = s + i;", "    }", "}", "cout << s << endl;"],
             "0 到 100 里能被 3 整除的数之和"),
            (["long long f = 1;", "for (int i = 1; i <= 10; i++) {", "    f = f * i;", "}",
              "cout << f << endl;"], "结果太大就换 long long 装"),
            (["for (int i = 1; i <= 3; i++) {", "    for (int j = 1; j <= i; j++) {",
              "        cout << j << \"*\" << i << \" \";", "    }", "    cout << endl;", "}"],
             "循环套循环：打印半个乘法表"),
        ],
    },
    "broadcast": {  # 广播冲击波 —— 输出
        1: [(["cout"], "输出的开头：把内容送到屏幕")],
        2: [(["int x = 1;"], "先准备一个要输出的数")],
        3: [(["cout << x;"], "两个小于号表示「流向」屏幕")],
        4: [(["cout << x << endl;"], "endl 表示换行")],
        5: [
            (["cout << \"hi\";", "cout << endl;"], "字符串要加双引号"),
            (["cout << 1 + 2 << endl;"], "可以先把算式算完再输出"),
        ],
        6: [
            (["int x = 5;", "cout << \"x = \";", "cout << x << endl;"], "文字和数字可以拼着输出"),
            (["int n = 7;", "cout << \"n=\" << n << \"!\" << endl;"], "一个 cout 能接好几段"),
        ],
        7: [
            (["for (int i = 0; i < 3; i++) {", "    cout << \"wave \" << i << endl;", "}"],
             "循环里输出，一次发三波"),
            (["for (int i = 1; i <= 3; i++) {", "    cout << i << \"-\" << i * i << endl;", "}"],
             "边输出边算平方"),
        ],
        8: [
            (["int n = 3;", "for (int i = 1; i <= n; i++) {", "    cout << \"wave \" << i << endl;",
              "}", "cout << \"done\" << endl;"], "输出结束后再报一句完成"),
            (["int n = 5;", "for (int i = 1; i <= n; i++) {", "    cout << i;",
              "    if (i < n) {", "        cout << \",\";", "    }", "}", "cout << endl;"],
             "经典题：数字之间用逗号隔开，最后不加"),
            (["for (int i = 3; i >= 1; i--) {", "    for (int j = 0; j < i; j++) {",
              "        cout << \"*\";", "    }", "    cout << endl;", "}"],
             "两层循环画一个倒三角"),
        ],
    },
    "judgment": {  # 随机数审判 —— rand
        1: [(["rand"], "随机数函数：每次结果都可能不同")],
        2: [(["int r = 0;"], "准备一个变量装随机数")],
        3: [(["r = rand();"], "取一个随机数存进 r")],
        4: [(["int r = rand() % 6;"], "% 6 把范围压到 0 到 5，像掷骰子")],
        5: [
            (["int r = rand() % 6;", "cout << r;"], "掷一次骰子并输出结果"),
            (["int r = rand() % 10 + 1;", "cout << r;"], "% 10 + 1 得到 1 到 10"),
        ],
        6: [
            (["int r = rand() % 100;", "if (r < 50) {", "    cout << \"low\";", "}"],
             "随机结果参与判断"),
            (["int r = rand() % 6 + 1;", "if (r == 6) {", "    cout << \"win\";", "}"],
             "掷到 6 才算赢"),
        ],
        7: [
            (["int r = rand() % 100;", "if (r < 50) {", "    cout << \"low\";", "} else {",
              "    cout << \"high\";", "}"], "随机 + 二选一"),
            (["int a = rand() % 6 + 1;", "int b = rand() % 6 + 1;", "cout << a + b << endl;"],
             "掷两次骰子，把点数加起来"),
        ],
        8: [
            (["int n = 0;", "for (int i = 0; i < 10; i++) {", "    if (rand() % 2 == 0) {",
              "        n++;", "    }", "}", "cout << n << endl;"], "扔十次硬币，数正面朝上的次数"),
            (["int c = 0;", "for (int i = 0; i < 20; i++) {", "    if (rand() % 6 + 1 == 6) {",
              "        c++;", "    }", "}", "cout << c << endl;"], "掷 20 次，数 6 出了几次"),
            (["int x = rand() % 100;", "int g = 50;", "if (g == x) {", "    cout << \"hit\";",
              "} else if (g < x) {", "    cout << \"low\";", "} else {", "    cout << \"high\";",
              "}"], "猜数游戏：告诉玩家猜大了还是猜小了"),
        ],
    },
    "blade": {  # 递归飞刃 —— 函数
        1: [(["int"], "函数的返回值类型")],
        2: [(["return 0;"], "return 把结果送回去")],
        3: [(["int f(int n)"], "函数头：名字、参数、返回类型")],
        4: [(["int f(int n) { return n; }"], "最简单的函数：原样返回")],
        5: [
            (["int f(int n) {", "    return n * 2;", "}"], "函数里做一次运算再返回"),
            (["int sq(int n) {", "    return n * n;", "}"], "求平方的函数"),
        ],
        6: [
            (["int add(int a, int b) {", "    return a + b;", "}"], "两个参数的函数"),
            (["int max2(int a, int b) {", "    if (a > b) {", "        return a;", "    }",
              "    return b;", "}"], "函数里可以先判断再返回"),
        ],
        7: [
            (["int f(int n) {", "    if (n <= 1) {", "        return 1;", "    }",
              "    return n * f(n - 1);", "}"], "自己调用自己，这就是递归"),
            (["int fib(int n) {", "    if (n <= 2) {", "        return 1;", "    }",
              "    return fib(n - 1) + fib(n - 2);", "}"], "斐波那契：前两个相加"),
        ],
        8: [
            (["int sum(int n) {", "    int s = 0;", "    for (int i = 1; i <= n; i++) {",
              "        s = s + i;", "    }", "    return s;", "}"], "用函数算出 1 到 n 的和"),
            (["int gcd(int a, int b) {", "    while (b != 0) {", "        int t = a % b;",
              "        a = b;", "        b = t;", "    }", "    return a;", "}"],
             "辗转相除求最大公约数"),
            (["int sum(int n) {", "    if (n == 1) {", "        return 1;", "    }",
              "    return n + sum(n - 1);", "}"], "递归版求和：n 加上前面所有项"),
        ],
    },
    "pointer": {  # 指针追踪 —— 指针
        1: [(["int* p;"], "星号表示这是一个指针变量")],
        2: [(["int n = 5;"], "先有一个普通的整数")],
        3: [(["int* p = &n;"], "& 取地址，让 p 指向 n")],
        4: [(["cout << *p;"], "*p 表示「p 指向的那个值」")],
        5: [
            (["int n = 5;", "int* p = &n;", "cout << *p;"], "指过去再读出来"),
            (["int a = 3;", "int* p = &a;", "cout << *p + 1;"], "取到的值能直接参与运算"),
        ],
        6: [
            (["int n = 5;", "int* p = &n;", "*p = *p + 1;", "cout << n;"], "通过指针改值，n 也跟着变"),
            (["void swap(int* a, int* b) {", "    int t = *a;", "    *a = *b;", "    *b = t;",
              "}"], "经典：交换两个数"),
        ],
        7: [
            (["void up(int* p) {", "    *p = *p + 1;", "}"], "把指针传进函数才能改到外面"),
            (["int a[3] = {1, 2, 3};", "int* p = a;", "cout << *(p + 1);"], "数组名就是首地址"),
        ],
        8: [
            (["int n = 0;", "int* p = &n;", "for (int i = 0; i < 5; i++) {", "    *p = *p + i;",
              "}", "cout << n << endl;"], "循环里通过指针累加"),
            (["int a[5] = {1, 2, 3, 4, 5};", "int* p = a;", "int s = 0;",
              "for (int i = 0; i < 5; i++) {", "    s = s + *(p + i);", "}",
              "cout << s << endl;"], "用指针走完整个数组"),
            (["void swap(int* a, int* b) {", "    int t = *a;", "    *a = *b;", "    *b = t;",
              "}", "int x = 1, y = 2;", "swap(&x, &y);", "cout << x << \" \" << y;"],
             "传地址进去，外面才真的换了"),
        ],
    },
    "volley": {  # 多线程齐射 —— 数组 + 循环
        1: [(["int a[5];"], "数组：一排编号的格子")],
        2: [(["a[0] = 1;"], "下标从 0 开始，不是 1")],
        3: [(["cout << a[0];"], "按下标取出来")],
        4: [(["for (int i = 0; i < 5; i++)"], "用循环走遍每个下标")],
        5: [
            (["int a[5] = {1, 2, 3, 4, 5};", "cout << a[0];"], "定义时直接给初值"),
            (["int a[3] = {5, 2, 9};", "cout << a[2];"], "最后一个的下标是 2 不是 3"),
        ],
        6: [
            (["int a[5] = {1, 2, 3, 4, 5};", "for (int i = 0; i < 5; i++) {", "    cout << a[i];",
              "}"], "遍历数组全部输出"),
            (["int a[5] = {1, 2, 3, 4, 5};", "for (int i = 4; i >= 0; i--) {",
              "    cout << a[i];", "}"], "倒着遍历：从 4 走到 0"),
        ],
        7: [
            (["int a[5] = {1, 2, 3, 4, 5};", "int s = 0;", "for (int i = 0; i < 5; i++) {",
              "    s = s + a[i];", "}", "cout << s;"], "把数组里的数全加起来"),
            (["int a[5] = {3, 9, 2, 7, 5};", "int m = a[0];", "for (int i = 1; i < 5; i++) {",
              "    if (a[i] > m) {", "        m = a[i];", "    }", "}", "cout << m;"],
             "打擂台：找出数组里的最大值"),
            (["int a[4] = {1, 2, 3, 4};", "for (int i = 0; i < 4; i++) {",
              "    a[i] = a[i] * 2;", "    cout << a[i] << \" \";", "}"], "原地把每个元素翻倍"),
        ],
        8: [
            (["int a[5] = {2, 4, 6, 8, 10};", "int s = 0;", "for (int i = 0; i < 5; i++) {",
              "    if (a[i] % 4 == 0) {", "        s = s + a[i];", "    }", "}",
              "cout << s << endl;"], "只累加符合条件的元素"),
            (["int a[6] = {1, 2, 3, 4, 5, 6};", "int c = 0;", "for (int i = 0; i < 6; i++) {",
              "    if (a[i] % 2 == 0) {", "        c++;", "    }", "}", "cout << c << endl;"],
             "数一数数组里有几个偶数"),
            (["int a[5];", "int s = 0;", "for (int i = 0; i < 5; i++) {", "    cin >> a[i];",
              "    s = s + a[i];", "}", "cout << s / 5 << endl;"],
             "从键盘读入五个数，输出平均数"),
        ],
    },
    "gc": {  # 垃圾回收 —— 数组与内存
        1: [(["int n = 0;"], "先准备一个计数变量")],
        2: [(["int a[10];"], "申请十个整数的空间")],
        3: [(["a[i] = 0;"], "按下标写入")],
        4: [(["for (int i = 0; i < 10; i++)"], "循环覆盖全部下标")],
        5: [
            (["int a[10];", "for (int i = 0; i < 10; i++) {", "    a[i] = 0;", "}"],
             "把数组全部清零"),
            (["int a[5];", "for (int i = 0; i < 5; i++) {", "    a[i] = i + 1;", "}"],
             "按下标依次填入 1 到 5"),
        ],
        6: [
            (["int a[10];", "a[0] = 1;", "a[1] = 1;", "for (int i = 2; i < 10; i++) {",
              "    a[i] = a[i - 1] + a[i - 2];", "}"], "后面的数由前面两个相加得到"),
            (["int a[5] = {1, 2, 3, 4, 5};", "int b[5];", "for (int i = 0; i < 5; i++) {",
              "    b[i] = a[i];", "}"], "把数组一个一个搬过去"),
        ],
        7: [
            (["int a[10];", "a[0] = 1;", "a[1] = 1;", "for (int i = 2; i < 10; i++) {",
              "    a[i] = a[i - 1] + a[i - 2];", "}", "cout << a[9];"], "算出最后一个数并输出"),
            (["int a[6] = {0, 3, 0, 5, 0, 7};", "int c = 0;", "for (int i = 0; i < 6; i++) {",
              "    if (a[i] != 0) {", "        c++;", "    }", "}", "cout << c;"],
             "跳过空格子，只数有值的"),
        ],
        8: [
            (["int a[10] = {0};", "int n = 0;", "for (int i = 0; i < 10; i++) {",
              "    a[i] = i * i;", "    n = n + a[i];", "}", "cout << n << endl;"],
             "存平方数，同时累加"),
            (["int a[10] = {0};", "for (int i = 0; i < 10; i++) {",
              "    a[i] = (i + 1) * (i + 1);", "}", "int s = 0;",
              "for (int i = 0; i < 10; i++) {", "    s = s + a[i];", "}", "cout << s << endl;"],
             "两个循环：先把表填好，再求和"),
            (["int a[10] = {0};", "a[0] = 1;", "a[1] = 1;", "int s = 2;",
              "for (int i = 2; i < 10; i++) {", "    a[i] = a[i - 1] + a[i - 2];",
              "    s = s + a[i];", "}", "cout << s << endl;"], "边生成边累加"),
        ],
    },
    "buffer": {  # 缓冲区溢出 —— 边界
        1: [(["int i = 0;"], "下标从 0 开始")],
        2: [(["i < 10;"], "循环条件：不能等于 10")],
        3: [(["if (i < 10)"], "先判断再取，防止越界")],
        4: [(["while (i < 10)"], "条件成立就一直做")],
        5: [
            (["int i = 0;", "while (i < 10) {", "    i++;", "}"], "while 版本的计数循环"),
            (["int i = 0;", "while (i < 5) {", "    cout << i;", "    i++;", "}"],
             "少了 i++ 就永远出不来"),
        ],
        6: [
            (["int a[10];", "for (int i = 0; i < 10; i++) {", "    a[i] = i;", "}"],
             "写满十格，一格不多"),
            (["int a[10];", "int i = 0;", "while (i < 10) {", "    a[i] = i;", "    i++;", "}"],
             "用 while 也能填满数组"),
        ],
        7: [
            (["int a[10];", "int n = 0;", "for (int i = 0; i < 10; i++) {", "    a[i] = i * 2;",
              "    n++;", "}", "cout << n;"], "边写边数，最后输出个数"),
            (["int n = 1234;", "int c = 0;", "while (n > 0) {", "    n = n / 10;", "    c++;",
              "}", "cout << c;"], "经典题：每次砍掉最后一位，数位数"),
        ],
        8: [
            (["int a[10];", "int s = 0;", "for (int i = 0; i < 10; i++) {", "    a[i] = i + 1;",
              "    if (a[i] > 5) {", "        s = s + a[i];", "    }", "}",
              "cout << s << endl;"], "越界是 bug，条件要写死"),
            (["int n = 1234;", "int r = 0;", "while (n > 0) {", "    r = r * 10 + n % 10;",
              "    n = n / 10;", "}", "cout << r << endl;"], "经典题：把数字倒过来"),
            (["int s = 0;", "for (int i = 1; i <= 100; i++) {", "    s = s + i;",
              "    if (s > 1000) {", "        break;", "    }", "}", "cout << s << endl;"],
             "break：够了就提前跳出循环"),
        ],
    },
    "breakpoint": {  # 断点调试 —— 输出中间过程
        1: [(["int k = 0;"], "准备一个观察用的变量")],
        2: [(["k = k + 1;"], "手动往前推一步")],
        3: [(["cout << k;"], "把当前值打印出来看")],
        4: [(["cout << \"step \" << k;"], "输出时带上说明文字")],
        5: [
            (["cout << \"step 1\";", "cout << endl;"], "一步一步打点"),
            (["int a = 5;", "cout << \"a=\" << a << endl;"], "输出时带上变量的名字"),
        ],
        6: [
            (["for (int i = 0; i < 3; i++) {", "    cout << \"step \" << i << endl;", "}"],
             "每轮循环都留一个记号"),
            (["for (int i = 1; i <= 3; i++) {", "    cout << i << \"*3=\" << i * 3 << endl;",
              "}"], "把每一步的结果都打出来"),
        ],
        7: [
            (["int s = 0;", "for (int i = 1; i <= 5; i++) {", "    s = s + i;",
              "    cout << s << endl;", "}"], "每加一次就打印，看过程"),
            (["int m = 0;", "for (int i = 1; i <= 5; i++) {", "    if (i > m) {",
              "        m = i;", "    }", "    cout << m << endl;", "}"],
             "看最大值是怎么一点点变大的"),
        ],
        8: [
            (["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;",
              "    cout << i << \" : \" << s << endl;", "}", "cout << \"sum = \" << s << endl;"],
             "把每一步和最后结果都打出来"),
            (["int f = 1;", "for (int i = 1; i <= 5; i++) {", "    f = f * i;",
              "    cout << i << \"!=\" << f << endl;", "}"], "打印每一步的阶乘"),
            (["int s = 0;", "for (int i = 1; i <= 5; i++) {", "    s = s + i;",
              "    cout << s << endl;", "}", "cout << \"avg=\" << s / 5 << endl;"],
             "过程打完，最后算个平均"),
        ],
    },
    "forever": {  # 永真力场 —— while
        1: [(["while"], "条件成立就一直重复")],
        2: [(["int n = 0;"], "准备一个会被改变的变量")],
        3: [(["while (n < 5)"], "条件写在括号里")],
        4: [(["while (n < 5) { n++; }"], "别忘让 n 变大，否则停不下来")],
        5: [
            (["while (n < 5) {", "    n++;", "}"], "循环体必须能推进条件"),
            (["int n = 10;", "while (n > 0) {", "    n = n - 2;", "}"], "倒着数也能停下来"),
        ],
        6: [
            (["int n = 0;", "while (n < 5) {", "    n = n + 2;", "}", "cout << n;"],
             "步长可以是 2"),
            (["int n = 1;", "while (n < 100) {", "    n = n * 2;", "}", "cout << n;"],
             "每次翻倍，长得非常快"),
        ],
        7: [
            (["int n = 0;", "while (n < 100) {", "    n = n + 7;", "}", "cout << n << endl;"],
             "一直加到超过 100"),
            (["int n = 123;", "int s = 0;", "while (n > 0) {", "    s = s + n % 10;",
              "    n = n / 10;", "}", "cout << s << endl;"], "经典题：把每一位数字加起来"),
        ],
        8: [
            (["int n = 0;", "int c = 0;", "while (n < 100) {", "    n = n + 3;", "    c++;", "}",
              "cout << c << endl;"], "顺便数一共加了多少次"),
            (["int s = 0;", "int i = 1;", "while (s <= 100) {", "    s = s + i;", "    i++;",
              "}", "cout << i - 1 << endl;"], "一直加到刚好超过 100，看加到几"),
            (["int n = 100;", "int c = 0;", "while (n > 1) {", "    n = n / 2;", "    c++;",
              "}", "cout << c << endl;"], "每次减半，数要减几次"),
        ],
    },
    "rebuild": {  # 全量重编译 —— 完整程序
        1: [(["int main()"], "程序从 main 开始执行")],
        2: [(["return 0;"], "返回 0 表示正常结束")],
        3: [(["int x = 1;"], "在 main 里定义变量")],
        4: [(["cout << x << endl;"], "输出后换行")],
        5: [
            (["int a = 3;", "int b = 4;", "cout << a + b;"], "先算再输出"),
            (["int r = 5;", "cout << r * r * 3 << endl;"], "套公式算圆的面积近似值"),
        ],
        6: [
            (["int a = 3;", "int b = 4;", "int c = a * b;", "cout << c << endl;"],
             "中间结果存进新变量"),
            (["int a = 3, b = 5;", "int t = a;", "a = b;", "b = t;",
              "cout << a << \" \" << b << endl;"], "交换两个变量要借一个临时变量"),
        ],
        7: [
            (["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "}",
              "cout << s << endl;"], "完整的累加程序"),
            (["int y = 2024;", "if (y % 400 == 0) {", "    cout << \"leap\";",
              "} else if (y % 4 == 0 && y % 100 != 0) {", "    cout << \"leap\";", "} else {",
              "    cout << \"no\";", "}"],
             "闰年：被 400 整除，或被 4 整除但不被 100 整除"),
        ],
        8: [
            (["int s = 0;", "for (int i = 0; i <= 100; i++) {", "    s = s + i;", "}",
              "cout << s << endl;"], "求 0 到 100 所有整数的和"),
            (["int h = 35, f = 94;", "for (int r = 0; r <= h; r++) {",
              "    if (r * 2 + (h - r) * 4 == f) {", "        cout << r << \" \" << h - r << endl;",
              "    }", "}"], "鸡兔同笼：一只一只试，试到脚数对上"),
            (["for (int n = 100; n <= 999; n++) {", "    int a = n / 100;",
              "    int b = n / 10 % 10;", "    int c = n % 10;",
              "    if (a*a*a + b*b*b + c*c*c == n) {", "        cout << n << endl;", "    }",
              "}"], "水仙花数：各位立方和刚好等于自己"),
        ],
    },
    "general": {  # 被动 / 进化 / 兜底
        1: [(["int"], "整数类型")],
        2: [(["int n = 0;"], "定义变量并给初值")],
        3: [(["n = n + 1;"], "自增的写法")],
        4: [(["cout << n << endl;"], "输出并换行")],
        5: [
            (["int n = 0;", "n = n + 1;", "cout << n;"], "改完立刻看结果"),
            (["int a = 2;", "int b = a * a;", "cout << b;"], "中间变量装一下再输出"),
        ],
        6: [
            (["int s = 0;", "for (int i = 0; i < 5; i++) {", "    s = s + i;", "}"],
             "小循环做累加"),
            (["int s = 0;", "for (int i = 1; i <= 9; i++) {", "    s = s + i;", "}",
              "cout << s;"], "1 到 9 的和"),
        ],
        7: [
            (["int s = 0;", "for (int i = 0; i < 5; i++) {", "    s = s + i;", "}",
              "cout << s << endl;"], "累加后输出"),
            (["int n = 10;", "int s = 0;", "for (int i = 1; i <= n; i++) {", "    s = s + i;",
              "}", "cout << s << endl;"], "用变量控制循环要走多少次"),
        ],
        8: [
            (["int s = 0;", "for (int i = 1; i <= 100; i++) {", "    s = s + i;", "}",
              "cout << s << endl;"], "求 1 到 100 所有整数的和"),
            (["int c = 0;", "for (int i = 1; i <= 100; i++) {", "    if (i % 7 == 0) {",
              "        c++;", "    }", "}", "cout << c << endl;"],
             "数 100 以内有几个 7 的倍数"),
            (["int s = 0;", "for (int i = 1; i <= 100; i += 2) {", "    s = s + i;", "}",
              "cout << s << endl;"], "步长改成 2：只走奇数"),
        ],
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
lines.append('## Lv5 起每级有多道「变体」（同一难度、不同考点的题），出题时随机抽一道，')
lines.append('## 抽中哪道由 CodeChallenge.build 决定。题目主要取自 GESP C++ 与 NOIP 入门题：')
lines.append('## 求和、阶乘、素数、闰年、水仙花数、鸡兔同笼、辗转相除、数位拆分、最值、图形打印。')
lines.append('##')
lines.append('## 代码一律 ASCII（等宽字体只子集了 ASCII），中文讲解放 TIPS。')
lines.append('## 缩进统一 4 空格。')
lines.append('')
lines.append('')
lines.append('## 主题 -> 等级 -> [变体0 的代码行, 变体1 的代码行, ...]')
lines.append('const FRAG := {')

n_var = 0
for theme in DB:
    lines.append('\t"%s": {' % theme)
    for lv in range(1, 9):
        pool = DB[theme][lv]
        n_var += len(pool)
        items = ", ".join(
            "[" + ", ".join(gd_str(c) for c in code) + "]" for code, _t in pool)
        lines.append('\t\t%d: [%s],' % (lv, items))
    lines.append('\t},')
lines.append('}')
lines.append('')
lines.append('')
lines.append('## 主题 -> 等级 -> [变体0 的讲解, 变体1 的讲解, ...]（与 FRAG 一一对应）')
lines.append('const TIPS := {')
for theme in DB:
    lines.append('\t"%s": {' % theme)
    for lv in range(1, 9):
        pool = DB[theme][lv]
        items = ", ".join(gd_str(tip) for _c, tip in pool)
        lines.append('\t\t%d: [%s],' % (lv, items))
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
lines.append('## 取某主题某等级的「题目池」。主题没有这一级就退回 general，再没有就是空。')
lines.append('static func _pool(table: Dictionary, theme: String, level: int) -> Array:')
lines.append('\tvar by_lv: Dictionary = table.get(theme, {})')
lines.append('\tif not by_lv.has(level):')
lines.append('\t\tby_lv = table.get("general", {})')
lines.append('\tif not by_lv.has(level):')
lines.append('\t\treturn []')
lines.append('\treturn by_lv[level] as Array')
lines.append('')
lines.append('')
lines.append('## 这一级一共有几道变体（出题端用它决定随机范围）')
lines.append('static func variants(theme: String, level: int) -> int:')
lines.append('\treturn _pool(FRAG, theme, level).size()')
lines.append('')
lines.append('')
lines.append('## 取某主题某等级第 idx 道变体的代码行。')
lines.append('## idx 越界一律退回第 0 道 —— 出题端宁可重复，也不能崩在升级那一刻。')
lines.append('static func frag(theme: String, level: int, idx: int = 0) -> Array:')
lines.append('\tvar p := _pool(FRAG, theme, level)')
lines.append('\tif p.is_empty():')
lines.append('\t\treturn []')
lines.append('\tvar i := idx')
lines.append('\tif i < 0 or i >= p.size():')
lines.append('\t\ti = 0')
lines.append('\treturn (p[i] as Array).duplicate()')
lines.append('')
lines.append('')
lines.append('## 取对应变体的讲解文案')
lines.append('static func tip(theme: String, level: int, idx: int = 0) -> String:')
lines.append('\tvar p := _pool(TIPS, theme, level)')
lines.append('\tif p.is_empty():')
lines.append('\t\treturn ""')
lines.append('\tvar i := idx')
lines.append('\tif i < 0 or i >= p.size():')
lines.append('\t\ti = 0')
lines.append('\treturn str(p[i])')
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
print('主题数', len(DB), '· 题目数', n_var, '· 文件行数', out.count('\n'))
