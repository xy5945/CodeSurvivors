class_name CodeChallengeDB
extends RefCounted
##
## 升级打码的 C++ 题库（纯数据，由 tools 下的生成脚本产出，不要手改）。
##
## 只存「标准档」片段，轻松档/严格档由 CodeChallenge 在运行时派生：
##   轻松 = 去掉纯括号行后最长的那一行
##   严格 = Lv6 及以上再包一层 main 结构
##
## 代码一律 ASCII（等宽字体只子集了 ASCII），中文讲解放 TIPS。
## 缩进统一 4 空格。


## 主题 -> 等级 -> 代码行数组
const FRAG := {
	"whip": {
		1: ["if"],
		2: ["int n = 0;"],
		3: ["if (n > 0) n++;"],
		4: ["if (n > 0) { n--; }"],
		5: ["if (n > 10) {", "    n = 10;", "}"],
		6: ["if (n % 2 == 0) {", "    cout << \"even\";", "} else {", "    cout << \"odd\";", "}"],
		7: ["int n = 7;", "if (n % 2 == 0) {", "    cout << \"even\";", "} else {", "    cout << \"odd\";", "}"],
		8: ["int n = 0;", "for (int i = 1; i <= 10; i++) {", "    if (i % 2 == 0) {", "        n = n + i;", "    }", "}", "cout << n;"],
	},
	"orbit": {
		1: ["for"],
		2: ["int i = 0;"],
		3: ["i++;"],
		4: ["for (int i = 0; i < 10; i++)"],
		5: ["for (int i = 0; i < 10; i++) {", "    cout << i;", "}"],
		6: ["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "}"],
		7: ["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "}", "cout << s;"],
		8: ["int s = 0;", "for (int i = 0; i <= 100; i++) {", "    if (i % 3 == 0) {", "        s = s + i;", "    }", "}", "cout << s << endl;"],
	},
	"broadcast": {
		1: ["cout"],
		2: ["int x = 1;"],
		3: ["cout << x;"],
		4: ["cout << x << endl;"],
		5: ["cout << \"hi\";", "cout << endl;"],
		6: ["int x = 5;", "cout << \"x = \";", "cout << x << endl;"],
		7: ["for (int i = 0; i < 3; i++) {", "    cout << \"wave \" << i << endl;", "}"],
		8: ["int n = 3;", "for (int i = 1; i <= n; i++) {", "    cout << \"wave \" << i << endl;", "}", "cout << \"done\" << endl;"],
	},
	"judgment": {
		1: ["rand"],
		2: ["int r = 0;"],
		3: ["r = rand();"],
		4: ["int r = rand() % 6;"],
		5: ["int r = rand() % 6;", "cout << r;"],
		6: ["int r = rand() % 100;", "if (r < 50) {", "    cout << \"low\";", "}"],
		7: ["int r = rand() % 100;", "if (r < 50) {", "    cout << \"low\";", "} else {", "    cout << \"high\";", "}"],
		8: ["int n = 0;", "for (int i = 0; i < 10; i++) {", "    if (rand() % 2 == 0) {", "        n++;", "    }", "}", "cout << n << endl;"],
	},
	"blade": {
		1: ["int"],
		2: ["return 0;"],
		3: ["int f(int n)"],
		4: ["int f(int n) { return n; }"],
		5: ["int f(int n) {", "    return n * 2;", "}"],
		6: ["int add(int a, int b) {", "    return a + b;", "}"],
		7: ["int f(int n) {", "    if (n <= 1) {", "        return 1;", "    }", "    return n * f(n - 1);", "}"],
		8: ["int sum(int n) {", "    int s = 0;", "    for (int i = 1; i <= n; i++) {", "        s = s + i;", "    }", "    return s;", "}"],
	},
	"pointer": {
		1: ["int* p;"],
		2: ["int n = 5;"],
		3: ["int* p = &n;"],
		4: ["cout << *p;"],
		5: ["int n = 5;", "int* p = &n;", "cout << *p;"],
		6: ["int n = 5;", "int* p = &n;", "*p = *p + 1;", "cout << n;"],
		7: ["void up(int* p) {", "    *p = *p + 1;", "}"],
		8: ["int n = 0;", "int* p = &n;", "for (int i = 0; i < 5; i++) {", "    *p = *p + i;", "}", "cout << n << endl;"],
	},
	"volley": {
		1: ["int a[5];"],
		2: ["a[0] = 1;"],
		3: ["cout << a[0];"],
		4: ["for (int i = 0; i < 5; i++)"],
		5: ["int a[5] = {1, 2, 3, 4, 5};", "cout << a[0];"],
		6: ["int a[5] = {1, 2, 3, 4, 5};", "for (int i = 0; i < 5; i++) {", "    cout << a[i];", "}"],
		7: ["int a[5] = {1, 2, 3, 4, 5};", "int s = 0;", "for (int i = 0; i < 5; i++) {", "    s = s + a[i];", "}", "cout << s;"],
		8: ["int a[5] = {2, 4, 6, 8, 10};", "int s = 0;", "for (int i = 0; i < 5; i++) {", "    if (a[i] % 4 == 0) {", "        s = s + a[i];", "    }", "}", "cout << s << endl;"],
	},
	"gc": {
		1: ["int n = 0;"],
		2: ["int a[10];"],
		3: ["a[i] = 0;"],
		4: ["for (int i = 0; i < 10; i++)"],
		5: ["int a[10];", "for (int i = 0; i < 10; i++) {", "    a[i] = 0;", "}"],
		6: ["int a[10];", "a[0] = 1;", "a[1] = 1;", "for (int i = 2; i < 10; i++) {", "    a[i] = a[i - 1] + a[i - 2];", "}"],
		7: ["int a[10];", "a[0] = 1;", "a[1] = 1;", "for (int i = 2; i < 10; i++) {", "    a[i] = a[i - 1] + a[i - 2];", "}", "cout << a[9];"],
		8: ["int a[10] = {0};", "int n = 0;", "for (int i = 0; i < 10; i++) {", "    a[i] = i * i;", "    n = n + a[i];", "}", "cout << n << endl;"],
	},
	"buffer": {
		1: ["int i = 0;"],
		2: ["i < 10;"],
		3: ["if (i < 10)"],
		4: ["while (i < 10)"],
		5: ["int i = 0;", "while (i < 10) {", "    i++;", "}"],
		6: ["int a[10];", "for (int i = 0; i < 10; i++) {", "    a[i] = i;", "}"],
		7: ["int a[10];", "int n = 0;", "for (int i = 0; i < 10; i++) {", "    a[i] = i * 2;", "    n++;", "}", "cout << n;"],
		8: ["int a[10];", "int s = 0;", "for (int i = 0; i < 10; i++) {", "    a[i] = i + 1;", "    if (a[i] > 5) {", "        s = s + a[i];", "    }", "}", "cout << s << endl;"],
	},
	"breakpoint": {
		1: ["int k = 0;"],
		2: ["k = k + 1;"],
		3: ["cout << k;"],
		4: ["cout << \"step \" << k;"],
		5: ["cout << \"step 1\";", "cout << endl;"],
		6: ["for (int i = 0; i < 3; i++) {", "    cout << \"step \" << i << endl;", "}"],
		7: ["int s = 0;", "for (int i = 1; i <= 5; i++) {", "    s = s + i;", "    cout << s << endl;", "}"],
		8: ["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "    cout << i << \" : \" << s << endl;", "}", "cout << \"sum = \" << s << endl;"],
	},
	"forever": {
		1: ["while"],
		2: ["int n = 0;"],
		3: ["while (n < 5)"],
		4: ["while (n < 5) { n++; }"],
		5: ["while (n < 5) {", "    n++;", "}"],
		6: ["int n = 0;", "while (n < 5) {", "    n = n + 2;", "}", "cout << n;"],
		7: ["int n = 0;", "while (n < 100) {", "    n = n + 7;", "}", "cout << n << endl;"],
		8: ["int n = 0;", "int c = 0;", "while (n < 100) {", "    n = n + 3;", "    c++;", "}", "cout << c << endl;"],
	},
	"rebuild": {
		1: ["int main()"],
		2: ["return 0;"],
		3: ["int x = 1;"],
		4: ["cout << x << endl;"],
		5: ["int a = 3;", "int b = 4;", "cout << a + b;"],
		6: ["int a = 3;", "int b = 4;", "int c = a * b;", "cout << c << endl;"],
		7: ["int s = 0;", "for (int i = 1; i <= 10; i++) {", "    s = s + i;", "}", "cout << s << endl;"],
		8: ["int s = 0;", "for (int i = 0; i <= 100; i++) {", "    s = s + i;", "}", "cout << s << endl;"],
	},
	"general": {
		1: ["int"],
		2: ["int n = 0;"],
		3: ["n = n + 1;"],
		4: ["cout << n << endl;"],
		5: ["int n = 0;", "n = n + 1;", "cout << n;"],
		6: ["int s = 0;", "for (int i = 0; i < 5; i++) {", "    s = s + i;", "}"],
		7: ["int s = 0;", "for (int i = 0; i < 5; i++) {", "    s = s + i;", "}", "cout << s << endl;"],
		8: ["int s = 0;", "for (int i = 0; i <= 100; i++) {", "    s = s + i;", "}", "cout << s << endl;"],
	},
}


