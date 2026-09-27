class_name CodeChallengeDB
extends RefCounted
##
## 升级打码的 C++ 题库（纯数据，由 tools 下的生成脚本产出，不要手改）。
##
## 只存「标准档」片段，轻松档/严格档由 CodeChallenge 在运行时派生：
##   轻松 = 去掉纯括号行后最长的那一行
##   严格 = Lv6 及以上再包一层 main 结构
##
## Lv5 起每级有多道「变体」（同一难度、不同考点的题），出题时随机抽一道，
## 抽中哪道由 CodeChallenge.build 决定。题目主要取自 GESP C++ 与 NOIP 入门题：
## 求和、阶乘、素数、闰年、水仙花数、鸡兔同笼、辗转相除、数位拆分、最值、图形打印。
##
## 代码一律 ASCII（等宽字体只子集了 ASCII），中文讲解放 TIPS。
## 缩进统一 4 空格。


## 主题 -> 等级 -> [变体0 的代码行, 变体1 的代码行, ...]
const FRAG := {
	"whip": {
		1: [["if"]],
		2: [["int n = 0;"]],
		3: [["if (n > 0) n++;"]],
		4: [["if (n > 0) { n--; }"]],
		5: [["if (n > 10) {", "    n = 10;", "}"], ["if (n < 0) {", "    n = -n;", "}"]],
		6: [["if (n % 2 == 0) {", "    cout << \"even\";", "} else {", "    cout << \"odd\";", "}"], ["if (y % 4 == 0 && y % 100 != 0) {", "    cout << \"leap\";", "} else {", "    cout << \"no\";", "}"]],
		7: [["int n = 7;", "if (n % 2 == 0) {", "    cout << \"even\";", "} else {", "    cout << \"odd\";", "}"], ["int s = 85;", "if (s >= 90) {", "    cout << \"A\";", "} else if (s >= 60) {", "    cout << \"B\";", "} else {", "    cout << \"C\";", "}"], ["int a = 3;", "int b = 9;", "if (a > b) {", "    cout << a;", "} else {", "    cout << b;", "}"]],
		8: [["int n = 0;", "for (int i = 1; i <= 10; i++) {", "    if (i % 2 == 0) {", "        n = n + i;", "    }", "}", "cout << n;"], ["int n = 13;", "int f = 0;", "for (int i = 2; i < n; i++) {", "    if (n % i == 0) {", "        f = 1;", "    }", "}", "if (f == 0) {", "    cout << \"prime\";", "}"], ["int a = 3, b = 9, c = 5;", "int m = a;", "if (b > m) {", "    m = b;", "}", "if (c > m) {", "    m = c;", "}", "cout << m << endl;"]],
	},
	"orbit": {
		1: [["for"]],
		2: [["int i = 0;"]],
		3: [["i++;"]],
		4: [["for (int i = 0; i < 10; i++)"]],
		5: [["for (int i = 0; i < 10; i++) {", "    cout << i;", "}"], ["for (int i = 1; i <= 5; i++) {", "    cout << i * i;", "}"]],
		6: [["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "}"], ["int s = 1;", "for (int i = 1; i <= 5; i++) {", "    s = s * i;", "}"]],
		7: [["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "}", "cout << s;"], ["for (int i = 9; i >= 0; i--) {", "    cout << i << endl;", "}"], ["int s = 0;", "for (int i = 1; s <= 100; i++) {", "    s = s + i;", "}", "cout << s;"]],
		8: [["int s = 0;", "for (int i = 0; i <= 100; i++) {", "    if (i % 3 == 0) {", "        s = s + i;", "    }", "}", "cout << s << endl;"], ["long long f = 1;", "for (int i = 1; i <= 10; i++) {", "    f = f * i;", "}", "cout << f << endl;"], ["for (int i = 1; i <= 3; i++) {", "    for (int j = 1; j <= i; j++) {", "        cout << j << \"*\" << i << \" \";", "    }", "    cout << endl;", "}"]],
	},
	"broadcast": {
		1: [["cout"]],
		2: [["int x = 1;"]],
		3: [["cout << x;"]],
		4: [["cout << x << endl;"]],
		5: [["cout << \"hi\";", "cout << endl;"], ["cout << 1 + 2 << endl;"]],
		6: [["int x = 5;", "cout << \"x = \";", "cout << x << endl;"], ["int n = 7;", "cout << \"n=\" << n << \"!\" << endl;"]],
		7: [["for (int i = 0; i < 3; i++) {", "    cout << \"wave \" << i << endl;", "}"], ["for (int i = 1; i <= 3; i++) {", "    cout << i << \"-\" << i * i << endl;", "}"]],
		8: [["int n = 3;", "for (int i = 1; i <= n; i++) {", "    cout << \"wave \" << i << endl;", "}", "cout << \"done\" << endl;"], ["int n = 5;", "for (int i = 1; i <= n; i++) {", "    cout << i;", "    if (i < n) {", "        cout << \",\";", "    }", "}", "cout << endl;"], ["for (int i = 3; i >= 1; i--) {", "    for (int j = 0; j < i; j++) {", "        cout << \"*\";", "    }", "    cout << endl;", "}"]],
	},
	"judgment": {
		1: [["rand"]],
		2: [["int r = 0;"]],
		3: [["r = rand();"]],
		4: [["int r = rand() % 6;"]],
		5: [["int r = rand() % 6;", "cout << r;"], ["int r = rand() % 10 + 1;", "cout << r;"]],
		6: [["int r = rand() % 100;", "if (r < 50) {", "    cout << \"low\";", "}"], ["int r = rand() % 6 + 1;", "if (r == 6) {", "    cout << \"win\";", "}"]],
		7: [["int r = rand() % 100;", "if (r < 50) {", "    cout << \"low\";", "} else {", "    cout << \"high\";", "}"], ["int a = rand() % 6 + 1;", "int b = rand() % 6 + 1;", "cout << a + b << endl;"]],
		8: [["int n = 0;", "for (int i = 0; i < 10; i++) {", "    if (rand() % 2 == 0) {", "        n++;", "    }", "}", "cout << n << endl;"], ["int c = 0;", "for (int i = 0; i < 20; i++) {", "    if (rand() % 6 + 1 == 6) {", "        c++;", "    }", "}", "cout << c << endl;"], ["int x = rand() % 100;", "int g = 50;", "if (g == x) {", "    cout << \"hit\";", "} else if (g < x) {", "    cout << \"low\";", "} else {", "    cout << \"high\";", "}"]],
	},
	"blade": {
		1: [["int"]],
		2: [["return 0;"]],
		3: [["int f(int n)"]],
		4: [["int f(int n) { return n; }"]],
		5: [["int f(int n) {", "    return n * 2;", "}"], ["int sq(int n) {", "    return n * n;", "}"]],
		6: [["int add(int a, int b) {", "    return a + b;", "}"], ["int max2(int a, int b) {", "    if (a > b) {", "        return a;", "    }", "    return b;", "}"]],
		7: [["int f(int n) {", "    if (n <= 1) {", "        return 1;", "    }", "    return n * f(n - 1);", "}"], ["int fib(int n) {", "    if (n <= 2) {", "        return 1;", "    }", "    return fib(n - 1) + fib(n - 2);", "}"]],
		8: [["int sum(int n) {", "    int s = 0;", "    for (int i = 1; i <= n; i++) {", "        s = s + i;", "    }", "    return s;", "}"], ["int gcd(int a, int b) {", "    while (b != 0) {", "        int t = a % b;", "        a = b;", "        b = t;", "    }", "    return a;", "}"], ["int sum(int n) {", "    if (n == 1) {", "        return 1;", "    }", "    return n + sum(n - 1);", "}"]],
	},
	"pointer": {
		1: [["int* p;"]],
		2: [["int n = 5;"]],
		3: [["int* p = &n;"]],
		4: [["cout << *p;"]],
		5: [["int n = 5;", "int* p = &n;", "cout << *p;"], ["int a = 3;", "int* p = &a;", "cout << *p + 1;"]],
		6: [["int n = 5;", "int* p = &n;", "*p = *p + 1;", "cout << n;"], ["void swap(int* a, int* b) {", "    int t = *a;", "    *a = *b;", "    *b = t;", "}"]],
		7: [["void up(int* p) {", "    *p = *p + 1;", "}"], ["int a[3] = {1, 2, 3};", "int* p = a;", "cout << *(p + 1);"]],
		8: [["int n = 0;", "int* p = &n;", "for (int i = 0; i < 5; i++) {", "    *p = *p + i;", "}", "cout << n << endl;"], ["int a[5] = {1, 2, 3, 4, 5};", "int* p = a;", "int s = 0;", "for (int i = 0; i < 5; i++) {", "    s = s + *(p + i);", "}", "cout << s << endl;"], ["void swap(int* a, int* b) {", "    int t = *a;", "    *a = *b;", "    *b = t;", "}", "int x = 1, y = 2;", "swap(&x, &y);", "cout << x << \" \" << y;"]],
	},
	"volley": {
		1: [["int a[5];"]],
		2: [["a[0] = 1;"]],
		3: [["cout << a[0];"]],
		4: [["for (int i = 0; i < 5; i++)"]],
		5: [["int a[5] = {1, 2, 3, 4, 5};", "cout << a[0];"], ["int a[3] = {5, 2, 9};", "cout << a[2];"]],
		6: [["int a[5] = {1, 2, 3, 4, 5};", "for (int i = 0; i < 5; i++) {", "    cout << a[i];", "}"], ["int a[5] = {1, 2, 3, 4, 5};", "for (int i = 4; i >= 0; i--) {", "    cout << a[i];", "}"]],
		7: [["int a[5] = {1, 2, 3, 4, 5};", "int s = 0;", "for (int i = 0; i < 5; i++) {", "    s = s + a[i];", "}", "cout << s;"], ["int a[5] = {3, 9, 2, 7, 5};", "int m = a[0];", "for (int i = 1; i < 5; i++) {", "    if (a[i] > m) {", "        m = a[i];", "    }", "}", "cout << m;"], ["int a[4] = {1, 2, 3, 4};", "for (int i = 0; i < 4; i++) {", "    a[i] = a[i] * 2;", "    cout << a[i] << \" \";", "}"]],
		8: [["int a[5] = {2, 4, 6, 8, 10};", "int s = 0;", "for (int i = 0; i < 5; i++) {", "    if (a[i] % 4 == 0) {", "        s = s + a[i];", "    }", "}", "cout << s << endl;"], ["int a[6] = {1, 2, 3, 4, 5, 6};", "int c = 0;", "for (int i = 0; i < 6; i++) {", "    if (a[i] % 2 == 0) {", "        c++;", "    }", "}", "cout << c << endl;"], ["int a[5];", "int s = 0;", "for (int i = 0; i < 5; i++) {", "    cin >> a[i];", "    s = s + a[i];", "}", "cout << s / 5 << endl;"]],
	},
	"gc": {
		1: [["int n = 0;"]],
		2: [["int a[10];"]],
		3: [["a[i] = 0;"]],
		4: [["for (int i = 0; i < 10; i++)"]],
		5: [["int a[10];", "for (int i = 0; i < 10; i++) {", "    a[i] = 0;", "}"], ["int a[5];", "for (int i = 0; i < 5; i++) {", "    a[i] = i + 1;", "}"]],
		6: [["int a[10];", "a[0] = 1;", "a[1] = 1;", "for (int i = 2; i < 10; i++) {", "    a[i] = a[i - 1] + a[i - 2];", "}"], ["int a[5] = {1, 2, 3, 4, 5};", "int b[5];", "for (int i = 0; i < 5; i++) {", "    b[i] = a[i];", "}"]],
		7: [["int a[10];", "a[0] = 1;", "a[1] = 1;", "for (int i = 2; i < 10; i++) {", "    a[i] = a[i - 1] + a[i - 2];", "}", "cout << a[9];"], ["int a[6] = {0, 3, 0, 5, 0, 7};", "int c = 0;", "for (int i = 0; i < 6; i++) {", "    if (a[i] != 0) {", "        c++;", "    }", "}", "cout << c;"]],
		8: [["int a[10] = {0};", "int n = 0;", "for (int i = 0; i < 10; i++) {", "    a[i] = i * i;", "    n = n + a[i];", "}", "cout << n << endl;"], ["int a[10] = {0};", "for (int i = 0; i < 10; i++) {", "    a[i] = (i + 1) * (i + 1);", "}", "int s = 0;", "for (int i = 0; i < 10; i++) {", "    s = s + a[i];", "}", "cout << s << endl;"], ["int a[10] = {0};", "a[0] = 1;", "a[1] = 1;", "int s = 2;", "for (int i = 2; i < 10; i++) {", "    a[i] = a[i - 1] + a[i - 2];", "    s = s + a[i];", "}", "cout << s << endl;"]],
	},
	"buffer": {
		1: [["int i = 0;"]],
		2: [["i < 10;"]],
		3: [["if (i < 10)"]],
		4: [["while (i < 10)"]],
		5: [["int i = 0;", "while (i < 10) {", "    i++;", "}"], ["int i = 0;", "while (i < 5) {", "    cout << i;", "    i++;", "}"]],
		6: [["int a[10];", "for (int i = 0; i < 10; i++) {", "    a[i] = i;", "}"], ["int a[10];", "int i = 0;", "while (i < 10) {", "    a[i] = i;", "    i++;", "}"]],
		7: [["int a[10];", "int n = 0;", "for (int i = 0; i < 10; i++) {", "    a[i] = i * 2;", "    n++;", "}", "cout << n;"], ["int n = 1234;", "int c = 0;", "while (n > 0) {", "    n = n / 10;", "    c++;", "}", "cout << c;"]],
		8: [["int a[10];", "int s = 0;", "for (int i = 0; i < 10; i++) {", "    a[i] = i + 1;", "    if (a[i] > 5) {", "        s = s + a[i];", "    }", "}", "cout << s << endl;"], ["int n = 1234;", "int r = 0;", "while (n > 0) {", "    r = r * 10 + n % 10;", "    n = n / 10;", "}", "cout << r << endl;"], ["int s = 0;", "for (int i = 1; i <= 100; i++) {", "    s = s + i;", "    if (s > 1000) {", "        break;", "    }", "}", "cout << s << endl;"]],
	},
	"breakpoint": {
		1: [["int k = 0;"]],
		2: [["k = k + 1;"]],
		3: [["cout << k;"]],
		4: [["cout << \"step \" << k;"]],
		5: [["cout << \"step 1\";", "cout << endl;"], ["int a = 5;", "cout << \"a=\" << a << endl;"]],
		6: [["for (int i = 0; i < 3; i++) {", "    cout << \"step \" << i << endl;", "}"], ["for (int i = 1; i <= 3; i++) {", "    cout << i << \"*3=\" << i * 3 << endl;", "}"]],
		7: [["int s = 0;", "for (int i = 1; i <= 5; i++) {", "    s = s + i;", "    cout << s << endl;", "}"], ["int m = 0;", "for (int i = 1; i <= 5; i++) {", "    if (i > m) {", "        m = i;", "    }", "    cout << m << endl;", "}"]],
		8: [["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "    cout << i << \" : \" << s << endl;", "}", "cout << \"sum = \" << s << endl;"], ["int f = 1;", "for (int i = 1; i <= 5; i++) {", "    f = f * i;", "    cout << i << \"!=\" << f << endl;", "}"], ["int s = 0;", "for (int i = 1; i <= 5; i++) {", "    s = s + i;", "    cout << s << endl;", "}", "cout << \"avg=\" << s / 5 << endl;"]],
	},
	"forever": {
		1: [["while"]],
		2: [["int n = 0;"]],
		3: [["while (n < 5)"]],
		4: [["while (n < 5) { n++; }"]],
		5: [["while (n < 5) {", "    n++;", "}"], ["int n = 10;", "while (n > 0) {", "    n = n - 2;", "}"]],
		6: [["int n = 0;", "while (n < 5) {", "    n = n + 2;", "}", "cout << n;"], ["int n = 1;", "while (n < 100) {", "    n = n * 2;", "}", "cout << n;"]],
		7: [["int n = 0;", "while (n < 100) {", "    n = n + 7;", "}", "cout << n << endl;"], ["int n = 123;", "int s = 0;", "while (n > 0) {", "    s = s + n % 10;", "    n = n / 10;", "}", "cout << s << endl;"]],
		8: [["int n = 0;", "int c = 0;", "while (n < 100) {", "    n = n + 3;", "    c++;", "}", "cout << c << endl;"], ["int s = 0;", "int i = 1;", "while (s <= 100) {", "    s = s + i;", "    i++;", "}", "cout << i - 1 << endl;"], ["int n = 100;", "int c = 0;", "while (n > 1) {", "    n = n / 2;", "    c++;", "}", "cout << c << endl;"]],
	},
	"rebuild": {
		1: [["int main()"]],
		2: [["return 0;"]],
		3: [["int x = 1;"]],
		4: [["cout << x << endl;"]],
		5: [["int a = 3;", "int b = 4;", "cout << a + b;"], ["int r = 5;", "cout << r * r * 3 << endl;"]],
		6: [["int a = 3;", "int b = 4;", "int c = a * b;", "cout << c << endl;"], ["int a = 3, b = 5;", "int t = a;", "a = b;", "b = t;", "cout << a << \" \" << b << endl;"]],
		7: [["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "}", "cout << s << endl;"], ["int y = 2024;", "if (y % 400 == 0) {", "    cout << \"leap\";", "} else if (y % 4 == 0 && y % 100 != 0) {", "    cout << \"leap\";", "} else {", "    cout << \"no\";", "}"]],
		8: [["int s = 0;", "for (int i = 0; i <= 100; i++) {", "    s = s + i;", "}", "cout << s << endl;"], ["int h = 35, f = 94;", "for (int r = 0; r <= h; r++) {", "    if (r * 2 + (h - r) * 4 == f) {", "        cout << r << \" \" << h - r << endl;", "    }", "}"], ["for (int n = 100; n <= 999; n++) {", "    int a = n / 100;", "    int b = n / 10 % 10;", "    int c = n % 10;", "    if (a*a*a + b*b*b + c*c*c == n) {", "        cout << n << endl;", "    }", "}"]],
	},
	"general": {
		1: [["int"]],
		2: [["int n = 0;"]],
		3: [["n = n + 1;"]],
		4: [["cout << n << endl;"]],
		5: [["int n = 0;", "n = n + 1;", "cout << n;"], ["int a = 2;", "int b = a * a;", "cout << b;"]],
		6: [["int s = 0;", "for (int i = 0; i < 5; i++) {", "    s = s + i;", "}"], ["int s = 0;", "for (int i = 1; i <= 9; i++) {", "    s = s + i;", "}", "cout << s;"]],
		7: [["int s = 0;", "for (int i = 0; i < 5; i++) {", "    s = s + i;", "}", "cout << s << endl;"], ["int n = 10;", "int s = 0;", "for (int i = 1; i <= n; i++) {", "    s = s + i;", "}", "cout << s << endl;"]],
		8: [["int s = 0;", "for (int i = 1; i <= 100; i++) {", "    s = s + i;", "}", "cout << s << endl;"], ["int c = 0;", "for (int i = 1; i <= 100; i++) {", "    if (i % 7 == 0) {", "        c++;", "    }", "}", "cout << c << endl;"], ["int s = 0;", "for (int i = 1; i <= 100; i += 2) {", "    s = s + i;", "}", "cout << s << endl;"]],
	},
}


## 主题 -> 等级 -> [变体0 的讲解, 变体1 的讲解, ...]（与 FRAG 一一对应）
const TIPS := {
	"whip": {
		1: ["分支的开头：条件成立才执行"],
		2: ["定义一个整数变量 n"],
		3: ["条件成立时 n 加一"],
		4: ["大括号包住要做的事"],
		5: ["超过上限就压回上限", "负数变正数，这就是取绝对值"],
		6: ["用 % 取余判断奇偶", "两个条件同时满足用 &&"],
		7: ["二选一：if 走一条，else 走另一条", "else if 可以接着往下分", "比大小：谁大就输出谁"],
		8: ["循环里套分支：只累加偶数", "用标记变量判断素数", "打擂台：一个个比出最大值"],
	},
	"orbit": {
		1: ["循环的开头：重复做同一件事"],
		2: ["循环变量 i 从 0 开始"],
		3: ["i 自己加一，等价于 i = i + 1"],
		4: ["三个部分：起点、条件、步进"],
		5: ["把 0 到 9 依次打印出来", "循环里先算再输出"],
		6: ["累加：把每次的 i 加进 s", "累乘：这就是阶乘"],
		7: ["算完再输出 1 到 10 的和", "循环也能倒着走，i--", "循环条件里也可以用变量"],
		8: ["0 到 100 里能被 3 整除的数之和", "结果太大就换 long long 装", "循环套循环：打印半个乘法表"],
	},
	"broadcast": {
		1: ["输出的开头：把内容送到屏幕"],
		2: ["先准备一个要输出的数"],
		3: ["两个小于号表示「流向」屏幕"],
		4: ["endl 表示换行"],
		5: ["字符串要加双引号", "可以先把算式算完再输出"],
		6: ["文字和数字可以拼着输出", "一个 cout 能接好几段"],
		7: ["循环里输出，一次发三波", "边输出边算平方"],
		8: ["输出结束后再报一句完成", "经典题：数字之间用逗号隔开，最后不加", "两层循环画一个倒三角"],
	},
	"judgment": {
		1: ["随机数函数：每次结果都可能不同"],
		2: ["准备一个变量装随机数"],
		3: ["取一个随机数存进 r"],
		4: ["% 6 把范围压到 0 到 5，像掷骰子"],
		5: ["掷一次骰子并输出结果", "% 10 + 1 得到 1 到 10"],
		6: ["随机结果参与判断", "掷到 6 才算赢"],
		7: ["随机 + 二选一", "掷两次骰子，把点数加起来"],
		8: ["扔十次硬币，数正面朝上的次数", "掷 20 次，数 6 出了几次", "猜数游戏：告诉玩家猜大了还是猜小了"],
	},
	"blade": {
		1: ["函数的返回值类型"],
		2: ["return 把结果送回去"],
		3: ["函数头：名字、参数、返回类型"],
		4: ["最简单的函数：原样返回"],
		5: ["函数里做一次运算再返回", "求平方的函数"],
		6: ["两个参数的函数", "函数里可以先判断再返回"],
		7: ["自己调用自己，这就是递归", "斐波那契：前两个相加"],
		8: ["用函数算出 1 到 n 的和", "辗转相除求最大公约数", "递归版求和：n 加上前面所有项"],
	},
	"pointer": {
		1: ["星号表示这是一个指针变量"],
		2: ["先有一个普通的整数"],
		3: ["& 取地址，让 p 指向 n"],
		4: ["*p 表示「p 指向的那个值」"],
		5: ["指过去再读出来", "取到的值能直接参与运算"],
		6: ["通过指针改值，n 也跟着变", "经典：交换两个数"],
		7: ["把指针传进函数才能改到外面", "数组名就是首地址"],
		8: ["循环里通过指针累加", "用指针走完整个数组", "传地址进去，外面才真的换了"],
	},
	"volley": {
		1: ["数组：一排编号的格子"],
		2: ["下标从 0 开始，不是 1"],
		3: ["按下标取出来"],
		4: ["用循环走遍每个下标"],
		5: ["定义时直接给初值", "最后一个的下标是 2 不是 3"],
		6: ["遍历数组全部输出", "倒着遍历：从 4 走到 0"],
		7: ["把数组里的数全加起来", "打擂台：找出数组里的最大值", "原地把每个元素翻倍"],
		8: ["只累加符合条件的元素", "数一数数组里有几个偶数", "从键盘读入五个数，输出平均数"],
	},
	"gc": {
		1: ["先准备一个计数变量"],
		2: ["申请十个整数的空间"],
		3: ["按下标写入"],
		4: ["循环覆盖全部下标"],
		5: ["把数组全部清零", "按下标依次填入 1 到 5"],
		6: ["后面的数由前面两个相加得到", "把数组一个一个搬过去"],
		7: ["算出最后一个数并输出", "跳过空格子，只数有值的"],
		8: ["存平方数，同时累加", "两个循环：先把表填好，再求和", "边生成边累加"],
	},
	"buffer": {
		1: ["下标从 0 开始"],
		2: ["循环条件：不能等于 10"],
		3: ["先判断再取，防止越界"],
		4: ["条件成立就一直做"],
		5: ["while 版本的计数循环", "少了 i++ 就永远出不来"],
		6: ["写满十格，一格不多", "用 while 也能填满数组"],
		7: ["边写边数，最后输出个数", "经典题：每次砍掉最后一位，数位数"],
		8: ["越界是 bug，条件要写死", "经典题：把数字倒过来", "break：够了就提前跳出循环"],
	},
	"breakpoint": {
		1: ["准备一个观察用的变量"],
		2: ["手动往前推一步"],
		3: ["把当前值打印出来看"],
		4: ["输出时带上说明文字"],
		5: ["一步一步打点", "输出时带上变量的名字"],
		6: ["每轮循环都留一个记号", "把每一步的结果都打出来"],
		7: ["每加一次就打印，看过程", "看最大值是怎么一点点变大的"],
		8: ["把每一步和最后结果都打出来", "打印每一步的阶乘", "过程打完，最后算个平均"],
	},
	"forever": {
		1: ["条件成立就一直重复"],
		2: ["准备一个会被改变的变量"],
		3: ["条件写在括号里"],
		4: ["别忘让 n 变大，否则停不下来"],
		5: ["循环体必须能推进条件", "倒着数也能停下来"],
		6: ["步长可以是 2", "每次翻倍，长得非常快"],
		7: ["一直加到超过 100", "经典题：把每一位数字加起来"],
		8: ["顺便数一共加了多少次", "一直加到刚好超过 100，看加到几", "每次减半，数要减几次"],
	},
	"rebuild": {
		1: ["程序从 main 开始执行"],
		2: ["返回 0 表示正常结束"],
		3: ["在 main 里定义变量"],
		4: ["输出后换行"],
		5: ["先算再输出", "套公式算圆的面积近似值"],
		6: ["中间结果存进新变量", "交换两个变量要借一个临时变量"],
		7: ["完整的累加程序", "闰年：被 400 整除，或被 4 整除但不被 100 整除"],
		8: ["求 0 到 100 所有整数的和", "鸡兔同笼：一只一只试，试到脚数对上", "水仙花数：各位立方和刚好等于自己"],
	},
	"general": {
		1: ["整数类型"],
		2: ["定义变量并给初值"],
		3: ["自增的写法"],
		4: ["输出并换行"],
		5: ["改完立刻看结果", "中间变量装一下再输出"],
		6: ["小循环做累加", "1 到 9 的和"],
		7: ["累加后输出", "用变量控制循环要走多少次"],
		8: ["求 1 到 100 所有整数的和", "数 100 以内有几个 7 的倍数", "步长改成 2：只走奇数"],
	},
}


## 升级项 id -> 主题名。武器用自己的 id；被动、进化、未登记的都走 general。
const THEME_OF := {
	"whip": "whip",
	"orbit": "orbit",
	"broadcast": "broadcast",
	"judgment": "judgment",
	"blade": "blade",
	"pointer": "pointer",
	"volley": "volley",
	"gc": "gc",
	"buffer": "buffer",
	"breakpoint": "breakpoint",
	"forever": "forever",
	"rebuild": "rebuild",
}


## 取某主题某等级的「题目池」。主题没有这一级就退回 general，再没有就是空。
static func _pool(table: Dictionary, theme: String, level: int) -> Array:
	var by_lv: Dictionary = table.get(theme, {})
	if not by_lv.has(level):
		by_lv = table.get("general", {})
	if not by_lv.has(level):
		return []
	return by_lv[level] as Array


## 这一级一共有几道变体（出题端用它决定随机范围）
static func variants(theme: String, level: int) -> int:
	return _pool(FRAG, theme, level).size()


## 取某主题某等级第 idx 道变体的代码行。
## idx 越界一律退回第 0 道 —— 出题端宁可重复，也不能崩在升级那一刻。
static func frag(theme: String, level: int, idx: int = 0) -> Array:
	var p := _pool(FRAG, theme, level)
	if p.is_empty():
		return []
	var i := idx
	if i < 0 or i >= p.size():
		i = 0
	return (p[i] as Array).duplicate()


## 取对应变体的讲解文案
static func tip(theme: String, level: int, idx: int = 0) -> String:
	var p := _pool(TIPS, theme, level)
	if p.is_empty():
		return ""
	var i := idx
	if i < 0 or i >= p.size():
		i = 0
	return str(p[i])


## 升级项 id 对应的主题
static func theme_of(upgrade_id: String) -> String:
	if THEME_OF.has(upgrade_id):
		return str(THEME_OF[upgrade_id])
	return "general"