## 主题 -> 等级 -> 一句话讲解（显示在代码块外，用中文字体）
const TIPS := {
	"whip": {
		1: "分支的开头：条件成立才执行",
		2: "定义一个整数变量 n",
		3: "条件成立时 n 加一",
		4: "大括号包住要做的事",
		5: "超过上限就压回上限",
		6: "用 % 取余判断奇偶",
		7: "二选一：if 走一条，else 走另一条",
		8: "循环里套分支：只累加偶数",
	},
	"orbit": {
		1: "循环的开头：重复做同一件事",
		2: "循环变量 i 从 0 开始",
		3: "i 自己加一，等价于 i = i + 1",
		4: "三个部分：起点、条件、步进",
		5: "把 0 到 9 依次打印出来",
		6: "累加：把每次的 i 加进 s",
		7: "算完再输出 1 到 10 的和",
		8: "0 到 100 里能被 3 整除的数之和",
	},
	"broadcast": {
		1: "输出的开头：把内容送到屏幕",
		2: "先准备一个要输出的数",
		3: "两个小于号表示「流向」屏幕",
		4: "endl 表示换行",
		5: "字符串要加双引号",
		6: "文字和数字可以拼着输出",
		7: "循环里输出，一次发三波",
		8: "输出结束后再报一句完成",
	},
	"judgment": {
		1: "随机数函数：每次结果都可能不同",
		2: "准备一个变量装随机数",
		3: "取一个随机数存进 r",
		4: "% 6 把范围压到 0 到 5，像掷骰子",
		5: "掷一次骰子并输出结果",
		6: "随机结果参与判断",
		7: "随机 + 二选一",
		8: "扔十次硬币，数正面朝上的次数",
	},
	"blade": {
		1: "函数的返回值类型",
		2: "return 把结果送回去",
		3: "函数头：名字、参数、返回类型",
		4: "最简单的函数：原样返回",
		5: "函数里做一次运算再返回",
		6: "两个参数的函数",
		7: "自己调用自己，这就是递归",
		8: "用函数算出 1 到 n 的和",
	},
	"pointer": {
		1: "星号表示这是一个指针变量",
		2: "先有一个普通的整数",
		3: "& 取地址，让 p 指向 n",
		4: "*p 表示「p 指向的那个值」",
		5: "指过去再读出来",
		6: "通过指针改值，n 也跟着变",
		7: "把指针传进函数才能改到外面",
		8: "循环里通过指针累加",
	},
	"volley": {
		1: "数组：一排编号的格子",
		2: "下标从 0 开始，不是 1",
		3: "按下标取出来",
		4: "用循环走遍每个下标",
		5: "定义时直接给初值",
		6: "遍历数组全部输出",
		7: "把数组里的数全加起来",
		8: "只累加符合条件的元素",
	},
	"gc": {
		1: "先准备一个计数变量",
		2: "申请十个整数的空间",
		3: "按下标写入",
		4: "循环覆盖全部下标",
		5: "把数组全部清零",
		6: "后面的数由前面两个相加得到",
		7: "算出最后一个数并输出",
		8: "存平方数，同时累加",
	},
	"buffer": {
		1: "下标从 0 开始",
		2: "循环条件：不能等于 10",
		3: "先判断再取，防止越界",
		4: "条件成立就一直做",
		5: "while 版本的计数循环",
		6: "写满十格，一格不多",
		7: "边写边数，最后输出个数",
		8: "越界是 bug，条件要写死",
	},
	"breakpoint": {
		1: "准备一个观察用的变量",
		2: "手动往前推一步",
		3: "把当前值打印出来看",
		4: "输出时带上说明文字",
		5: "一步一步打点",
		6: "每轮循环都留一个记号",
		7: "每加一次就打印，看过程",
		8: "把每一步和最后结果都打出来",
	},
	"forever": {
		1: "条件成立就一直重复",
		2: "准备一个会被改变的变量",
		3: "条件写在括号里",
		4: "别忘让 n 变大，否则停不下来",
		5: "循环体必须能推进条件",
		6: "步长可以是 2",
		7: "一直加到超过 100",
		8: "顺便数一共加了多少次",
	},
	"rebuild": {
		1: "程序从 main 开始执行",
		2: "返回 0 表示正常结束",
		3: "在 main 里定义变量",
		4: "输出后换行",
		5: "先算再输出",
		6: "中间结果存进新变量",
		7: "完整的累加程序",
		8: "求 0 到 100 所有整数的和",
	},
	"general": {
		1: "整数类型",
		2: "定义变量并给初值",
		3: "自增的写法",
		4: "输出并换行",
		5: "改完立刻看结果",
		6: "小循环做累加",
		7: "累加后输出",
		8: "求 0 到 100 所有整数的和",
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


## 取某主题某等级的代码行（没有就退回 general 的同级，再没有就空数组）
static func frag(theme: String, level: int) -> Array:
	var by_lv: Dictionary = FRAG.get(theme, {})
	if not by_lv.has(level):
		by_lv = FRAG.get("general", {})
	if not by_lv.has(level):
		return []
	return (by_lv[level] as Array).duplicate()


## 取讲解文案
static func tip(theme: String, level: int) -> String:
	var by_lv: Dictionary = TIPS.get(theme, {})
	var s := ""
	if by_lv.has(level):
		s = str(by_lv[level])
	if s == "":
		var g: Dictionary = TIPS.get("general", {})
		if g.has(level):
			s = str(g[level])
	return s


## 升级项 id 对应的主题
static func theme_of(upgrade_id: String) -> String:
	if THEME_OF.has(upgrade_id):
		return str(THEME_OF[upgrade_id])
	return "general"
