--[[
  主题工作室 Theme Studio for trime2  —— 事件通道版
  核心思路（完全按 trime2 源码加载主题 + KeyView 真实机制）：
   * 加载 = 沙箱真跑主题 Lua（main.lua / styles / keyboards），
       inherit / dofile / loadfile / require / env 元表继承链全部复刻，
       拿到与输入法启动后完全一致的样式表与键盘表。
   * 预览 = 按 Style/KeyStyle 的 __index 继承链逐字段取值渲染：
       背景(色/图)/圆角/描边/阴影/字体/字号/颜色/重力/偏移/留白/内边距，
       并复刻 KeyView.initKey 的角标规则与互斥隐藏。
   * 一个按键 = 6 个真实事件通道：click / long_click /
       swipe_up / swipe_down / swipe_left / swipe_right。
       交互严格照搬 KeyView.onTouchEvent + handleSwipeEvent 的手势判定：
         - 键内任意位置短按抬起 → click（点击还是点击）
         - 按住超过 long_click_time → long_click
         - 手指滑出按键边界超过 12dp，按主导轴 → swipe_up/down/left/right（上滑还是上滑）
       手势识别后，只打开该通道的【真实 event 字段 + 相关样式】编辑器；
       角标也可直接点击编辑对应通道。每一项都回显当前值，可改。
       - click      → 键主样式 key / functional / enter …（含 pressed）
       - long_click → key.long_click（含 pressed.long_click）
       - swipe_*    → key.hint / key.hint.up|down|left|right
   * 所有改动先在内存累积，点【保存主题】时二选一：
       - 覆盖原主题：把样式/键盘改动直接写回当前主题文件（自动备份为 .ts.bak）
       - 生成新主题：复制整份主题（字体/图片/脚本/键盘），再写回改动并改名为新主题
  部署：rime/tools/主题工作室/main.lua（同目录 init.lua）
--]]

-- 【r27.33】角标水平微调（dp，正=右移）。仅作用于 long_click 的 label 与按键 hint
-- （S.id=="click"，即 stPath="hint" 那类）——这两类实测偏左；上下左右滑动 hint
-- （swipe_up/down/left/right）本来就正常，一律不偏移。也不影响 click 主标签。
-- 默认 1dp；若觉得偏了直接改这个数字即可（含负数）。
CORNER_X_NUDGE_DP = 1

import "android.view.*"
import "android.widget.*"
import "android.graphics.*"
import "android.graphics.drawable.*"
import "android.text.*"
import "android.text.style.*"
-- ImageSpan/SpannableString 兜底：LuaJ 禁止对 import 注入的类名做全局赋值（
-- 报 "can not assignment 'ImageSpan'"），故只用【局部别名】承接，缺类时再用 bindClass 补。
local _ImageSpan = ImageSpan
local _SpannableString = SpannableString
local _Spannable = Spannable
if _ImageSpan == nil then pcall(function() _ImageSpan = luajava.bindClass("android.text.style.ImageSpan") end) end
if _SpannableString == nil then pcall(function() _SpannableString = luajava.bindClass("android.text.SpannableString") end) end
if _Spannable == nil then pcall(function() _Spannable = luajava.bindClass("android.text.Spannable") end) end
local _FgSpan = ForegroundColorSpan
if _FgSpan == nil then pcall(function() _FgSpan = luajava.bindClass("android.text.style.ForegroundColorSpan") end) end
-- androlua 专属类：import 必须在【顶层】直接调用（它依赖调用者环境绑定全局名，
-- 包进 pcall 闭包会导致 LuaDialog/LuaAdapter 绑定不到全局 → onClick 报 call nil）。
import "com.androlua.LuaDialog"
import "com.androlua.LuaAdapter"
if LuaDialog == nil then pcall(function() LuaDialog = luajava.bindClass("com.androlua.LuaDialog") end) end
if LuaAdapter == nil then pcall(function() LuaAdapter = luajava.bindClass("com.androlua.LuaAdapter") end) end

local Config = nil
pcall(function() Config = luajava.bindClass("com.osfans.trime.Config") end)
-- 【崩溃根因修复 / 通用安全模式】
-- 主题工作室与输入法虽然同进程，但 Rime native 引擎、ThemeManager.getKeyboard、
-- Function.loadString(LuaApp.getInstance(),…) 都必须在“输入法引擎已启动、实例已就绪”
-- 的状态下才安全。工具进程里引擎根本没启动，直接调这些方法会在 native 层写入污染状态，
-- 表现就是“打开工具、等几秒输入法整个闪退”——native 崩溃 pcall 根本挡不住。
-- 因此这里【彻底不绑定】这些 native/实例类。当前主题、配色、键盘一律走 Config 的
-- 纯 Java 静态偏好读取（getTheme/getStyle/getKeyboard/getDataDir）：只读 SharedPreferences，
-- 不触碰 native 引擎，物理上不可能污染输入法进程。
-- 变量保留为 nil（下面读取处均有 if 判断），确保旧逻辑不会因 nil 索引报错。
-- 顶层 Java 调用全部 pcall 包裹 + 纯 Lua 兜底：任何一步返回 null 都不再抛 load 期 NPE
local OsHandler = nil
pcall(function() OsHandler = luajava.bindClass("android.os.Handler") end)
local uiHandler = nil
pcall(function() if OsHandler then uiHandler = OsHandler() end end)
if not uiHandler then
    -- 极端情况下 Handler 不可用：退化为直接执行，保证后续 post/postDelayed 不会因 nil 中断
    uiHandler = {
        post = function(f) if type(f) == "function" then pcall(f) end end,
        postDelayed = function(f) if type(f) == "function" then pcall(f) end end,
        removeCallbacks = function() end,
    }
end
local dm = nil
pcall(function() dm = activity.getResources().getDisplayMetrics() end)
if not dm then dm = { density = 2, widthPixels = 1080, heightPixels = 1920 } end

function dp(n) return math.floor(n * dm.density + 0.5) end
-- Toast 必须包 pcall：工具界面已销毁（用户按返回键退出）后，任何延迟回调里再弹
-- Toast 都会抛 BadTokenException / "not attached to window"。这条异常一旦逃到
-- Handler 的 Runnable 里就是进程级未捕获异常 —— 同进程的输入法一起挂。
function toast(msg)
    pcall(function() Toast.makeText(activity, msg, Toast.LENGTH_SHORT).show() end)
end

-- 【崩溃取证】把 Java 层"未捕获异常"的完整堆栈写进 /sdcard/Download/主题工作室_崩溃.txt。
-- 判断价值：这条文件里有记录 → 是 Java 异常（NPE / BadToken / IllegalState 等）；
--            没有记录却进程消失 → 是 native 崩溃或被系统杀（ANR/OOM），两者处置完全不同。
--
-- 【重要·不要越权】工具与输入法是【同一个进程】，这里的 handler 是进程级、全局的。
-- 旧实现记录完直接 Process.killProcess()，等于把「工具里一次可恢复的 Java 异常」
-- 升级成「整个输入法被杀」——用户看到的就是闪退。现改为：
--   ① 只记录，绝不主动杀进程；
--   ② 记录完把异常原样转交给安装前的 handler（系统默认 / 输入法自己的上报器），
--      后续行为与没装这个工具时完全一致，不改变任何进程级语义。
pcall(function()
    local JThread   = luajava.bindClass("java.lang.Thread")
    local StringWriter = luajava.bindClass("java.io.StringWriter")
    local PrintWriter  = luajava.bindClass("java.io.PrintWriter")
    local prevHandler = nil
    pcall(function() prevHandler = JThread.getDefaultUncaughtExceptionHandler() end)
    local handler = luajava.createProxy("java.lang.Thread$UncaughtExceptionHandler", {
        uncaughtException = function(t, e)
            pcall(function()
                local sw = StringWriter()
                local pw = PrintWriter(sw)
                pcall(function() e:printStackTrace(pw) end)
                pcall(function() pw:flush() end)
                local body = tostring(sw:toString())
                local f = io.open("/sdcard/Download/主题工作室_崩溃.txt", "a")
                if f then
                    f:write("\n===== " .. os.date("%m-%d %H:%M:%S") .. " JAVA UNCAUGHT =====\n"
                        .. body .. "\n")
                    f:close()
                end
            end)
            -- 转交原 handler：不吞、不杀、不改变退出路径
            if prevHandler then
                pcall(function() prevHandler:uncaughtException(t, e) end)
            end
        end
    })
    -- 已经是自己的 handler（脚本被重跑）就不再套一层，避免多重转发
    if handler and prevHandler ~= handler then
        JThread.setDefaultUncaughtExceptionHandler(handler)
    end
end)

-- 工具内报错日志（logcat 抓不到时的兜底）
local errLog = {}
function logErr(ctx, e)
    table.insert(errLog, 1, os.date("%H:%M:%S") .. " [" .. ctx .. "] " .. tostring(e))
    if #errLog > 30 then table.remove(errLog) end
end

-- 打开这个文件，看到最后停在哪个阶段 → 精确判断“加载过久崩在哪一步”。文件放工具目录下。
local BOOT_LOG = nil
local bootT0 = os.clock()
function copyText(s)
    local ok = pcall(function()
        local cm = activity.getSystemService("clipboard")
        cm.setText(s)
    end)
    if ok then toast("已复制到剪贴板") else toast("复制失败") end
end

-- ========== 文件工具 ==========
function readFile(p)
    local f = io.open(p, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end
-- 只读前 n 字节：按 name= 反查键盘文件只要看头部，没必要把整份脚本读进内存。
-- 启动路径上会扫整个 keyboards/ 目录，整份读取时（大主题几十个脚本）会明显拖慢首屏。
function readFileHead(p, n)
    local f = io.open(p, "r")
    if not f then return nil end
    local s = f:read(n or 32768)
    f:close()
    return s
end
-- 去掉 Lua 注释（单行 -- 与长注释 --[=[ ... ]=]），字符串原样保留，换行保留以维持行号。
-- 注释内容替换成等长空格——这样后续对 name=/rows= 的匹配位置、诊断行号与原文完全一致。
-- 所有"从脚本文本读 name="的地方都必须先过这一层，否则注释里的示例 name 会被当真值。
function stripLuaComments(src)
    if type(src) ~= "string" then return "" end
    local out, i, n = {}, 1, #src
    local function blank(s) return (s:gsub("[^\n]", " ")) end
    while i <= n do
        local c = src:sub(i, i)
        if c == "-" and src:sub(i + 1, i + 1) == "-" then
            -- 长注释 --[=*[
            local b = i + 2
            if src:sub(b, b) == "[" then
                local j = b + 1
                while src:sub(j, j) == "=" do j = j + 1 end
                if src:sub(j, j) == "[" then
                    local close = "]" .. src:sub(b + 1, j - 1) .. "]"
                    local e = src:find(close, j + 1, true)
                    local stop = e and (e + #close - 1) or n
                    out[#out + 1] = blank(src:sub(i, stop))
                    i = stop + 1
                else
                    local e = src:find("\n", i, true) or (n + 1)
                    out[#out + 1] = blank(src:sub(i, e - 1)); i = e
                end
            else
                local e = src:find("\n", i, true) or (n + 1)
                out[#out + 1] = blank(src:sub(i, e - 1)); i = e
            end
        elseif c == '"' or c == "'" then
            -- 普通字符串：原样扫到闭合引号（含反斜杠转义），里面的 -- 不是注释
            local q, j = c, i + 1
            while j <= n do
                local d = src:sub(j, j)
                if d == "\\" then j = j + 2
                elseif d == q then j = j + 1 break
                else j = j + 1 end
            end
            out[#out + 1] = src:sub(i, j - 1); i = j
        elseif c == "[" then
            -- 长字符串 [[...]] / [=[...]=]：原样保留
            local j = i + 1
            while src:sub(j, j) == "=" do j = j + 1 end
            if src:sub(j, j) == "[" then
                local close = "]" .. src:sub(i + 1, j - 1) .. "]"
                local e = src:find(close, j + 1, true)
                local stop = e and (e + #close - 1) or n
                out[#out + 1] = src:sub(i, stop); i = stop + 1
            else
                out[#out + 1] = c; i = i + 1
            end
        else
            out[#out + 1] = c; i = i + 1
        end
    end
    return table.concat(out)
end
function writeFile(p, s)
    local f, err = io.open(p, "w")
    if not f then return false, err end
    f:write(s); f:close(); return true
end
function fileExists(p)
    local f = io.open(p, "r")
    if f then f:close() return true end
    return false
end
function isDir(p)
    local File = luajava.bindClass("java.io.File")
    local f = File(p)
    return f.exists() and f.isDirectory()
end
function mkdirs(p)
    pcall(function() luajava.bindClass("java.io.File")(p).mkdirs() end)
end
function listDir(p)
    local File = luajava.bindClass("java.io.File")
    local dir = File(p)
    local out = {}
    if dir.exists() and dir.isDirectory() then
        local files = dir.listFiles()
        if files then
            for i = 0, files.length - 1 do table.insert(out, files[i].getName()) end
        end
    end
    table.sort(out)
    return out
end

-- 二进制复制单文件（图片/字体/音频必须按字节复制）
function copyFileBin(src, dst)
    local fin = io.open(src, "rb")
    if not fin then return false end
    local fout = io.open(dst, "wb")
    if not fout then fin:close() return false end
    local n
    repeat
        n = fin:read(8192)
        if n then fout:write(n) end
    until not n
    fin:close(); fout:close()
    return true
end

-- 递归复制整个目录（新主题全资源的地基）
function copyDirRecursive(src, dst)
    if not isDir(src) then return false, "源目录不存在" end
    mkdirs(dst)
    for _, name in ipairs(listDir(src)) do
        if name ~= "." and name ~= ".." then
            local s = src .. "/" .. name
            local d = dst .. "/" .. name
            if isDir(s) then
                local ok, e = copyDirRecursive(s, d)
                if not ok then return false, e end
            else
                if not copyFileBin(s, d) then return false, "复制失败: " .. name end
            end
        end
    end
    return true
end

-- ========== 沙箱加载 Lua（真跑一遍拿到最终配置表，复刻 trime2 mColor 环境链） ==========
local sandboxLastError = nil
local autoInjectedGlobals = {}  -- 记录为真机独有、沙箱补齐的全局（诊断用）
local requiredModules = {}       -- 记录本次 require 链加载到的模块（诊断用）
local diagSourceLines = {}       -- 记录"文件:行号 → 源码"，供诊断面板显示
local kbdParseDiag = {}          -- 键盘静态解析诊断：记录候选文件里 rows 相关的源码行
local sandboxRealObjectsIsolated = false  -- 本次沙箱是否已把真实输入法对象换成安全桩（诊断用）
local sandboxBlockedClasses = {}         -- 访问源头被拦截为安全桩的 Java 类名（诊断用）

-- ===== nil 访问兜底智能表：配色脚本 randomColor 的 colors 参数在沙箱里为 nil =====
-- #它 = 一个合理长度；它[n]/它.key = 默认颜色值。这样 randomColor 既不会 #nil/index nil 崩，
-- 也不会返回 nil 颜色（nil 颜色会让按键背景变黑）。对合法非 nil 值 x or __nilSafe == x 无影响。
-- 默认色用不透明白 0xFFFFFFFF（与真机按键 view 白底一致），并给不同索引一点色差避免单调。
-- 关键：__nilSafe 本身做成真实数组（含 5 个元素），这样标准 Lua5.1 与 LuaJIT 的 # 都返回
-- 真实长度，不依赖 __len 元方法（标准 5.1 对表忽略 __len，可能导致 # = 0 → math.random 空区间）。
local nilSafeColors = { 0xFFFFFFFF, 0xFFF8F9FA, 0xFFF1F3F4, 0xFFE8EAED, 0xFFF5F5F5 }
local __nilSafe = setmetatable({ nilSafeColors[1], nilSafeColors[2], nilSafeColors[3], nilSafeColors[4], nilSafeColors[5] }, {
    __index = function(_, k)
        if type(k) == "number" then
            if k >= 1 and k <= #nilSafeColors then return nilSafeColors[k] end
            return nilSafeColors[((k - 1) % #nilSafeColors) + 1]
        end
        return nilSafeColors[1]
    end,
    __call = function() return nilSafeColors[1] end,
    __tostring = function() return "" end,
})

-- ===== 安全桩：任何调用/索引/运算/比较都落到桩上成为 no-op =====
-- 提到文件级，供 sandboxLoad 注入、以及 execWithAutoGlobal 处理 coercion error 时共用。
-- 关键点：真机 Android/Luaj 全局（如 PreferenceManager、ThemeManager、Rime）若被主题脚本
-- 通过某条路径拿到"真实 Java 类"，再用安全桩 this/context 作参数调用真实方法，会抛
-- "coercion error ... got org.luaj.LuaTable"（类型不匹配）。把这些真实类覆盖成安全桩即可。
-- 【防 OOM】安全桩改为“全局共享单实例”：桩的任何操作都是 no-op，本身无需区分身份。
-- 旧实现每次 __index/__call 都 makeSafeStub() 新建表和元表，脚本里一次链式调用或循环
-- 就能生成海量对象 → 内存暴涨 → 进程被杀（加载一段时间后闪退）。共享单例后对象数恒定。
local _sharedSafeStub = nil
function makeSafeStub()
    if _sharedSafeStub then return _sharedSafeStub end
    local s = {}
    local mt = {}
    local function z() return 0 end
    mt.__index = function(_, k)
        if k == "__isSafeStub" then return true end
        return _sharedSafeStub  -- 任何属性访问都返回同一个桩，不再逐个 key 缓存新建
    end
    mt.__newindex = function() end
    mt.__call = function() return _sharedSafeStub end
    mt.__add = z; mt.__sub = z; mt.__mul = z; mt.__div = z
    mt.__mod = z; mt.__pow = z
    mt.__concat = function() return "" end
    mt.__eq = function() return false end
    mt.__lt = function() return false end
    mt.__le = function() return false end
    mt.__unm = z
    mt.__len = function() return 0 end
    mt.__tostring = function() return "" end
    setmetatable(s, mt)
    _sharedSafeStub = s
    return s
end

-- ===== 【通用·源码级 #nil 容错】文件级工具（sandboxLoad 编译前一次性预处理） =====
-- 可靠的行分割（gmatch("([^\n]*)") 在部分 Lua 实现会产生空匹配导致行号错位）
function splitLines(s)
    s = tostring(s or "")
    local lines, pos = {}, 1
    while true do
        local nl = s:find("\n", pos, true)
        if not nl then lines[#lines + 1] = s:sub(pos); break end
        lines[#lines + 1] = s:sub(pos, nl - 1)
        pos = nl + 1
    end
    return lines
end
-- 把一行里"引号外"的危险 nil 访问统一兜底为 __nilSafe（注入的智能颜色表）：
--   #colors        → #(colors or __nilSafe)
--   colors[n]      → (colors or __nilSafe)[n]
-- 对合法非 nil 值语义完全不变（x or SAFE == x）；nil 时 SAFE 提供长度和默认颜色，
-- 既不崩也不返回 nil 颜色（返回 nil 颜色正是按键背景变黑的根源）。
-- 覆盖函数参数/局部变量这类全局注入到不了的作用域（配色脚本 randomColor 的 #nil/index nil 根因）。
local KW = { ["and"]=true,["or"]=true,["not"]=true,["if"]=true,["then"]=true,["else"]=true,
    ["elseif"]=true,["end"]=true,["for"]=true,["in"]=true,["do"]=true,["while"]=true,
    ["repeat"]=true,["until"]=true,["return"]=true,["local"]=true,["function"]=true,
    ["break"]=true,["nil"]=true,["true"]=true,["false"]=true }
function patchNilAccess(line)
    local out, i, n = {}, 1, #line
    local quote = nil
    local changed = false
    while i <= n do
        local c = line:sub(i, i)
        if quote then
            out[#out + 1] = c
            if c == "\\" and i < n then out[#out + 1] = line:sub(i + 1, i + 1); i = i + 2
            elseif c == quote then quote = nil; i = i + 1
            else i = i + 1 end
        elseif c == '"' or c == "'" or c == "`" then
            quote = c; out[#out + 1] = c; i = i + 1
        elseif c == "-" and line:sub(i + 1, i + 1) == "-" then
            -- 行注释：整行剩余原样输出，不改写
            out[#out + 1] = line:sub(i); break
        elseif c == "#" then
            local j = i + 1
            while j <= n and line:sub(j, j):match("%s") do j = j + 1 end
            local expr, e = nil, nil
            if line:sub(j, j) == "(" then
                local depth, k = 0, j
                while k <= n do
                    local ch = line:sub(k, k)
                    if ch == "(" then depth = depth + 1
                    elseif ch == ")" then depth = depth - 1; if depth == 0 then break end
                    elseif ch == '"' or ch == "'" then
                        local qq = ch; k = k + 1
                        while k <= n and line:sub(k, k) ~= qq do
                            if line:sub(k, k) == "\\" then k = k + 1 end
                            k = k + 1
                        end
                    end
                    k = k + 1
                end
                if depth == 0 then expr = line:sub(j, k); e = k + 1 end
            elseif j <= n and line:sub(j, j):match("[%a_]") then
                local s2, k = j, j + 1
                while k <= n and line:sub(k, k):match("[%w_]") do k = k + 1 end
                while k <= n do
                    local ch = line:sub(k, k)
                    if ch == "." then
                        k = k + 1
                        while k <= n and line:sub(k, k):match("[%w_]") do k = k + 1 end
                    elseif ch == "[" or ch == "(" then
                        local open, close = ch, (ch == "[" and "]" or ")")
                        local d2 = 0
                        while k <= n do
                            local c2 = line:sub(k, k)
                            if c2 == open then d2 = d2 + 1
                            elseif c2 == close then d2 = d2 - 1
                                if d2 == 0 then k = k + 1; break end
                            end
                            k = k + 1
                        end
                    else break end
                end
                expr = line:sub(s2, k - 1); e = k
            end
            if expr then
                out[#out + 1] = "#(" .. expr .. " or __nilSafe)"
                changed = true
                i = e
            else
                out[#out + 1] = c; i = i + 1
            end
        elseif c:match("[%a_]") then
            -- 标识符：取其后的 [索引] 访问，把被索引对象包成 (x or __nilSafe)
            local s2, k = i, i + 1
            while k <= n and line:sub(k, k):match("[%w_]") do k = k + 1 end
            local name = line:sub(s2, k - 1)
            local j = k
            while j <= n and line:sub(j, j):match("%s") do j = j + 1 end
            if not KW[name] and line:sub(j, j) == "[" then
                -- 只改写被索引对象：name → (name or __nilSafe)，跳过中间的空白；
                -- 索引 [...] 内容交给后续扫描继续处理（里面可能嵌套 #colors 等危险访问）。
                out[#out + 1] = "(" .. name .. " or __nilSafe)" .. line:sub(k, j - 1)
                changed = true
                i = j  -- 停在 '[' 处，下一轮原样输出 '['，再继续扫描索引内部
            else
                out[#out + 1] = name; i = k
            end
        else
            out[#out + 1] = c; i = i + 1
        end
    end
    return table.concat(out), changed
end
-- 对整份源码做一次性 nil 访问预处理（# / 索引），返回 (新源码, 改写处数)。
-- 只编译一次，杜绝"改一处崩另一处"的反复重编译。
function preprocessLenOps(src)
    if not src then return src, 0 end
    local lines = splitLines(src)
    local total = 0
    for i = 1, #lines do
        local fixed, changed = patchNilAccess(lines[i])
        if changed then lines[i] = fixed; total = total + 1 end
    end
    return table.concat(lines, "\n"), total
end

-- 执行主题/配色脚本；真机环境里定义、沙箱缺失的辅助全局（如万象主题的 f_kcr）会
-- 让脚本中途崩溃，导致后续样式全部丢失。这里按错误类型精确注入合理默认值后重跑，
-- 保证样式脚本完整执行——与真机输入界面一致。正常主题不会报错，完全不受影响。
-- ===== 稳健单次执行 =====
-- 主题脚本为完整真机环境编写，在预览沙箱里依赖大量真机对象/函数。旧版用"出错补洞
-- 重试"强行让它跑完：反复整段重跑 + 递归遍历整张表（最多 40 次）→ 加载慢/OOM/ANR，
-- 且注入 0 / 空函数 / 假表污染配色 → 按键背景变黑、串色。这是错误的方向，已废弃。
-- 新策略：沙箱已把真机对象/类换成安全桩、package/loadstring/debug 已隔离，源码预处理
-- 已兜底 #nil/索引 nil。这里只做一次 pcall：能算出的真实数据照常写入 env；出错仅记录
-- 不崩、不慢、不串色，且真实能算出的配色/键盘数据一项不少。
function execWithAutoGlobal(chunk, env, chunkArg, src, path)
    local unpack_ = unpack or table.unpack
    local function noteErrLine(msg)
        local ln = msg:match(":(%d+)[:%s]")
        if ln and src and path then
            local line = splitLines(src)[tonumber(ln)]
            if line then
                local tag = tostring(path) .. ":" .. ln
                if not diagSourceLines[tag] then
                    diagSourceLines[tag] = (line:gsub("^%s+", ""))
                end
            end
        end
    end
    -- 主题脚本可能改写 package.path；执行前后保存/恢复真机的 path/cpath，杜绝污染
    local savedPath, savedCpath
    local pkg = package
    if pkg then savedPath = pkg.path; savedCpath = pkg.cpath end
    local results = chunkArg ~= nil and {pcall(chunk, chunkArg)} or {pcall(chunk)}
    if pkg then pcall(function() pkg.path = savedPath; pkg.cpath = savedCpath end) end
    if results[1] then
        -- 保留 return 值：require 模块靠 `return M` 把表交出来
        if #results > 1 then return true, unpack_(results, 2) end
        return true
    end
    -- 只记录，不补洞、不重试。补洞注入的假值正是串色/黑底的元凶。
    noteErrLine(tostring(results[2]))
    return false, results[2]
end

function sandboxLoad(path, parentEnv)
    local src = readFile(path)
    if not src then return nil, "文件不存在: " .. tostring(path) end
    local env = {}
    env._G = env
    -- ===== 访问源头拦截：从 meta 继承链里漏出的真机 Java 类一律换成安全桩 =====
    -- 万象这类键盘脚本会直接引用「未经 import 的真机全局 Java 类」，如
    -- PreferenceManager.getDefaultSharedPreferences(this)。这类类以大写字母开头
    -- （Java 类命名惯例），若从 parentEnv（真机 Globals）继承到真实类，再用安全桩 this
    -- 作参数调真实方法，就会 coercion error 甚至第一次打开直接崩溃。
    -- 这里对「env 自身没有、但首字母大写的全局名」一律返回安全桩：
    --   · 主题自定义数据/变量多为小写，不受影响；
    --   · 已被 import 绑定的类（ThemeManager 等）已在 env 自身，也不会走到这里。
    local classStubCache = {}
    setmetatable(env, {
        __index = function(t, k)
            local inherited = parentEnv and parentEnv[k]
            if type(k) == "string" and k ~= "" then
                local c = k:sub(1, 1)
                -- 大写开头 = 真机 Java 类命名惯例（PreferenceManager/ThemeManager/Rime...）。
                -- 一律拦截为安全桩：不继承、不看 type（真机类在 Luaj 里 type 可能是 table，
                -- 早先 "type(table) 就放行" 的判断会让真实类泄漏，正是首次崩溃的根源）。
                if c >= "A" and c <= "Z" then
                    local v = classStubCache[k]
                    if not v then v = makeSafeStub() classStubCache[k] = v end
                    sandboxBlockedClasses[k] = (sandboxBlockedClasses[k] or 0) + 1
                    return v
                end
            end
            -- 小写名正常继承（主题自定义数据/cbs/rows 等都是小写）
            return inherited
        end,
    })
    local baseDir = path:match("^(.*)/[^/]+$") or ""

    -- ===== 关键隔离：绝不把真实的 activity / service / luajava 注入主题脚本 =====
    -- 万象这类主题的样式脚本及其 require 模块里，含有「针对真实键盘运行」的函数
    -- （service:xxx() / this.xxx / luajava.bindClass(...) 等直接操作输入法服务）。
    -- 主题工作室只是预览样式，若让这些函数拿到真实对象，就会真正操作输入法进程
    -- 并导致整个输入法崩溃。这里全部换成安全桩：任何调用/索引/运算都落到桩上成为
    -- no-op，既不会崩溃，也不影响纯数据样式表的正常求值（cbs=100 之类照常算出）。
    -- makeSafeStub 已提升为文件级函数（见上方），这里直接使用。
    sandboxRealObjectsIsolated = true
    env.this = makeSafeStub()
    env.service = makeSafeStub()
    env.activity = makeSafeStub()
    env.context = makeSafeStub()
    env.inherit = function(base, over)
        local src2 = base
        if type(base) == "string" then src2 = env[base] end
        local n = {}
        if type(src2) == "table" then for k, v in pairs(src2) do n[k] = v end end
        if type(over) == "table" then for k, v in pairs(over) do n[k] = v end end
        return n
    end
    env.__nilSafe = __nilSafe  -- nil 访问兜底智能表（配色脚本 randomColor 的 colors 为 nil 时用）
    env.print = print
    env.pcall = pcall
    env.xpcall = xpcall
    env.pairs = pairs
    env.ipairs = ipairs
    env.next = next
    env.tostring = tostring
    env.tonumber = tonumber
    env.type = type
    env.select = select
    env.rawget = rawget
    env.rawset = rawset
    env.error = error
    env.assert = assert
    env.setmetatable = setmetatable
    env.getmetatable = getmetatable
    env.unpack = unpack or table.unpack
    env.collectgarbage = collectgarbage or function() end
    -- 真机 JsePlatform.standardGlobals() 提供全套标准库；万象这类主题根脚本会用到
    -- loadstring/load 动态加载、coroutine、rawequal/rawlen 等，沙箱缺失会被调用成 nil
    -- （报错形如 main.lua:50 attempt to call nil ('?')）。这里全部补齐。
    -- 【关键逃逸修复】绝不能把真机 loadstring 直接暴露给主题脚本：
    -- LuaJ 里 loadstring(s) 编译出的 chunk 默认继承【真机 Globals】，主题脚本
    -- `loadstring(code)()` 会让 code 在真机环境执行，绕过全部安全桩，改写与
    -- trime 共享的进程状态 → 第一次打开输入法崩溃、第二次因状态已建立而不崩。
    -- 这里把 loadstring 强制绑定到沙箱 env，且绝不回退到裸 loadstring。
    env.loadstring = function(s, name)
        if s == nil then return function() end end
        if load then
            local ok, g = pcall(load, tostring(s), name or "=(loadstring)", "t", env)
            if ok and g then return g end
        end
        -- 宁可给空函数，也绝不落到会在真机 Globals 执行的裸 loadstring
        return function() end
    end
    env.load = function(s, name, mode, e)
        local envUse = e or env
        -- 用 load 第4参数绑定 env（AndroLua/Luaj 支持）。绝不用 setfenv(function, env)：
        -- 本环境的 setfenv 只接受 int level，会报 "bad argument: int expected, got function"。
        if load then
            local ok, g = pcall(load, s, name, mode or "t", envUse)
            if ok and g then return g end
        end
        -- 兜底走沙箱版 loadstring，绝不直接调用真机 loadstring
        return env.loadstring(s, name)
    end
    env.rawequal = rawequal
    env.rawlen = rawlen
    if coroutine then env.coroutine = coroutine end
    -- 【关键逃逸修复】真机 getfenv(0/2) 能顺调用栈拿到上层真实环境，setfenv 能篡改
    -- 函数环境。工作室自身用 load 第4参数绑定 env，不依赖这两个函数，直接降级：
    -- 环境查询一律回沙箱 env，环境设置降级 no-op，杜绝主题脚本借它逃逸到真机 Globals。
    env.getfenv = function() return env end
    env.setfenv = function(f) return f end
    env.module = function(name, ...)
        local m = {}
        env[name] = m
        return m
    end
    env.gcinfo = gcinfo or function() return 0 end
    pcall(function() env.io = require("io") end)
    -- 【关键逃逸修复】绝不能把真机 debug 库直接暴露给主题脚本：
    -- debug.getregistry() 能拿到真机注册表（含真机 Globals），debug.getfenv/getfenv
    -- 能拿到真实函数环境，debug.setfenv/setupvalue 能篡改真机函数 → 同样会造成
    pcall(function()
        local realDebug = require("debug")
        local safeDebug = {}
        if realDebug then for k, v in pairs(realDebug) do safeDebug[k] = v end end
        safeDebug.getregistry = function() return {} end          -- 不暴露真机注册表
        safeDebug.getfenv = function() return env end             -- 环境查询一律回沙箱
        safeDebug.setfenv = function(f) return f end              -- 篡改环境降级为 no-op
        safeDebug.setupvalue = function() end                     -- 禁止改写 upvalue
        safeDebug.sethook = function() end                        -- 禁止挂钩真机执行
        env.debug = safeDebug
    end)
    -- luajava 也必须隔离：给真桩会让主题脚本 bindClass 到真实输入法服务并操作键盘。
    -- 安全桩下 luajava.bindClass(...).xxx() 全部是 no-op，不会触及真实进程。
    env.luajava = makeSafeStub()
    env.java = makeSafeStub()

    local function cloneTable(t, deep)
        if type(t) ~= "table" then return t end
        local n = {}
        for k, v in pairs(t) do
            n[k] = (deep and type(v) == "table") and cloneTable(v, true) or v
        end
        return n
    end
    local function extendLib(lib)
        return setmetatable({
            clone = function(t) return cloneTable(t, false) end,
            deepclone = function(t) return cloneTable(t, true) end,
            deepcopy = function(t) return cloneTable(t, true) end,
            indexOf = function(t, v) if type(t) ~= "table" then return nil end
                for i, x in ipairs(t) do if x == v then return i end end return nil end,
            contains = function(t, v) return extendLib(nil).indexOf(t, v) ~= nil end,
            split = function(s, sep)
                local out = {}; sep = sep or ","
                local patt = "([^" .. sep:gsub("%W", "%%%0") .. "]*)"
                for part in tostring(s):gmatch(patt) do table.insert(out, part) end
                return out
            end,
        }, {__index = function(_, k)
            local v = lib and lib[k]
            if v ~= nil then return v end
            return function() return nil end
        end})
    end
    env.table = extendLib(table)
    env.string = extendLib(string)
    env.math = extendLib(math)
    -- 【#nil 连锁容错】配色脚本 randomColor 形如 colors[math.random(#colors)]：
    -- 当 #colors=0 时 math.random(0) 在 Lua5.1 会报 "interval is empty"。
    -- 这里包裹 random：空区间/非法参数一律返回 1，避免源码改写后二次崩溃。
    pcall(function()
        local realRandom = math.random
        env.math.random = function(a, b)
            if a == nil then return realRandom() end
            if b == nil then
                if type(a) ~= "number" or a < 1 then return 1 end
                local ok, v = pcall(realRandom, a); if ok then return v end
                return 1
            end
            if type(a) ~= "number" or type(b) ~= "number" or b < a then return a end
            local ok, v = pcall(realRandom, a, b); if ok then return v end
            return a
        end
    end)
    env.os = extendLib(os)
    env.utf8 = extendLib(utf8)
    -- import 不能是空函数：万象主题键盘 qwerty36.lua:1 是
    -- `import "com.osfans.trime.theme.ThemeManager"`，它靠这个类辅助构建 rows。
    -- 空函数会让后续 ThemeManager.xxx() 变成 nil 调用、脚本中途崩溃，rows 没定义、
    -- 被补值逻辑补成 0（数字），于是 type(rows)≈table 判定失败、键盘空白。
    -- 这里把导入的类名绑定为「安全桩」：方法调用是 no-op 但返回结构化桩，
    -- 既不操作真实键盘，又能让纯数据 rows 定义顺利执行。
    env.import = function(cls)
        local name = type(cls) == "string" and cls:match("([^%.%s]+)%s*$") or nil
        local stub = makeSafeStub()
        -- 总是覆盖：即使同名全局经父环境继承链已存在真实 Java 类（如万象的
        -- PreferenceManager），也强制换成安全桩，避免脚本拿真实类 + 安全桩 this 调用
        -- 触发 coercion error（got org.luaj.LuaTable）导致键盘脚本中断。
        if name then env[name] = stub end
        return stub
    end

    -- 在目录下递归找指定文件名（主题脚本的公共库可能放在任意子目录）
    -- 【防卡死】带访问预算：dataDir 若含超大目录树，depth 6 全树扫描会非常慢，
    -- 多次 require 找不到时反复全扫 → 加载时间过长被系统杀进程。限制单次扫描目录数。
    local scanBudget = { n = 250 }
    local function findInTree(root, fname, depth)
        if not root or depth > 6 then return nil end
        scanBudget.n = scanBudget.n - 1
        if scanBudget.n <= 0 then return nil end
        local okList, names = pcall(listDir, root)
        if not okList or not names then return nil end
        for _, n in ipairs(names) do
            if n == fname then
                local p = root .. "/" .. n
                if fileExists(p) then return p end
            end
        end
        for _, n in ipairs(names) do
            local sub = root .. "/" .. n
            local okD, isd = pcall(isDir, sub)
            if okD and isd then
                local r = findInTree(sub, fname, depth + 1)
                if r then return r end
            end
        end
        return nil
    end
    -- resolveLua(p, preferDirs)：按真机 require 语义解析模块真实路径。
    -- preferDirs 是调用方给出的优先目录——样式脚本的 require 首选 style 文件夹，
    -- 被 require 模块内部的 require 首选该模块所在文件夹。返回 (path, triedList)。
    local function resolveLua(p, preferDirs)
        if type(p) ~= "string" then return nil end
        local cands, tried = {}, {}
        local function add(d) if d then cands[#cands + 1] = d .. "/" .. p end end
        -- ① 调用方指定的优先目录（样式脚本 = style 文件夹；模块 = 模块所在目录）
        if preferDirs then for _, d in ipairs(preferDirs) do add(d) end end
        -- ② 入口脚本目录 —— 加载样式时它正是 style 文件夹
        add(baseDir)
        -- ③ 当前样式文件夹、主题根、styles、dataDir（复刻 ResourceFinder 的其余候选）
        add(styleDir)
        if themeDir then add(themeDir); add(themeDir .. "/styles") end
        local okD, dataDir = pcall(function() return Config.getDataDir() end)
        if okD and dataDir then add(tostring(dataDir)) end
        for _, c in ipairs(cands) do
            tried[#tried + 1] = c
            if fileExists(c) then return c, tried end
        end
        -- 兜底：按文件名在主题树、dataDir 全树递归找（模块名带点时取最后一段）
        local fname = p:match("([^/]+)$")
        if fname then
            scanBudget.n = 250  -- 每次 resolve 独立预算，避免多模块累积过早耗尽
            if themeDir then local r = findInTree(themeDir, fname, 0); if r then return r, tried end end
            scanBudget.n = 250
            if okD and dataDir then local r = findInTree(tostring(dataDir), fname, 0); if r then return r, tried end end
        end
        return nil, tried
    end
    local function compile(s2, full)
        -- 用 load 的第4参数把 chunk 绑定到沙箱 env（AndroLua/Luaj 支持，之前版本已验证
        -- chunk 确实在沙箱里跑，补值/import 桩都生效）。绝不用 setfenv(function, env)：
        -- 本环境的 setfenv 只接受 int level，用函数作参数会报
        -- "bad argument: int expected, got function (global 'setfenv')" 直接崩。
        -- 防真实 Java 类靠 env 元表的 __index 大写拦截（见 sandboxLoad 开头），不靠 env 绑定。
        local c2
        if load then
            local ok, f = pcall(load, s2, "@" .. full, "t", env)
            if ok and f then c2 = f end
        end
        if not c2 and loadstring then c2 = loadstring(s2, "@" .. full) end
        return c2
    end
    local function runSub(p)
        local full = resolveLua(p)
        if not full then return nil, "dofile 找不到: " .. tostring(p) end
        local src2 = readFile(full)
        src2 = preprocessLenOps(src2)
        local c2 = compile(src2, full)
        if c2 then
            local ok2, e2 = execWithAutoGlobal(c2, env, nil, src2, full)
            if not ok2 then return nil, e2 end
            return true
        end
        return nil, "加载失败: " .. tostring(p)
    end
    env.dofile = function(p)
        local function pass(ok, ...)
            if not ok then
                local e = (...)
                if e then sandboxLastError = tostring(e) end
                return nil
            end
            return ...
        end
        return pass(runSub(p))
    end
    env.loadfile = function(p)
        local full = resolveLua(p)
        if not full then return nil end
        return compile(readFile(full), full)
    end
    local requireCache = {}
    -- ===== 关键：package 必须完全独立，绝不继承真机的 package =====
    -- env 设了 __index 元表（小写名从 parentEnv 继承），若写 `env.package = env.package or {}`，
    -- 读 env.package 会触发 __index 返回【真机的 package 表】——主题根 main.lua 里
    --   package.path = "/storage/.../scripts/?.lua;" .. package.path
    -- 就会改写【真机 Globals 的 package.path】，丢掉系统默认搜索路径，导致输入法此后
    -- require 任何库都失败 → 首次打开输入法直接崩溃；再次打开 path 已被改过故不崩。
    -- 这里用 rawset 明确写入纯沙箱表，__index 不再有机会返回真机 package；path 字段给
    -- 一个合法初值，使上面的拼接不报错，也不会污染真机。
    local sandboxPackage = {
        loaded = requireCache,
        path = "/storage/emulated/0/Documents/rime/scripts/?.lua;" ..
               "/storage/emulated/0/Documents/rime/lua/?.lua;" ..
               (baseDir ~= "" and (baseDir .. "/?.lua;") or "") ..
               (themeDir and (themeDir .. "/?.lua;") or "") ..
               "?.lua",
        cpath = "",
    }
    rawset(env, "package", sandboxPackage)
    -- 发起方基准目录栈：加载样式脚本时基准 = style 文件夹(baseDir)；
    -- 进入某模块后临时切到该模块所在目录，使模块内部的 require 相对自己找。
    local requireBaseDir = baseDir
    env.require = function(mod)
        if type(mod) ~= "string" then return nil end
        if requireCache[mod] ~= nil then return requireCache[mod] end
        -- 真机 require：模块名 . → /，加 .lua。首选基准是「发起方所在目录」
        -- （样式脚本里的 require → style 文件夹；模块里的 require → 模块所在目录）。
        local rel = (tostring(mod):gsub("%.", "/")) .. ".lua"
        local full, tried = resolveLua(rel, {requireBaseDir})
        if not full then
            -- 模块名本身可能已带 .lua
            local raw = tostring(mod):find("%.lua$") and tostring(mod) or (tostring(mod) .. ".lua")
            full, tried = resolveLua(raw, {requireBaseDir})
        end
        if not full then
            requiredModules[#requiredModules + 1] = tostring(mod) .. " -> 未找到（试过: " ..
                table.concat(tried or {}, " | ") .. "）"
            requireCache[mod] = {}
            return {}
        end
        -- 【循环 require 防护】执行前先登记占位，打断 A→B→A 无限递归（万象主题的模块
        -- 之间可能互相 require）；执行完下面会覆盖成真实返回值。
        -- 没有这行时，循环 require 会指数级递归 → 加载卡死 → 进程被杀 → 输入法陪葬。
        requireCache[mod] = env
        local src2 = readFile(full)
        src2 = preprocessLenOps(src2)
        local c2 = compile(src2, full)
        if not c2 then requireCache[mod] = {} return {} end
        -- 执行模块时把基准切到模块所在目录，支持模块之间的嵌套 require；
        -- 执行完恢复，回到主脚本的基准（style 文件夹）。
        local moduleDir = full:match("^(.*)/[^/]+$") or requireBaseDir
        local prevBase = requireBaseDir
        requireBaseDir = moduleDir
        local ok2, ret, e2 = execWithAutoGlobal(c2, env, tostring(mod), src2, full)
        requireBaseDir = prevBase
        if ok2 then
            if ret == nil then ret = true end  -- Lua 语义：模块无 return 时返回 true
            requireCache[mod] = ret
            requiredModules[#requiredModules + 1] = tostring(mod) .. " -> " .. full
            return ret
        end
        -- execWithAutoGlobal 失败时返回 (false, err)：错误在第 2 个返回值 ret，e2 恒为 nil。
        local failMsg = tostring(ret ~= nil and ret or e2)
        sandboxLastError = failMsg
        requiredModules[#requiredModules + 1] = tostring(mod) .. " -> 执行失败: " .. failMsg
        requireCache[mod] = {}
        return {}
    end

    -- 【通用·#nil 一次性预处理】编译前把整份源码里所有 #表达式改成安全形式，
    -- 一次搞定全部 #nil（randomColor 常有多处），只编译一次，杜绝"改一处崩另一处"
    -- 引发的反复重编译 → 加载慢 → OOM/ANR 崩溃。对合法值语义零影响。
    local patchedSrc, nPatch = preprocessLenOps(src)
    if nPatch > 0 then
        src = patchedSrc
        autoInjectedGlobals["源码预处理#nil(处数)"] = (autoInjectedGlobals["源码预处理#nil(处数)"] or 0) + nPatch
    end
    local chunk = compile(src, path)
    if chunk then
        local ok2, rerr = execWithAutoGlobal(chunk, env, nil, src, path)
        if not ok2 then sandboxLastError = tostring(rerr) end
    end
    return env
end

-- ========== 路径解析 ==========
function parsePath(path)
    local segs = {}
    for seg in path:gmatch("[^%.]+") do
        local n = tonumber(seg)
        table.insert(segs, n or seg)
    end
    return segs
end
function getFrom(root, path)
    local node = root
    for _, seg in ipairs(parsePath(path)) do
        if type(node) ~= "table" then return nil end
        node = node[seg]
    end
    return node
end
function setIn(root, path, v)
    if not root then return end
    local segs = parsePath(path)
    local node = root
    for i = 1, #segs - 1 do
        if type(node[segs[i]]) ~= "table" then node[segs[i]] = {} end
        node = node[segs[i]]
    end
    node[segs[#segs]] = v
end
function luaPath(path)
    local segs = parsePath(path)
    local out = {}
    for _, seg in ipairs(segs) do
        if type(seg) == "number" then
            out[#out] = out[#out] .. "[" .. seg .. "]"
        else
            table.insert(out, seg)
        end
    end
    return table.concat(out, ".")
end

-- 值序列化为 Lua 源码
function luaQuote(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
    return '"' .. s .. '"'
end
function serializeValue(v, indent)
    indent = indent or ""
    local t = type(v)
    if t == "number" then
        if v ~= v then return "0/0" end
        if v == math.huge then return "math.huge" end
        if v == -math.huge then return "-math.huge" end
        if v > 0xFFFFFF and v == math.floor(v) then return string.format("0x%08X", v) end
        return tostring(v)
    elseif t == "string" then
        return luaQuote(v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        local parts = {}
        for k, val in pairs(v) do
            local key
            if type(k) == "number" then key = "[" .. k .. "]"
            elseif type(k) == "string" and k:match("^[%a_][%w_]*$") then key = k
            else key = "[" .. luaQuote(k) .. "]" end
            table.insert(parts, key .. " = " .. serializeValue(val, indent .. "  "))
        end
        if #parts == 0 then return "{}" end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return "nil"
end

-- ========== 全局状态 ==========
local currentTheme, themeDir, themeEnv = nil, nil, nil
local currentVariant, styleDir, styleEnv = nil, nil, nil  -- 配色（样式真正来源）
local currentKbdFile, kbdEnv = nil, nil
local kbdFallbackNote = nil  -- 键盘 rows 加载失败时记录的回退说明（诊断用）
local kbdSelectReason = nil  -- 当前键盘的选择依据（诊断用：真机 get_keyboard 判断链）
local kbdSourceNote = nil    -- 键盘配置来源（反射运行时 globals / 静态解析，诊断用）
local presetKeysCache = {}
local labelImgIndex = nil

-- ===== 【首选数据源】Java 桥接：直接拿输入法已加载的真实主题数据 =====
-- trime2 源码新增 com.osfans.trime.theme.ThemeDataBridge.snapshot()，
-- 同进程跨 Lua 虚拟机读取输入法的 mGlobals/mColor/键盘 Globals，序列化成 Lua 字面量。
-- 工具拿到的是输入法正在用的真实数据：零执行主题脚本、零补洞、零 native 调用。
-- 若桥接类未编译进 APK（或未生效），snapshot 调用失败 → 全部回退原有沙箱方案。
local bridgeData = nil          -- 本次 loadTheme 读到的桥接数据 {style,keyboard,meta}
local bridgeAvailable = nil     -- 桥接类是否可用（三态：nil 未检测 / true / false）
local bridgeDiag = nil          -- 桥接诊断说明
-- 强制忽略桥接键盘、改按主题声明/文件判定重载（诊断用）。
-- 旧版桥接在偏好为空时会自己加载 qwerty36.lua 冒充"真机键盘"，工具无法分辨，
-- 这个开关让用户能立刻验证"是不是桥接把 36 键塞进来的"。

-- rows 下标是 1(string) 而非 1(number)）。序列化后 loadstring 回来仍是 string，
-- 导致工具里所有 type(k)=="number" 判断失效：rowsCount 返回 0 → keyboardRowsOK 失败 →
-- 桥接键盘被丢弃、回退 qwerty36；即使拿到，渲染的 rowIdx/keyIdx 也会把全部行过滤 → 空白。
-- 这里把 keyboard.rows 及每行 keys 的"纯数字字符串 key"规范化回 number。
-- 只动 keyboard，不碰 style（配色表的语义 key 不含纯数字），一处修复下游全部生效。
function numKeyFix(k)
    if type(k) == "string" and k:match("^%d+$") then return tonumber(k) end
    return k
end
-- 把一个"数组型"table 的纯数字字符串 key 转回 number（rows / keys / toolbar.keys 等）
function normalizeArrayKeys(tbl)
    if type(tbl) ~= "table" then return tbl end
    local out = {}
    for k, v in pairs(tbl) do out[numKeyFix(k)] = v end
    return out
end
function normalizeBridgeKeyboardNumberKeys(kbd)
    if type(kbd) ~= "table" or type(kbd.rows) ~= "table" then return kbd end
    local newRows = {}
    for rk, row in pairs(kbd.rows) do
        if type(row) == "table" and type(row.keys) == "table" then
            row.keys = normalizeArrayKeys(row.keys)
        end
        newRows[numKeyFix(rk)] = row
    end
    kbd.rows = newRows
    return kbd
end
-- 【工具栏修复】桥接 style.toolbar.keys 的下标同样是字符串，#tbkeys 会返回 0
-- 导致 buildToolbarPreview 直接 return nil（工具栏整条消失）。这里转回 number。
function normalizeBridgeStyleArrays(style)
    if type(style) ~= "table" then return style end
    if type(style.toolbar) == "table" then
        if type(style.toolbar.keys) == "table" then
            style.toolbar.keys = normalizeArrayKeys(style.toolbar.keys)
            -- toolbar.keys 里每一项若是 table，其内部的数组字段也规范化
            for _, o in pairs(style.toolbar.keys) do
                if type(o) == "table" and type(o.states) == "table" then o.states = normalizeArrayKeys(o.states) end
            end
        end
    end
    return style
end

function readBridgeSnapshot()
    -- 只检测一次桥接类是否可用，避免每次重复 bindClass
    if bridgeAvailable == false then
        return nil
    end

    -- ① 绑定桥接类
    local okBind, cls = pcall(function()
        return luajava.bindClass("com.osfans.trime.theme.ThemeDataBridge")
    end)
    if not okBind or not cls then
        bridgeAvailable = nil   -- 不永久锁定：可能只是类还没被 ClassLoader 加载，下次重载再试
        bridgeDiag = "bindClass 失败——APK 里没有 com.osfans.trime.theme.ThemeDataBridge（桥接类未编译进去？）"
        return nil
    end

    -- ② 调用 snapshot()
    local okSnap, src = pcall(function() return cls.snapshot() end)
    if not okSnap or type(src) ~= "string" or src == "" then
        bridgeAvailable = nil   -- 不永久锁定：输入法可能只是还没加载完，下次重载再试
        bridgeDiag = "snapshot() 调用失败或返回空"
        return nil
    end

    -- ③ 解析 Lua 字面量
    local okChunk, chunk = pcall(function() return loadstring(src) end)
    if not okChunk or not chunk then
        bridgeAvailable = nil
        bridgeDiag = "loadstring 编译快照失败"
        return nil
    end
    local okRun, data = pcall(chunk)
    if not okRun or type(data) ~= "table" then
        bridgeAvailable = nil
        bridgeDiag = "快照 chunk 执行失败"
        return nil
    end

    -- 【关键修复】规范化桥接键盘的数字下标：LuaJ 把 rows[1] 序列化成 ["1"]，
    -- 不转回 number 的话 rowsCount/渲染 rowIdx/keyIdx 会把全部行当字符串过滤掉。
    if type(data.keyboard) == "table" then
        normalizeBridgeKeyboardNumberKeys(data.keyboard)
    end
    -- 【工具栏修复】toolbar.keys 同样被序列化成字符串下标，#tbkeys 返回 0 → 工具栏不显示
    if type(data.style) == "table" then
        normalizeBridgeStyleArrays(data.style)
    end

    bridgeAvailable = true
    -- 至少要拿到样式或键盘之一才算有效
    local hasStyle = type(data.style) == "table" and next(data.style) ~= nil
    local rowsN = 0
    if type(data.keyboard) == "table" and type(data.keyboard.rows) == "table" then
        for k, v in pairs(data.keyboard.rows) do
            if type(k) == "number" and type(v) == "table" and type(v.keys) == "table" then rowsN = rowsN + 1 end
        end
    end
    local hasKbd = rowsN > 0
    local meta = type(data.meta) == "table" and data.meta or {}
    if not hasStyle and not hasKbd then
        bridgeDiag = "桥接返回空数据（输入法可能尚未加载主题，source=" .. tostring(meta.source) .. "）"
        return nil
    end
    bridgeDiag = "Java 桥接数据已加载（source=" .. tostring(meta.source or "?")
        .. "，style=" .. tostring(hasStyle) .. "，keyboard=" .. tostring(hasKbd) .. "）"
    return data
end

-- 内存改动（不写原文件，导出时统一写进新主题）
local styleEdits = {}   -- 样式字段 path -> value
local kbdEdits   = {}   -- 键盘字段 path -> value
local kbdOps     = {}   -- 键盘结构操作：{kind=..., ...} 有序
local dirtyCount = 0    -- 改动计数（用于提示）
-- "只影响当前键"：为单键新建的专属样式表 名字->true。导出时这些表要先整表定义，
-- 再写字段改动；换键盘/配色/主题时随 styleEdits 一起失效。
local newStyleTables = {}
local function clearOwnStyles()
    for name in pairs(newStyleTables) do
        if styleEnv then styleEnv[name] = nil end
        for path in pairs(styleEdits) do
            if path == name or path:find(name .. ".", 1, true) == 1 then
                styleEdits[path] = nil
            end
        end
    end
    newStyleTables = {}
end

-- 【崩溃加固·总开关】一旦用户开始编辑，后续重渲染切到"纯 Lua 安全渲染"：
-- 症状：点"应用修改"后输入法崩溃（工具与输入法同进程），且改的颜色不生效、
-- 再次修改无变化。根因：applyAll→renderPreview 重建全部按键角标，走 nativeSpan
-- （真机 KeyStyle.getSpan）/ newTightOrTextView（用工具 activity 构造真机类）等
-- native 调用；重复渲染时这些 native 调用崩溃（signal 级，pcall 挡不住），整个
-- 进程（输入法+工具）重启，内存里的 styleEdits/kbdEdits 改动全丢 → 表现为"改了没生效"。
-- 真机 TightTextView.onDraw 只用 drawText(字符串)、不渲染 ImageSpan，故角标用
-- 普通 TextView + 纯字符串即可得到同样显示。
-- 【全程安全渲染】工具只改自己的预览视图，绝不调任何真机 native：
--   getSpan / getFont / findImagePath / 构造真机 TightTextView / ThemeManager.getStyle。
-- 这样首次加载与保存操作都零 native 调用 → 不碰真机、不崩溃、改动可见且不会因进程重启丢失。
-- 真机文字内容仍来自只读 dump（liveKeyTexts），纯只读、不调真机业务方法，不受影响。
-- 【真机文字快照的停用策略：按键级精确停用】
-- 角标文字只来自真机 dump 快照 liveKeyTexts（makeKeyView 里 lt），推导逻辑有已知的
-- 长按角标等旧错误，所以【能沿用快照就一定要沿用】。旧实现用单个全局布尔 once-dirty
-- 一刀切：用户改任意字段（哪怕只是边框色）→ markDirty → 全部键角标一起回退 → 旧错误重现。
-- 现改为两级：
--   · liveTextsDisabledKeys[r..","..k] = true ：只有该键的【文字/label/结构】被真正改动时
--     才停用它自己的快照，让该键角标改由 kbdEnv 驱动（改了才可见）；其它键继续用快照。
--   · liveTextsDisabled（全局）：仅在增删/移动键导致 seq 全体错位时才置 true 全量停用。
-- 纯样式编辑（颜色/宽度/圆角/偏移/字体/边距…）两者都不碰 —— 角标保持真机准确显示。
liveTextsDisabled = false              -- 全局总开关：仅结构变化(增删/移动键)时置 true
liveTextsDisabledKeys = {}             -- 按键级：[r..","..k]=true 表示该键文字被改,停用其快照
local function keySlot(r, k) return tostring(r) .. "," .. tostring(k) end
function disableLiveTextOfKey(r, k)
    liveTextsDisabledKeys[keySlot(r, k)] = true
end
function markDirty(n)
    dirtyCount = dirtyCount + (n or 1)
    -- 不再一刀切停用全局快照；由调用方按改动性质精确决定是否停用某键。
end
-- 样式类字段（颜色/宽度/圆角/偏移/字体/边距…）与真机"文字内容"正交：改这些
-- 既不动全局开关、也不动逐键开关，真机文字快照继续生效。
function markStyleDirty(n)
    dirtyCount = dirtyCount + (n or 1)
end

-- ========== 数据获取统一层 ==========
-- 事实：tool 的 this 是 LuaActivity，不是输入法 Service；两者同进程、共享静态字段与默认偏好，
-- 但凡是"依赖 Rime native 引擎 / 输入法实例"的调用都不该在工具里做。
-- 原则：① 只用 Config 的纯静态方法（读 DefaultSharedPreferences / 文件系统）；
--       ② 绝不调用 Config.getKeyboard()（内部 Rime.getCurrentRimeSchema() 是 native）。
-- readPref 与源码 Function.getPref 完全同源（PreferenceManager.getDefaultSharedPreferences）。
function readPref(key, def)
    local out = def
    -- 优先源码 Function.getPref（与输入法完全同源）；类名若被混淆/缺失则回退系统 API
    -- （PreferenceManager.getDefaultSharedPreferences 读的就是同一份默认偏好）。
    local ok = pcall(function()
        local F = luajava.bindClass("com.osfans.trime.util.Function")
        local v = F.getPref(activity):getString(key, def)
        if v ~= nil then out = tostring(v) end
    end)
    if not ok or out == def then
        pcall(function()
            local PM = luajava.bindClass("android.preference.PreferenceManager")
            local v = PM.getDefaultSharedPreferences(activity):getString(key, def)
            if v ~= nil then out = tostring(v) end
        end)
    end
    return out
end
-- 读 float 偏好（与真机 Config.getKeyboardHeightScale 同源）。
-- 真机键盘高度 = style.keyboard.height × keyboard_height_scale，这个 scale 是用户在
-- 「键盘高度」设置里拖出来的浮点值，存在偏好 keyboard_height（横屏 _landscape 后缀）。
-- 之前工具只取主题表里的 keyboard.height，没有乘 scale —— 用户一调键盘高度，预览就和真机不符。
function readPrefFloat(key, def)
    local out = nil
    pcall(function()
        local F = luajava.bindClass("com.osfans.trime.util.Function")
        local v = tonumber(F.getPref(activity):getFloat(key, def))
        if v then out = v end
    end)
    if out == nil then
        pcall(function()
            local PM = luajava.bindClass("android.preference.PreferenceManager")
            local v = tonumber(PM.getDefaultSharedPreferences(activity):getFloat(key, def))
            if v then out = v end
        end)
    end
    -- 少数版本把高度写成字符串偏好，getFloat 拿不到就按字符串读一次
    if out == nil then
        local s = readPref(key, "")
        local v = tonumber(tostring(s):match("[-%d%.]+") or "")
        if v then out = v end
    end
    if out == nil then out = def end
    if out < 0.5 then out = 0.5 end   -- 真机 Config 把 scale 下限压在 0.5
    if out > 2 then out = 2 end       -- 上限 2
    return out
end
-- 真机按键高度缩放：Config.getKeyboardHeightScale()。横屏偏好名带 _landscape。
-- 注意真机还有上限 scale<=屏幕高*0.95/rawContentHeight，这里预览框高度有限，
-- 由 renderPreviewImpl 自己的压缩逻辑兜底，不再重复做屏幕级裁剪。
function keyboardHeightScale()
    local key = "keyboard_height"
    pcall(function()
        local cfg = luajava.bindClass("android.content.res.Configuration")
        local res = activity.getResources()
        local orientation = res.getConfiguration().orientation
        if orientation == cfg.ORIENTATION_LANDSCAPE then key = "keyboard_height_landscape" end
    end)
    local s = readPrefFloat(key, readPrefFloat("keyboard_height", 1.0))
    if type(s) ~= "number" or s <= 0 then s = 1.0 end
    return s
end

-- Java String[] → Lua 数组（AndroLua 的 Java 数组：length 字段 + 0 基下标）
function javaStrArray(arr)
    local out = {}
    if arr == nil then return out end
    local ok, n = pcall(function() return arr.length end)
    if not ok or type(n) ~= "number" then return out end
    for i = 0, n - 1 do
        local okv, v = pcall(function() return arr[i] end)
        if okv and v ~= nil then out[#out + 1] = tostring(v) end
    end
    return out
end
function getThemesRoot()
    local ok, dir = pcall(function() return Config.getThemeDir() end)
    if ok and dir then return tostring(dir) end
    return nil
end
-- 主题列表：Config.getThemes()（源码：themes 下含 main.lua 的目录）
function listThemes()
    local ok, arr = pcall(function() return Config.getThemes() end)
    local out = (ok and javaStrArray(arr)) or {}
    if #out > 0 then return out end
    local root = getThemesRoot()
    if not root then return out end
    for _, name in ipairs(listDir(root)) do
        if fileExists(root .. "/" .. name .. "/main.lua") then out[#out + 1] = name end
    end
    return out
end
-- 配色列表：当前主题用 Config.getStyles()；其它主题用其主题目录下的 styles（源码路径 API）
function listVariants(themeName)
    local cur = nil
    pcall(function() cur = Config.getTheme() end)
    if themeName == cur then
        local ok, arr = pcall(function() return Config.getStyles() end)
        local out = (ok and javaStrArray(arr)) or {}
        if #out > 0 then return out end
    end
    local out = {}
    local okDir, sd = pcall(function() return Config.getThemeDir(themeName) .. "/styles" end)
    sd = (okDir and sd) or (getThemesRoot() .. "/" .. themeName .. "/styles")
    if isDir(sd) then
        for _, name in ipairs(listDir(sd)) do
            if fileExists(sd .. "/" .. name .. "/main.lua") then out[#out + 1] = name end
        end
    end
    return out
end
-- 键盘列表：当前主题用 Config.getKeyboards()；其它主题用其主题目录下的 keyboards
function listKeyboards(themeName)
    local cur = nil
    pcall(function() cur = Config.getTheme() end)
    if themeName == cur then
        local ok, arr = pcall(function() return Config.getKeyboards() end)
        local out = (ok and javaStrArray(arr)) or {}
        if #out > 0 then return out end
    end
    local out = {}
    local okDir, kd = pcall(function() return Config.getThemeDir(themeName) .. "/keyboards" end)
    kd = (okDir and kd) or (getThemesRoot() .. "/" .. themeName .. "/keyboards")
    for _, name in ipairs(listDir(kd)) do
        if name:match("%.lua$") then out[#out + 1] = name end
    end
    return out
end

-- ========== 图片查找（样式目录→主题 images→递归索引→数据目录） ==========
function findImage(rel)
    if not rel or rel == "" then return nil end
    local root = getThemesRoot()
    local cands = {}
    if styleDir then table.insert(cands, styleDir .. "/" .. rel) end
    if themeDir then table.insert(cands, themeDir .. "/" .. rel) end
    if themeDir then
        for _, sub in ipairs(listDir(themeDir)) do table.insert(cands, themeDir .. "/" .. sub .. "/" .. rel) end
    end
    if styleDir then
        for _, sub in ipairs(listDir(styleDir)) do table.insert(cands, styleDir .. "/" .. sub .. "/" .. rel) end
    end
    if root then table.insert(cands, root .. "/" .. rel) end
    -- 与源码 Config.findImagePath 的第三级回退一致：<数据目录>/images
    local okD, dataDir = pcall(function() return Config.getDataDir() end)
    if okD and dataDir then table.insert(cands, tostring(dataDir) .. "/images/" .. rel) end
    for _, p in ipairs(cands) do if p and fileExists(p) then return p end end
    return nil
end
function buildLabelImgIndex()
    labelImgIndex = {}
    local imgRoot = themeDir and (themeDir .. "/images")
    if not imgRoot or not isDir(imgRoot) then return end
    local function scan(dir, depth)
        if depth > 4 then return end
        for _, name in ipairs(listDir(dir)) do
            local p = dir .. "/" .. name
            if isDir(p) then scan(p, depth + 1)
            elseif name:lower():match("%.png$") then
                local key = name:lower()
                if labelImgIndex[key] == nil then labelImgIndex[key] = p end
            end
        end
    end
    scan(imgRoot, 0)
end

-- ========== 真机 native 接口（一律短路） ==========
-- getSize()/getSpan() 依赖输入法已初始化的 native 状态，在工具进程里调用会直接崩掉
-- 整个进程（pcall 挡不住）。这两个接口固定返回"不可用"，渲染代码因此只有本地分支。
--
-- 字体则分两路（见下面的 nativeTypefaceFor / nativeFontOf）：
--   · 首选真机 Style.getFont() 已建好的 Typeface —— 它是一条 fallback 链
--     （中文主字体 + iconfont），本地方案永远复刻不全；
--     这一步只读主题 Lua 表、构建 Typeface，不碰 Rime native，且有 pcall 兜底。
--   · 真机 Style 取不到时退回本地：style 名 → font 字段 → resolveUIFont → loadTypeface。
-- 无论哪一路，最终都要过 Paint.hasGlyph 验证（见 pickTypefaceForLabel），
-- 画不出该字的字体不会被用上 —— 这是「整串变空白」的根因。
-- 字体结果按候选名缓存，避免每次渲染重复扫目录/建 Typeface。
local _fontCache = {}
function nativeFontOf(styleNames)
    local key
    if type(styleNames) == "string" then key = styleNames
    elseif type(styleNames) == "table" then key = table.concat(styleNames, "|")
    else key = "" end
    local hit = _fontCache[key]
    if hit ~= nil then return hit or nil end
    -- 把候选 style 名映射为 font 字段路径：<name>.font，末尾兜底 key.font/keyboard.font
    local paths = {}
    if type(styleNames) == "string" then
        paths[1] = styleNames .. ".font"
    elseif type(styleNames) == "table" then
        for _, nm in ipairs(styleNames) do
            if type(nm) == "string" and nm ~= "" then paths[#paths + 1] = nm .. ".font" end
        end
    end
    paths[#paths + 1] = "key.font"
    paths[#paths + 1] = "keyboard.font"
    local fontName = resolveUIFont(paths)
    local tf = fontName and loadTypeface(fontName) or nil
    _fontCache[key] = tf or false
    return tf
end

-- 真机已经构建好的 Typeface（含 Style.getFont 的 fallback 链）。
-- 【为什么要有这个】本地一个 TextView 只能设一个字体文件，而真机 Style.getFont
-- 对数组型 font 用 CustomFallbackBuilder 建了【整条链】：中文走主字体，
-- 私用区图标字符自动落到后面的 iconfont。工具只挑一个文件，永远差一截 ——
-- 这就是「工具栏特殊字符不显示」的根。这里直接问同进程的主题 Style 要那份链：
-- 只读 Lua 表 + 构建 Typeface（真机渲染本来就在做），不碰 Rime native，全程 pcall。
local _nativeTfCache = {}
function nativeTypefaceFor(styleNames)
    if type(styleNames) ~= "table" or #styleNames == 0 then return nil end
    local key = table.concat(styleNames, "|")
    local hit = _nativeTfCache[key]
    if hit ~= nil then return hit or nil end
    local ok, tf = pcall(function()
        local TM = luajava.bindClass("com.osfans.trime.theme.ThemeManager")
        local root = TM.getStyle()
        if root == nil then return nil end
        for _, nm in ipairs(styleNames) do
            local cur = root
            -- "toolbar.key" 在主题表里是嵌套的 toolbar → key，真机也是这样逐层取
            for seg in tostring(nm):gmatch("[^%.]+") do
                cur = cur:getStyle(seg)
                if cur == nil then break end
            end
            if cur ~= nil then
                local f = cur:getFont("font")
                if f ~= nil then return f end
            end
        end
        return nil
    end)
    if ok and tf then
        _nativeTfCache[key] = tf
        return tf
    end
    _nativeTfCache[key] = false
    return nil
end

-- 安全渲染：偏移一律取样式表里的 Lua 数值，不调真机 getSize。
function nativeOffset(styleNames, key) return nil end

-- 安全渲染：角标一律用纯文字绘制，不调真机 getSpan。
function nativeSpan(text, styleNames, derive) return nil, false end

-- 【r27.38】判定字符串是否为图片文件名。
-- 致命坑：Lua 5.1（LuaJ）的 pattern【不支持 | 交替】。旧代码四处写
--     s:match("%.(png|jpg|jpeg|webp|gif)$")
-- 其字面含义是匹配 ".png|jpg|jpeg|webp|gif" 这个整串，对 bunny.png 恒为 false。
-- 连锁后果：① 图片分支永不进入；② findLabelImage 把 bunny.png 拼成 bunny.png.png
-- 查图返回 nil（日志 #6[bunny.png]TXT->nil 的根因）；③ 诊断把图片键误标成 TXT。
-- 改为取扩展名后逐一比较，兼容大小写。
local function isImageFileName(s)
    if type(s) ~= "string" then return false end
    local ext = s:match("%.([%w]+)$")
    if not ext then return false end
    ext = ext:lower()
    return ext == "png" or ext == "jpg" or ext == "jpeg"
        or ext == "webp" or ext == "gif"
end

function findLabelImage(label)
    if type(label) ~= "string" or label == "" then return nil end
    -- 是否显式图片文件名（bunny.png / x.webp …）。区分这两类很关键：
    --  · 显式文件名 → 可放心走宽查找（主题各子目录 + 递归索引），因为用户已明确指名图片；
    --  · 普通文字 label（含单字，如万象字根 "a"）→ 只走固定三级路径，
    --    否则递归索引会命中子目录同名 a.png，造成字根图误命中（r13 曾踩过）。
    local isFileName = isImageFileName(label)
    local name = isFileName and label or (label .. ".png")
    -- 固定三级路径（与真机 Config.findImagePath 逐字一致）
    if styleDir and fileExists(styleDir .. "/" .. name) then return styleDir .. "/" .. name end
    if themeDir then
        local p = themeDir .. "/images/" .. name
        if fileExists(p) then return p end
    end
    if isFileName then
        -- 【r27.33】显式文件名：宽查找兜底（主题根/各子目录/数据目录，findImage 已覆盖），
        -- 再用递归索引（深度 4）找 images/子目录 里的图。修 png 不显示：
        -- 旧实现只查 3 个固定路径，子目录 png 返回 nil → 落回显示文件名。
        local p = findImage(name)
        if p then return p end
        if labelImgIndex then
            local ip = labelImgIndex[name:lower()]
            if ip then return ip end
        end
    else
        local okD, dataDir = pcall(function() return Config.getDataDir() end)
        if okD and dataDir then
            local p = tostring(dataDir) .. "/images/" .. name
            if fileExists(p) then return p end
        end
    end
    return nil
end
-- 字体文件查找（对齐 Style.getFont：主题字体目录 → 主题 → 数据目录）
local fontIndex = nil
function buildFontIndex()
    fontIndex = {}
    -- 深度限制很关键：万象这类主题根目录会有成百上千个图片/脚本，
    -- 旧实现递归整棵树（深度 4）只为了找一个 iconfont.ttf，切一次主题就卡一下。
    -- fonts 目录深一点，主题根只看到一级子目录即可。
    local function scan(dir, depth, maxDepth)
        if not dir or depth > maxDepth or not isDir(dir) then return end
        for _, name in ipairs(listDir(dir)) do
            local p = dir .. "/" .. name
            if isDir(p) then
                -- 图片目录动辄几千个文件，为找字体扫它纯属浪费；主题字体也不会放这儿。
                local low = name:lower()
                if low ~= "images" and low ~= "img" and low ~= "backgrounds" then
                    scan(p, depth + 1, maxDepth)
                end
            elseif name:lower():match("%.ttf$") or name:lower():match("%.otf$")
                or name:lower():match("%.ttc$") or name:lower():match("%.otc$") then
                local low = name:lower()
                if fontIndex[low] == nil then fontIndex[low] = p end
                -- 去扩展名 key 兜底（font 字段可能写 "iconfont" 而非 "iconfont.ttf"）
                local stem = low:match("^(.+)%.%a+$")
                if stem and fontIndex[stem] == nil then fontIndex[stem] = p end
            end
        end
    end
    if themeDir then
        scan(themeDir .. "/fonts", 0, 6)   -- 标准字体目录（子目录常按语言/字重分层）
        -- 主题根下找 iconfont：万象这类主题会放在 <主题>/<子目录>/<子目录>/ 里。
        -- 深度保持 4（与旧版一致），避免比旧版少扫一层又把图标字体漏掉；
        -- images 等图片目录已在 scan 里跳过，不会因为放宽深度而变慢。
        scan(themeDir, 0, 4)
    end
    if styleDir then scan(styleDir, 0, 4) end
    -- 全局字体目录 Documents/rime/fonts：主题里 font 只写文件名、文件放在这里的很常见。
    -- 旧索引不扫它，只靠 findFont 的精确拼接能命中，换个名字（如 iconfont）就找不到，
    -- 图标字体一丢，工具栏的私用区字符整排变空白。
    local okD, dataDir = pcall(function() return Config.getDataDir() end)
    if okD and dataDir then scan(tostring(dataDir) .. "/fonts", 0, 2) end
end
function findFont(name)
    if type(name) ~= "string" or name == "" then return nil end
    if styleDir and fileExists(styleDir .. "/" .. name) then return styleDir .. "/" .. name end
    if themeDir then
        local p = themeDir .. "/fonts/" .. name
        if fileExists(p) then return p end
    end
    -- 懒建索引：主题脚本里没写字体时不必扫目录
    if not fontIndex then buildFontIndex() end
    if fontIndex then
        local low = name:lower()
        local hit = fontIndex[low]
        if not hit then
            local stem = low:match("^(.+)%.%a+$")
            if stem then hit = fontIndex[stem] end
        end
        if hit then return hit end
    end
    local okD, dataDir = pcall(function() return Config.getDataDir() end)
    if okD and dataDir then
        local p = tostring(dataDir) .. "/fonts/" .. name
        if fileExists(p) then return p end
    end
    return nil
end
-- 字体缓存 + 文件校验。
-- Typeface.createFromFile 每次都会重新读盘并让 native（Skia）解析字形，而预览里
-- 每个键的每个标签（主标签、long_click 角标、hint 角标）都要取一次字体：
-- 一次渲染就是 100+ 次 createFromFile → 明显卡顿、内存抖动。更麻烦的是，
-- 损坏的或只是改了后缀名的「假 .ttf」会让 Skia 在 native 层直接崩（SIGSEGV，
-- Lua 的 pcall 完全挡不住），表现就是输入法闪退。这里按路径缓存，
-- 并且只接受大小合理、扩展名正确的字体文件；失败记 false，不反复重试。
local tfCache = {}
local JFileCls = nil
pcall(function() JFileCls = luajava.bindClass("java.io.File") end)
function loadTypeface(name)
    -- 回到 r9「能正确显示」的极简实现：找到字体文件就直接 createFromFile。
    -- 之前加的 32MB 大小限制 / 扩展名白名单会误挡万象的合并字体（中文+图标在一个
    -- 大 ttf 里），一旦挡掉，工具栏图标和文字全退回系统字体 —— 用户反馈的显示问题。
    -- pcall 保留：挡住 Java 层异常；native 崩溃靠「不扫字体池、只加载主题声明的字体」
    -- 这条路规避（r9 长期这么跑没闪退）。
    local p = findFont(name)
    if not p then return nil end
    local ok, tf = pcall(function()
        return luajava.bindClass("android.graphics.Typeface").createFromFile(p)
    end)
    if ok then return tf end
    return nil
end

-- 换主题/配色/键盘时统一作废字体相关缓存。
-- 之前只清了 _fontCache、fontIndex，tfCache 与图标字体兜底仍在，
-- 于是「先看无字体的主题、再换到有 iconfont 的主题」时，同名缓存命中 false，
-- 图标字体永远加载不上 —— 表现就是工具栏的特殊字符突然不显示了。
local _iconFont, _iconFontTried = nil, false
-- 这三个也必须在 resetFontCaches 之前声明，否则函数体里赋值会落到全局，
-- local 那份永远是空的 —— 换主题时清了个寂寞。
local _themeFonts, _glyphCache, _labelTfCache = nil, {}, {}
local _glyphCacheN = 0     -- 探测结果条数上限，防止长时间使用后无限膨胀
function resetFontCaches()
    fontIndex = nil
    tfCache = {}
    _fontCache = {}
    _iconFont, _iconFontTried = nil, false
    -- 字形探测/主题字体池同样绑在「当前主题目录」上，换主题必须一起作废，
    -- 否则新主题的图标字符会命中旧主题的探测结果，永远显示不出来。
    _themeFonts = nil
    _glyphCache = {}
    _glyphCacheN = 0
    _labelTfCache = {}
    _nativeTfCache = {}      -- 真机 Typeface 也绑在「当前主题」上，换主题必须重取
end

-- UTF-8 逐个字符拆开（Lua 5.1 没有 utf8 库，LuaJ 也没有）。
-- 返回 { {s="字", cp=码位}, ... }，同时给「按码位判断」和「按单字探测字形」用。
function utf8Units(s)
    local out, i, n = {}, 1, #s
    while i <= n do
        local b = s:byte(i)
        if not b then break end
        local len, cp
        if b < 0x80 then
            len, cp = 1, b
        elseif b < 0xE0 then
            local b2 = s:byte(i + 1) or 0
            len, cp = 2, (b - 0xC0) * 0x40 + (b2 - 0x80)
        elseif b < 0xF0 then
            local b2, b3 = s:byte(i + 1) or 0, s:byte(i + 2) or 0
            len = 3
            cp = ((b - 0xE0) * 0x40 + (b2 - 0x80)) * 0x40 + (b3 - 0x80)
        else
            local b2, b3, b4 = s:byte(i + 1) or 0, s:byte(i + 2) or 0, s:byte(i + 3) or 0
            len = 4
            cp = (((b - 0xF0) * 0x40 + (b2 - 0x80)) * 0x40 + (b3 - 0x80)) * 0x40 + (b4 - 0x80)
        end
        out[#out + 1] = { s = s:sub(i, i + len - 1), cp = cp }
        i = i + len
    end
    return out
end

-- 私用区字符（U+E000–U+F8FF）：图标字体的主战场。
-- 旧实现只看首字节是不是 0xEE/0xEF，而 0xEF 还覆盖 U+F000–U+FFFF，
-- 于是全角标点（「，」=U+FF0C、「；」=U+FF1B、「：」=U+FF1A…）全被误判成私用区，
-- 被强行套上图标字体，结果这些标点在工具栏上反而显示成空白。这里老实解码码位。
local function hasPrivateUse(s)
    if type(s) ~= "string" or s == "" then return false end
    for _, u in ipairs(utf8Units(s)) do
        if u.cp >= 0xE000 and u.cp <= 0xF8FF then return true end
    end
    return false
end

-- ========== 字形探测：不猜文件名，直接问字体「你有没有这个字」 ==========
-- 之前靠名字猜图标字体（iconfont.ttf / *icon*），猜错就把一个不含该字符的字体
-- 塞给 TextView —— 汉字、图标直接变空白或豆腐块。这里用 Paint.hasGlyph
-- 逐个码位验证，只有真的画得出来才用它；一个都不行就保持系统默认（至少能显示）。
local JPaintCls = nil
pcall(function() JPaintCls = luajava.bindClass("android.graphics.Paint") end)
local _probePaint = nil
-- 单次渲染的字形探测预算：一次预览最多问 500 次 hasGlyph。
-- hasGlyph 是 JNI 调用，极端主题（几十个图标键 × 十几个字体）能把主线程拖住上秒；
-- 预算耗尽后一律不设字体，交给系统字体 —— 宁可少一个图标，也不要整屏卡住。
local _glyphBudget = 500
function resetGlyphBudget() _glyphBudget = 500 end
-- _glyphCache 在上面统一声明（resetFontCaches 要清它）

local function paintHasGlyph(tf, ch)
    if not JPaintCls then return true end      -- 探测不了就不拦，退回旧行为
    if _glyphBudget <= 0 then return nil end   -- 预算耗尽：调用方按「本次不设字体」处理
    if not _probePaint then
        local ok, p = pcall(function() return JPaintCls() end)
        if not ok or not p then return true end
        _probePaint = p
    end
    _glyphBudget = _glyphBudget - 1
    local ok, r = pcall(function()
        _probePaint.setTypeface(tf)
        return _probePaint.hasGlyph(ch)
    end)
    if not ok then return true end             -- API < 23 没有 hasGlyph
    return r == true
end

function typefaceHasGlyphs(tf, s)
    if not tf then return false end
    local id = tostring(tf)
    local okAll = true
    for _, u in ipairs(utf8Units(tostring(s or ""))) do
        -- 空白字符任何字体都能画，且部分自绘字体对空格返回 false，跳过免得误杀
        if u.cp > 0x20 and u.cp ~= 0x7F then
            local k = id .. "\1" .. u.s
            local hit = _glyphCache[k]
            if hit == nil then
                if _glyphCacheN > 4000 then _glyphCache = {}; _glyphCacheN = 0 end
                hit = paintHasGlyph(tf, u.s)
                if hit == nil then return false end   -- 预算耗尽：本次不设字体，走系统字体
                _glyphCache[k] = hit
                _glyphCacheN = _glyphCacheN + 1
            end
            if not hit then okAll = false; break end
        end
    end
    return okAll
end

-- 主题目录里能找到的全部字体（图标字体优先），按需加载，最多 16 个。
-- _themeFonts 在上方统一声明，换主题时由 resetFontCaches 置 nil 重建。
function themeFontList()
    if _themeFonts then return _themeFonts end
    _themeFonts = {}
    if not fontIndex then buildFontIndex() end
    if not fontIndex then return _themeFonts end
    local ks = {}
    for k in pairs(fontIndex) do ks[#ks + 1] = k end
    table.sort(ks)
    local pref, rest = {}, {}
    for _, k in ipairs(ks) do
        if k:find("icon", 1, true) or k:find("symbol", 1, true)
            or k:find("glyph", 1, true) then pref[#pref + 1] = k
        else rest[#rest + 1] = k end
    end
    local n = 0
    local function push(list, cap)
        for _, k in ipairs(list) do
            if n >= cap then break end
            local tf = loadTypeface(fontIndex[k])
            if tf then _themeFonts[#_themeFonts + 1] = tf; n = n + 1 end
        end
    end
    -- 上限收紧到 4/8：createFromFile 会把整个字体文件解析进 native 内存，
    -- 一个 20MB 的 CJK 字体在低端机上要几百毫秒。16 个字体 × 每个 key 的探测，
    -- 足以让首屏白屏、甚至 ANR（工具与输入法同进程）。真正需要的只有图标字体那几个。
    push(pref, 4)
    push(rest, 8)
    return _themeFonts
end

-- 给某个 label 挑字体。
-- prefTfs 是主题声明的字体（可能来自真机 Style），prefName 是主题里的字体名。
-- 普通字符（中文/字母/标点）：直接用主题声明的字体，和早期能正确显示的版本一致；
--   hasGlyph 对 fallback 链的误判会让主题字体被丢弃，所以这里不校验。
-- 私用区图标字符：逐个用 hasGlyph 验证，只有真画得出才用，否则交回系统字体。
-- _labelTfCache 同样在上方统一声明。
function pickTypefaceForLabel(label, prefTfs, prefName)
    label = tostring(label or "")
    if label == "" then return nil end
    -- 缓存键带上「首选字体」：同一个 label 在 toolbar.key 和 hint 角标下
    -- 可能用不同字体，不带就会互相串用。
    local lk = label .. "\1" .. tostring(prefName or "")
        .. "\1" .. tostring(type(prefTfs) == "table" and prefTfs[1] or "")
    local hit = _labelTfCache[lk]
    if hit ~= nil then return hit or nil end
    -- 【两类字符都不再用 Paint.hasGlyph 挑字体】
    -- hasGlyph 对 CustomFallbackBuilder 合成的 fallback 链、以及私用区码位都会误判 false
    -- （按单字问「有没有这个字形」≠ 整串实际渲染），一校验就把正确的字体丢掉、
    -- 退回系统字体 —— 中文变豆腐、图标变方框都是这么来的。
    --
    -- ① 普通字符：主题/真机声明的字体直接生效（与早期能正确显示的版本一致）。
    -- ② 私用区图标字符：只有图标字体画得出，系统字体必然方框。优先用
    --    「真机 fallback 链」——它本身就是 中文主字体 + iconfont 合成的，
    --    真机工具栏就是用它渲染的，工具照用即可；拿不到再用本地图标字体兜底。
    local isIcon = hasPrivateUse(label)
    local picked = nil
    if isIcon then
        -- 回到早期「能正确显示」的做法：主题 font 字段解析出的字体直接 setTypeface，
        -- 不经 hasGlyph。工具栏图标是私用区，只有主题自带的 iconfont 画得出；
        -- hasGlyph 对 fallback 链的误判会把正确字体丢掉 → 系统字体 → 方框。
        --
        -- 顺序：① 专门的图标字体兜底（按文件名 / font 数组 / 主题字体池找到的单文件）
        --       ② 本地 nativeFontOf 解析出的主题字体
        --       ③ 真机 fallback 链（最后，因为它可能取到不含图标的字体）
        local itf = iconFontFallback()
        if itf then picked = itf end
        if not picked and type(prefTfs) == "table" then
            -- prefTfs[2] 是 nativeFontOf 的结果（[1] 是真机链）
            if prefTfs[2] then picked = prefTfs[2]
            elseif prefTfs[1] then picked = prefTfs[1] end
        end
        if not picked and type(prefName) == "string" and prefName ~= "" then
            picked = loadTypeface(prefName)
        end
        if not picked and type(prefTfs) == "table" then picked = prefTfs[1] end
        -- 最后兜底：主题字体池逐个试（单字体文件，hasGlyph 对单字体可靠）。
        if not picked then
            for _, tf in ipairs(themeFontList()) do
                if typefaceHasGlyphs(tf, label) then picked = tf break end
            end
        end
    else
        picked = (type(prefTfs) == "table") and prefTfs[1] or nil
        if not picked and type(prefName) == "string" and prefName ~= "" then
            picked = loadTypeface(prefName)
        end
    end
    if picked then
        _labelTfCache[lk] = picked
        return picked
    end
    -- 到这里说明所有候选都拿不到：交回系统字体（图标会显示方框，但至少不会
    -- 因为 hasGlyph 误判把本来正确的字体丢掉）。缓存 false，避免每次渲染重复找。
    _labelTfCache[lk] = false
    return nil
end


-- 图标字体兜底。
-- 主题里的 font 字段常常只写在 keyboard / candidate 上，toolbar 自身不带 font；
-- 私用区字符一旦拿不到 iconfont，系统字体没有对应字形，只能显示空白。
-- 这里按名字挑一个图标字体兜底，让工具栏图标在没有 toolbar.key.font 时也能显示。
function iconFontFallback()
    if _iconFontTried then return _iconFont end
    _iconFontTried = true
    local names = {
        "iconfont.ttf", "iconfont.otf",
        "icon.ttf", "icons.ttf", "symbol.ttf", "symbols.ttf",
        "trime.ttf", "rime.ttf", "material.ttf",
    }
    for _, n in ipairs(names) do
        local tf = loadTypeface(n)
        if tf then _iconFont = tf; return tf end
    end
    if not fontIndex then buildFontIndex() end
    if fontIndex then
        local ks = {}
        for k in pairs(fontIndex) do ks[#ks + 1] = k end
        table.sort(ks)
        for _, k in ipairs(ks) do
            if k:find("icon", 1, true) or k:find("symbol", 1, true)
                or k:find("glyph", 1, true) then
                local tf = loadTypeface(fontIndex[k])
                if tf then _iconFont = tf; return tf end
            end
        end
    end
    -- 主题里的 font 常写成数组（主字体 + 图标字体），真机 Style.getFont 按序回退。
    -- 工具只能给 TextView 一个 Typeface，图标字符就改用数组里「非首个」的字体。
    for _, p in ipairs({ "toolbar.key.font", "toolbar.font", "key.font",
                         "keyboard.font", "candidate.font" }) do
        local v = getValue(p)
        if type(v) == "table" then
            local idx = {}
            for k in pairs(v) do
                local n = numKeyFix(k)
                if type(n) == "number" then idx[#idx + 1] = n end
            end
            table.sort(idx)
            for i = 2, #idx do
                local nm = v[idx[i]]
                if nm == nil then nm = v[tostring(idx[i])] end
                if type(nm) == "string" then
                    local tf = loadTypeface(nm)
                    if tf then _iconFont = tf; return tf end
                end
            end
        end
    end
    return nil
end

function buildPresetKeys()
    local t = {}
    local function put(k, v)
        -- 纯数字 key 统一成字符串，和 resolveEventLabel 的 tostring 查表一致
        -- （万象 preset_keys 的数字键事件如 [1] 或 ["1"]，都要能被 click="1" 命中）
        if type(k) == "number" then k = tostring(math.floor(k) == k and k or k) end
        if t[k] == nil then t[k] = v end
    end
    local function merge(src)
        if type(src) == "table" then for k, v in pairs(src) do put(k, v) end end
    end
    merge(themeEnv and themeEnv.preset_keys)
    local root = getThemesRoot()
    if root and currentTheme ~= "default" and fileExists(root .. "/default/main.lua") then
        local denv = sandboxLoad(root .. "/default/main.lua")
        merge(denv and denv.preset_keys)
    end
    presetKeysCache = t
end
-- 事件串 -> 显示文字（对齐 trime2 Event/KeyView：preset label 优先，否则去 {...} 组）
function resolveEventLabel(s)
    if s == nil then return nil end
    -- 桥接快照里数字键的 click 可能是 number（如 1），LuaJ 序列化保留数值类型。
    -- 统一转字符串再查 preset_keys，否则数字键 label 恒为 nil → 看不到文字。
    if type(s) == "number" then s = tostring(math.floor(s) == s and s or s) end
    if type(s) ~= "string" or s == "" then return nil end
    local pk = presetKeysCache[s]
    -- 事件串常写成 "{Keyboard_symbol}"，而 preset_keys 的键是 "Keyboard_symbol"（不带括号），
    -- 直接查表必然落空 → 走到最后 gsub 去括号 → 返回空串 → 工具栏那个键就是一片空白。
    -- 这是「工具栏不显示特殊字符」的另一半原因：字符没丢，是 label 被取成了空串。
    if pk == nil then
        local name = s:match("^{([^{}]+)}$")
        if name then pk = presetKeysCache[name] end
    end
    if type(pk) == "table" then return pk.label or "" end
    if type(pk) == "string" then return pk end
    return (s:gsub("{[^{}]+}", ""))
end

-- 事件值 → 显示 label：兼容 string / number / table（万象 preset 事件是
-- {label=..., send=...} 结构）。long_click / swipe 角标取值统一走这里。
-- 严格复刻真机 Event.getLabel()：toggle+states → 当前态；否则 label/select/send/text。
function resolveEventLabelFull(x)
    if type(x) == "string" then
        local r = resolveEventLabel(x)
        return (r ~= nil and r ~= "") and r or x
    elseif type(x) == "number" then
        return tostring(x)
    elseif type(x) == "table" then
        local toggle = x.toggle
        if type(toggle) == "string" and toggle ~= "" and type(x.states) == "table" then
            local st = x.states[1] or x.states["1"]
            if st ~= nil and st ~= "" then return tostring(st) end
        end
        if x.label ~= nil and x.label ~= "" then return resolveEventLabelFull(x.label) end
        if x.select ~= nil and x.select ~= "" then return tostring(x.select) end
        if x.send ~= nil and x.send ~= "" then return resolveEventLabelFull(x.send) end
        if x.text ~= nil and x.text ~= "" then return tostring(x.text) end
    end
    return nil
end

-- ========== 内存编辑引擎（只改内存表 + 记录改动，绝不写原文件） ==========
local STYLE_UNSET = "\255UNSET\255"   -- 样式字段「删除」标记（导出时写成 = nil）
function getValue(path)
    local v = styleEdits[path]
    if v ~= nil then
        if v == STYLE_UNSET then return nil end
        return v
    end
    if not styleEnv then return nil end
    return getFrom(styleEnv, path)
end
function setValue(path, v)
    styleEdits[path] = v
    setIn(styleEnv, path, v)     -- 同步内存表，预览实时反映
    markStyleDirty(1)            -- 纯样式改动：保留真机文字快照，角标不回退
end
-- 预览用：按某区域的 corner_radius / stroke_width / stroke_color 生成背景 drawable。
-- 真机 Style.getDrawable 的圆角取【当前这张样式表】的 corner_radius，不是背景字段自己的，
-- 所以键盘整体背景用根表、按键区用 keyboard.*、工具栏用 toolbar.*，前缀一一对应。
function areaDrawable(prefix, color)
    local function p(f) return prefix == "" and f or (prefix .. "." .. f) end
    local gd = GradientDrawable()
    gd.setShape(GradientDrawable.RECTANGLE)
    gd.setColor(color)
    gd.setCornerRadius(dp(tonumber(getValue(p("corner_radius"))) or 0))
    local sw = tonumber(getValue(p("stroke_width"))) or 0
    if sw > 0 then gd.setStroke(dp(sw), tonumber(getValue(p("stroke_color"))) or 0) end
    return gd
end

-- 删除某个样式字段：先让预览回退到继承/默认，导出时写 <path> = nil。
function unsetStyleValue(path)
    styleEdits[path] = STYLE_UNSET
    if styleEnv then
        -- 只在路径真实存在时置 nil：不要为了删一个字段顺手创建空的中间表
        local segs = parsePath(path)
        local node = styleEnv
        for i = 1, #segs - 1 do
            node = node[segs[i]]
            if type(node) ~= "table" then node = nil; break end
        end
        if type(node) == "table" then node[segs[#segs]] = nil end
    end
    markStyleDirty(1)
end
-- 解析 UI 字体名：按给定路径依次在 style 与主题根里找，字段可为字符串或字体数组；
-- 返回第一个 findFont 能定位到真实字体文件的名字，供 loadTypeface 使用。
function resolveUIFont(paths)
    local function pick(v)
        if type(v) == "string" and v ~= "" then
            return findFont(v) and v or nil
        elseif type(v) == "table" then
            -- 真机 Style.getFont 对数组型 font 按 1..n 顺序做 fallback。
            -- 桥接数据里数字下标可能是字符串 "1"/"2"，ipairs 会立即停 → 取不到，
            -- 这里收集所有数字下标（含纯数字字符串）排序后按序取，再兜底字符串 key。
            local idx = {}
            for k in pairs(v) do
                local n = numKeyFix(k)
                if type(n) == "number" then idx[#idx + 1] = n end
            end
            table.sort(idx)
            for _, n in ipairs(idx) do
                local x = v[n] ~= nil and v[n] or v[tostring(n)]
                if type(x) == "string" and findFont(x) then return x end
            end
            -- 字符串 key 的字体表（如 {candidate="x.ttf"}）
            for _, x in pairs(v) do
                if type(x) == "string" and findFont(x) then return x end
            end
        end
        return nil
    end
    for _, p in ipairs(paths) do
        local hit = pick(getValue(p))
        if hit then return hit end
        if themeEnv then
            hit = pick(getFrom(themeEnv, p))
            if hit then return hit end
        end
    end
    -- 兜底：万象等主题把字体写在非标准字段（如顶层全局变量 xxxfont）。
    -- 深度扫描 style 里所有 font 类字段，返回第一个能定位到真实字体文件的值。
    if styleEnv then
        local found = nil
        local function scan(t, depth)
            if found or type(t) ~= "table" or depth > 4 then return end
            for k, v in pairs(t) do
                if found then break end
                local ks = type(k) == "string" and k:lower() or ""
                if (ks:find("font", 1, true) or ks:find("typeface", 1, true)) then
                    local hit = pick(v)
                    if hit then found = hit; break end
                end
                if type(v) == "table" then scan(v, depth + 1) end
            end
        end
        scan(styleEnv, 0)
        if found then return found end
    end
    return nil
end
function getKbdValue(path)
    if kbdEdits[path] ~= nil then return kbdEdits[path] end
    if not kbdEnv then return nil end
    return getFrom(kbdEnv, path)
end
function setKbdValue(path, v)
    kbdEdits[path] = v
    setIn(kbdEnv, path, v)
    markDirty(1)
end
-- 键盘文件里的"纯样式引用"字段（style 指针）：改它不影响文字/序号，
-- 保留真机文字快照，避免角标回退。
function setKbdStyleValue(path, v)
    kbdEdits[path] = v
    setIn(kbdEnv, path, v)
    markStyleDirty(1)
end
function unsetKbdValue(r, k, field)
    local path = "rows." .. r .. ".keys." .. k .. "." .. field
    kbdEdits[path] = "\255UNSET\255"  -- 标记删除
    local row = kbdEnv and kbdEnv.rows and kbdEnv.rows[r]
    if row and row.keys and row.keys[k] then row.keys[k][field] = nil end
    markDirty(1)
end

-- 键盘结构操作（内存执行 + 记录），导出时按顺序重放
function opSwap(r, k, k2)
    local keys = kbdEnv and kbdEnv.rows and kbdEnv.rows[r] and kbdEnv.rows[r].keys
    if not keys or not keys[k] or not keys[k2] then toast("无法交换") return false end
    keys[k], keys[k2] = keys[k2], keys[k]
    table.insert(kbdOps, {kind = "swap", r = r, k = k, k2 = k2})
    liveTextsDisabled = true  -- seq 顺序变了，全量停用旧快照
    markDirty(1); return true
end
function opMove(r, k, r2)
    local rows = kbdEnv and kbdEnv.rows
    local src = rows and rows[r] and rows[r].keys
    local dst = rows and rows[r2] and rows[r2].keys
    if not src or not dst then toast("目标行不存在") return false end
    local keyDef = table.remove(src, k)
    local pos = math.min(k, #dst + 1)
    table.insert(dst, pos, keyDef)
    table.insert(kbdOps, {kind = "move", r = r, k = k, r2 = r2, pos = pos})
    liveTextsDisabled = true  -- seq 顺序变了，全量停用旧快照
    markDirty(1); return true
end
function opInsert(tr, pos, spacer)
    local keys = kbdEnv and kbdEnv.rows and kbdEnv.rows[tr] and kbdEnv.rows[tr].keys
    if not keys then return false end
    local keyDef = spacer and {width = 5} or {click = "a", label = "A", width = 10}
    table.insert(keys, pos, keyDef)
    table.insert(kbdOps, {kind = "insert", r = tr, pos = pos, key = keyDef})
    liveTextsDisabled = true  -- seq 顺序变了，全量停用旧快照
    markDirty(1); return true
end
function opDelete(r, k)
    local keys = kbdEnv and kbdEnv.rows and kbdEnv.rows[r] and kbdEnv.rows[r].keys
    if not keys or not keys[k] then return false end
    table.remove(keys, k)
    table.insert(kbdOps, {kind = "delete", r = r, k = k})
    liveTextsDisabled = true  -- seq 顺序变了，全量停用旧快照
    markDirty(1); return true
end
function setKbdTop(field, v)
    if not kbdEnv then return end
    kbdEnv[field] = v
    table.insert(kbdOps, {kind = "top", field = field, value = v})
    markDirty(1)
end

-- ========== 预览渲染 ==========
local renderPreview       -- 前向声明
local keyEditDialog       -- 前向声明
local channelEditDialog   -- 前向声明（按事件通道编辑，核心新交互）
local tbKeysDialog        -- 前向声明
local selKeyR, selKeyK = nil, nil
local previewBox     -- UI 构建时赋值
local renderRetry = 0
local showCandidateFlag = true  -- 真机输入界面默认显示候选栏（candidate.show 默认 true）

-- ========== 事件通道定义（复刻 trime2 的 6 类按键事件）==========
-- 每类通道：event 字段、提示文字字段、样式表相对路径、显示色（用于编辑区着色）
local CHANNELS = {
    -- label = 该状态 view 上实际显示的文字字段（click→label；其余→ch.hint 角标文字字段）
    -- hint  = click 专属：独立 hint（真机 mHints[0]="下标提示"）的显示文字字段
    { id = "click",      name = "点击",   ev = "click",       label = "label",     hint = "hint",       stPath = "",              color = 0xFF3FB950 },
    { id = "long_click", name = "长按",   ev = "long_click",  hint = "hint_long",  stPath = "long_click",    color = 0xFFE3B341 },
    { id = "swipe_up",   name = "上滑",   ev = "swipe_up",    hint = "hint_up",    stPath = "hint.up",       color = 0xFF58A6FF },
    { id = "swipe_down", name = "下滑",   ev = "swipe_down",  hint = "hint_down",  stPath = "hint.down",     color = 0xFF58A6FF },
    { id = "swipe_left", name = "左滑",   ev = "swipe_left",  hint = "hint_left",  stPath = "hint.left",     color = 0xFF58A6FF },
    { id = "swipe_right",name = "右滑",   ev = "swipe_right", hint = "hint_right", stPath = "hint.right",    color = 0xFF58A6FF },
}
function channelById(id)
    for _, c in ipairs(CHANNELS) do if c.id == id then return c end end
    return nil
end

-- 在 FrameLayout 放 label：命中图片显示图片，否则文字（高保真：支持 font / gravity / offset）
-- 复用真机 TightTextView：真机 KeyView 里所有角标（mLongClick/mHint/四个 swipe hint）
-- 都是 TightTextView，只有主标签 mClick 是普通 TextView。TightTextView 的 onMeasure/onDraw
-- 自己按文字像素测量、并用 canvas.drawText(getText().toString()) 绘制——它【不渲染 ImageSpan】。
-- 这正是真机 ▼ 显示成 27x25 小字符三角（dump 虽标 [IMG]，那只是桥接检测到 span 存在），
-- 而工具用普通 TextView 显示 ImageSpan 得到 40x47 大梯形图片的根因，与查图/染色无关。
-- 工具与运行中的输入法同进程，能 bindClass 真机类（日志已证实 com.osfans.trime.Config 可用），
-- 直接复用即可字节级一致；失败则回退普通 TextView（最坏与旧行为相同）。
-- 角标容器：安全渲染下统一用普通 TextView（真机 TightTextView 只比它多一层像素级测量，
-- 对纯文字显示没有差别，而构造真机类会在工具进程里触发 native 初始化）。
function newTightOrTextView()
    return TextView(activity)
end

-- 【r27.40 通用内容渲染入口】严格复刻真机 KeyStyle.getSpan(text) 的语义：
--   内容是【桥接提供的文本】，查到图（path，由 findLabelImage 按真机 findImagePath 语义得到）
--   就显示按字号缩放的图片，查不到就显示文字原文。与按键类别、是否文件名完全无关。
-- 全工具所有显示入口（键盘主标签 / 各通道角标 / 工具栏主标签 / 工具栏角标）统一走这里，
-- 因此任意键的内容——动态文字（单手开/关、悬浮开/关、剪贴板…）、图片文件名、恰好有
-- 同名图的文字——都与真机一致；不再针对某个键或某种后缀做特判。
-- text=显示的文字原文；path=findLabelImage 的结果；返回 true 表示显示了图片。
function drawContentOnView(tv, text, path, textSizeSp)
    local shown = false
    if path then
        -- 图标按 textSize 等比缩放（真机 getSpan 按 textSize 画 ImageSpan，不按原图像素）。
        local targetPx = textSizeSp and math.ceil(dp(textSizeSp)) or 0
        local function scaled(b)
            if not b or targetPx <= 0 then return b end
            local sw, sh = b.getWidth(), b.getHeight()
            if sw <= 0 or sh <= 0 then return b end
            local side = math.max(sw, sh)
            if side == targetPx then return b end
            local nw = math.max(1, math.floor(sw * targetPx / side + 0.5))
            local nh = math.max(1, math.floor(sh * targetPx / side + 0.5))
            local ok, nb = pcall(function() return Bitmap.createScaledBitmap(b, nw, nh, true) end)
            return ok and nb or b
        end
        pcall(function()
            local bmp = scaled(decodeImage(path))
            if bmp then
                local bd = BitmapDrawable(activity.getResources(), bmp)
                bd.setBounds(0, 0, bmp.getWidth(), bmp.getHeight())
                if _ImageSpan and _SpannableString and _Spannable then
                    local ss = _SpannableString(" ")
                    ss.setSpan(_ImageSpan(bd), 0, 1, _Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    tv.setText(ss)
                    shown = true
                end
            end
        end)
        if not shown then
            -- compound drawable 兜底（部分 ROM 上 ImageSpan 不显示时用）
            pcall(function()
                local bmp2 = scaled(decodeImage(path))
                if bmp2 then
                    local bd2 = BitmapDrawable(activity.getResources(), bmp2)
                    bd2.setBounds(0, 0, bmp2.getWidth(), bmp2.getHeight())
                    tv.setText("")
                    tv.setCompoundDrawables(bd2, nil, nil, nil)
                    shown = true
                end
            end)
        end
    end
    if not shown then pcall(function() tv.setText(text) end) end
    return shown
end

-- 【r27.42 统一判图】唯一查图入口：只有内容文本本身是【图片文件名后缀】才查图。
-- 普通文字（"菜单"/"中文"/"▽"/候选词…）一律返回 nil → 显示文字，绝不因为恰好存在
-- 同名 png 就被替换成图。这与用户要求一致：显图与否只看文字后缀，与键类别/通道无关。
-- findLabelImage 内部对普通文字会加 .png 查固定路径（真机 getSpan 语义），这里在入口
-- 用 isImageFileName 拦一道，把"文字查图"收敛为"文件名查图"。
function lookupContentImage(text)
    if not isImageFileName(text) then return nil end
    local p = findLabelImage(text)
    if not p and labelImgIndex then p = labelImgIndex[tostring(text):lower()] end
    return p
end

function addLabelView(fl, label, textSizeSp, textColor, imgPadDp, fontName, gravity, offsetX, offsetY, imgLookup, nativeStyles, pxOffsets, wrapLp, derive, tight, absX, absY, absW, absH)
    -- derive：通道派生路径（"hint"/"long_click"/"hint.up"…），传给 nativeSpan 精确复现
    -- 真机 getSpan 用的 KeyStyle 实例——染色/尺寸必须取自正确实例（g 键 ▼ 就是被主 key
    -- style 染成白色大梯形，真机用 hint style 染成 27x25 灰三角）。nil=主 label。
    -- wrapLp=true：父容器是 WRAP_CONTENT（工具栏按键）。真机 KeyView 的 mClick 用
    -- FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, getGravity(CENTER))，即 gravity
    -- 设在【布局参数】上控制 view 在父容器位置。若此处仍用 MATCH_PARENT + setGravity，
    -- 在 WRAP_CONTENT 父容器里子 view 被测量成内容宽度 → setGravity 失效 → 文字靠左。
    -- 键盘按键父容器是固定尺寸 keyRoot，保持原 MATCH_PARENT 方式（wrapLp=nil）。
    local function setLabelLp(v)
        -- 【r22】absX/absY = 真机 dump 权威布局坐标（getLeft/getTop，相对 keyRoot）：
        -- 必须在 addView 之前把 LP 建好（addView 时一次性 layout），不能在 addView 之后
        -- 再 setLayoutParams——后者只是异步 requestLayout，dump 在同一帧取 getLeft 仍是旧值
        -- （r21 实测：事后改 LP 坐标纹丝不动）。gravity=TOP|LEFT + margins=(absX,absY)
        -- 使 view 左上角精确落在真机坐标，且 dump 打印一致。
        -- 【r27.28】有桥接权威尺寸 absW/absH 时用固定尺寸（真机 getWidth/getHeight），
        -- 不再用 WRAP_CONTENT 让工具字体重新测量。long_click「语 音」等纯文字角标
        -- 原来走工具字体 → 测得宽度≠真机 dumpW → 文字在 view 内按 gravity 排版时视觉偏；
        -- 固定成真机尺寸后，view 框与真机一致，文字排版基准相同。
        if absX ~= nil and absY ~= nil then
            local useW = (type(absW) == "number" and absW > 0) and absW or -2
            local useH = (type(absH) == "number" and absH > 0) and absH or -2
            local lp = FrameLayout.LayoutParams(useW, useH)
            lp.gravity = bitOr(Gravity.TOP, Gravity.LEFT)
            lp.setMargins(absX, absY, 0, 0)
            v.setLayoutParams(lp)
        elseif wrapLp then
            local lp = FrameLayout.LayoutParams(-2, -2)  -- WRAP_CONTENT
            lp.gravity = gravity or Gravity.CENTER
            v.setLayoutParams(lp)
        else
            v.setLayoutParams(FrameLayout.LayoutParams(-1, -1))
        end
    end
    -- 严格按真机 getSpan 语义（通用版）：所有文字元素（click/hint/方向 hint/long_click）
    -- 都用【原始文本】调真机 Config.findImagePath(text+".png") 查图：
    --   · 查到 → 显示真机 KeyStyle.getSpan(text) 渲染的图（染色/缩放由真机决定）；
    --   · 查不到 → 显示文字。
    -- 不做任何按元素类别（hint/swipe/单字符）的特殊分支——真机源码 getSpan 对所有
    -- 元素一视同仁，唯一输入是原始 text，唯一判定是 findImagePath。
    -- 偏移对三条渲染分支（真机 span / 兜底原图 / 纯文字）统一应用，对齐真机
    -- mClick/mHint/mLongClick.setTranslationX/Y(getSize("offset_x"/"offset_y", 0))。
    -- 真机 Style.getSize(key,def)：mTable.get(key) 必须 isint() 才 dp2px，否则直接返回 def(0)。
    -- 也就是说主题里 offset 写成小数（如 1.5）真机会【完全忽略】当成 0。工具旧代码无条件
    -- dp(offset) 会把小数也应用 —— 换主题后位置对不上真机。这里对齐：非 pxOffsets 的值
    -- 只有整数才生效，小数当 0。
    local function realOffset(v)
        if v == nil then return nil end
        local n = tonumber(v)
        if n == nil then return nil end
        if n ~= math.floor(n) then return 0 end   -- 真机 isint()==false → def 0
        return n
    end
    local function applyOffset(v)
        -- 【r22】有真机 dump 权威坐标时，位置完全由 LP.margins 决定，不能再叠加
        -- translation（否则视觉位置 = dump坐标 + offset，与真机 dump 打印值不符）。
        if absX ~= nil and absY ~= nil then
            pcall(function() v.setTranslationX(0); v.setTranslationY(0) end)
            return
        end
        local ox, oy = realOffset(offsetX), realOffset(offsetY)
        if ox or oy then
            pcall(function()
                -- pxOffsets=true：值来自真机 KeyStyle.getSize()，已是像素，绝不能再 dp()。
                local tx = pxOffsets and (ox or 0) or dp(ox or 0)
                local ty = pxOffsets and (oy or 0) or dp(oy or 0)
                v.setTranslationX(tx)
                v.setTranslationY(ty)
            end)
        end
    end
    local lookupText = imgLookup or label
    -- 查图顺序与真机一致：样式目录 → 主题目录 → 数据目录 images，均按 text.png 精确匹配。
    -- 与真机 getSpan 的 findImagePath(text+".png") 逐字一致。不做任何按元素类别的特殊分支。
    -- 所有元素一视同仁：查到图 → 用真机【对应通道实例】的 getSpan（染色/尺寸正确）→ 显示图。
    local imgPath = lookupContentImage(lookupText)  -- 【r27.42】统一后缀判断，普通文字不查图
    if imgPath then
        -- 真机 getSpan 渲染结果：图已按该通道 KeyStyle 的 textColor 染色、缩放到 textSize、
        -- ALIGN_CENTER。derive 决定用哪个实例（hint / long_click / 方向），这是与真机一致的关键。
        local span, spanOK = nativeSpan(lookupText, nativeStyles, derive)
        if spanOK and span then
            local tv = tight and newTightOrTextView() or TextView(activity)
            pcall(function() tv.setText(span) end)
            tv.setGravity(gravity or Gravity.CENTER)
            tv.setSingleLine(true)
            if textSizeSp then tv.setTextSize(textSizeSp) end
            -- TightTextView.onDraw 用 getCurrentTextColor()，必须显式设色才与真机
            -- setHintText/setLongClickText 的 mHintStyle.getTextColor() 一致。
            if tight and type(textColor) == "number" then pcall(function() tv.setTextColor(textColor) end) end
            applyOffset(tv)
            setLabelLp(tv)
            fl.addView(tv)
            return tv
        end
        -- 真机 getSpan 拿不到权威结果时，严格按其语义回退为【文字】：
        -- KeyStyle.getSpan 源码里 findImagePath 找到图后若 LuaBitmap.getLocalBitmap 失败，
        -- 会 catch 异常并 return 原始 text（显示文字），绝不会直接画原图。
        -- 工具旧兜底用 BitmapFactory.decodeFile 直接画原图——BitmapFactory 比真机 LuaBitmap
        -- 宽容，会把真机"回退文字"的图（如 g 键 hint ▼.png）错显成白色图片。删除该兜底，
        -- 让它落到下方纯文字分支，才是真机一致行为。
    end
    local tv = tight and newTightOrTextView() or TextView(activity)
    -- 【r27.40 通用内容渲染】触发条件不再是"label 是不是文件名"，而是
    -- findLabelImage/lookupContentImage 是否查到图——这是真机 getSpan 的唯一判定：
    -- 内容能查到图就显示图，查不到才显示文字。于是 bunny.png、任意带同名图的文字键、
    -- 工具栏角标等所有入口统一受桥接内容驱动，不再逐个按键特判。
    local usePath = imgPath or lookupContentImage(lookupText)
    local imgShown = drawContentOnView(tv, label, usePath, textSizeSp)
    tv.setGravity(gravity or Gravity.CENTER)
    tv.setSingleLine(true)
    if textSizeSp then tv.setTextSize(textSizeSp) end
    if type(textColor) == "number" then pcall(function() tv.setTextColor(textColor) end) end
    -- 字体：默认字体主题下真机与工具都用系统默认字体，字形本身一致。
    -- r27.29 曾试图走 nativeTypefaceFor（ThemeManager.getStyle().getKeyStyle().getFont()）
    -- 取真机完整 fallback 链，但工具进程拿不到真机 Style，43 次全 miss（hit=0 实测），
    -- 纯属无效开销且带来误导诊断 —— r27.31 撤销，回到 nativeFontOf 直设。
    -- 偏移与字体无关：坐标(e=0)/尺度(r=1.0)/尺寸(dumpW×dumpH)/gravity 均已数据核实对齐。
    local tfApplied = false
    if nativeStyles then
        local ntf = nativeFontOf(nativeStyles)
        if ntf then tfApplied = pcall(function() tv.setTypeface(ntf) end) end
    end
    if not tfApplied and fontName then
        local tf = loadTypeface(fontName)
        if tf then pcall(function() tv.setTypeface(tf) end) end
    end
    applyOffset(tv)
    setLabelLp(tv)
    fl.addView(tv)
    return tv
end

function utf8Cut(s, n)
    local c, i = 0, 1
    while i <= #s and c < n do
        local b = s:byte(i)
        if b and b < 0x80 then i = i + 1
        elseif b and b < 0xE0 then i = i + 2
        elseif b and b < 0xF0 then i = i + 3
        else i = i + 4 end
        c = c + 1
    end
    return s:sub(1, i - 1)
end

function buildToolbarPreview(W)
    local tb = styleEnv and styleEnv.toolbar
    if type(tb) ~= "table" then return nil end
    local tbkeys = tb.keys
    -- 稳健判断：桥接数据即使没规范化，也要能识别字符串下标的数组（#tbkeys 会误报 0）
    local tbKeyCount = 0
    if type(tbkeys) == "table" then for _ in pairs(tbkeys) do tbKeyCount = tbKeyCount + 1 end end
    local hasKeys = tbKeyCount > 0
    if not hasKeys and tb.schema_switches ~= true then return nil end

    -- 【r27.32】工具栏改用桥接真机数据：liveKeyTexts.toolbar 是 Java 按 ToolbarView
    -- 里每个 KeyView 输出的结构化快照，e.label=KSCLICK txt（真机最终显示文字，如
    -- 「中文」「悬浮关」，而非脚本内部名 Mode_switch / 文件名 bunny.png）；
    -- e.corners 里 ch=long_click 的 txt 是右上角标。桥接按 seq 顺序，与脚本 tbkeys
    -- 的键顺序一致，按 index 一一对应。桥接某键无文字时回退脚本 evLabel。
    local liveTb = (liveKeyTexts and liveKeyTexts.toolbar) or {}
    local liveTbN = #liveTb
    local function liveTbEntry(i)
        if i >= 1 and i <= liveTbN then return liveTb[i] end
        return nil
    end
    -- 桥接 long_click 角标文字（右上小字）
    local function liveTbLongText(e)
        if not e or type(e.corners) ~= "table" then return nil end
        for _, c in ipairs(e.corners) do
            if c.chan == "long_click" and c.txt and c.txt ~= "" then return c.txt end
        end
        return nil
    end

    local tbH = dp((tonumber(getValue("candidate.height")) or 40) * math.min(1, keyboardHeightScale()))
    TB_PREVIEW_H = tbH          -- 供预览布局取工具栏实际高度（避免读 Java 字段）
    local row = LinearLayout(activity)
    row.setOrientation(LinearLayout.HORIZONTAL)
    row.setGravity(Gravity.CENTER_VERTICAL)
    row.setLayoutParams(LinearLayout.LayoutParams(-1, tbH))
    local tbbg = getValue("toolbar.background")
    if type(tbbg) == "string" then
        local p = findImage(tbbg)
        if p then pcall(function()
            local bmp = decodeImage(p, W, tbH)
            if bmp then row.setBackgroundDrawable(BitmapDrawable(activity.getResources(), bmp)) end
        end) end
    elseif type(tbbg) == "number" then
        pcall(function() row.setBackgroundDrawable(areaDrawable("toolbar", tbbg)) end)
    end

    local tbkey = type(tb.key) == "table" and tb.key or {}
    local pad = type(tbkey.padding) == "table" and tbkey.padding or {}
    local tsize = tonumber(getValue("toolbar.key.text_size")) or tonumber(getValue("key.text_size")) or 20
    local tcolor = getValue("toolbar.key.text_color")
    if type(tcolor) ~= "number" then tcolor = getValue("key.text_color") end

    local itemsLay = LinearLayout(activity)
    itemsLay.setOrientation(LinearLayout.HORIZONTAL)
    itemsLay.setGravity(Gravity.CENTER_VERTICAL)
    local hsv = HorizontalScrollView(activity)
    hsv.setHorizontalScrollBarEnabled(false)
    hsv.addView(itemsLay)
    row.addView(hsv, LinearLayout.LayoutParams(0, tbH, 1))

    local tbStat = { n = 0, pua = 0, samples = {} }
    local function tbKeyView(label, stName, target, longLabel)
        tbStat.n = tbStat.n + 1
        if hasPrivateUse(label) then tbStat.pua = tbStat.pua + 1 end
        -- 采样前 10 个键：label 原文 + 码位。下次「图标还是不显示」时，
        -- 一眼能分出三种情况：label 是空的 / 码位根本不是私用区 / 字体确实没这个字形。
        if #tbStat.samples < 10 then
            local codes = {}
            for _, u in ipairs(utf8Units(tostring(label or ""))) do
                codes[#codes + 1] = string.format("%04X", u.cp)
            end
            tbStat.samples[#tbStat.samples + 1] =
                string.format("[%s]=(%s)", tostring(label or ""), table.concat(codes, " "))
        end
        local st = (type(stName) == "string") and styleEnv[stName] or nil
        local wrap = FrameLayout(activity)
        local bg2 = (type(st) == "table" and st.background) or tbkey.background
        if type(bg2) == "number" then
            local gd = GradientDrawable()
            gd.setColor(bg2)
            gd.setCornerRadius(dp(tonumber((type(st) == "table" and st.corner_radius) or tbkey.corner_radius or 0)))
            wrap.setBackgroundDrawable(gd)
        end
        wrap.setPadding(dp(tonumber(pad.left) or 0), dp(tonumber(pad.top) or 0),
                        dp(tonumber(pad.right) or 0), dp(tonumber(pad.bottom) or 0))
        local isImg = lookupContentImage(label or "") ~= nil  -- 【r27.42】统一后缀判图
        if isImg then wrap.setMinimumWidth(tbH)
        else
            local n = 0
            for _ in tostring(label or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
            if n <= 2 then wrap.setMinimumWidth(tbH) end
        end
        wrap.onClick = function()
            if toolbarEntryDialog then toolbarEntryDialog()
            elseif tbKeysDialog then tbKeysDialog() end
        end
        local ts2 = (type(st) == "table" and tonumber(st.text_size)) or tsize
        local tc2 = (type(st) == "table" and st.text_color) or tcolor
        -- 工具栏字体：真机 ToolbarView 用 getStyle("toolbar").getKeyStyle("key")；
        local tbNativeStyles = { "toolbar.key", "tool", "key" }
        if type(stName) == "string" and stName ~= "" then
            table.insert(tbNativeStyles, 1, stName)
        end
        -- 真机工具栏按键就是 KeyView（ToolbarView 173/179 行），和键盘按键同一套：
        -- mKeyStyle = toolbar.key（回退 keyboard.key）；table 键写了 style 则用
        -- getKeyStyle(o.style, mKeyStyle)。偏移同样走 KeyStyle.getSize(offset_x/y)。
        -- 候选顺序：工具 stName → <stName>（真机 style 名）→ toolbar.key → key。
        -- 优先用 channelField 直接从序列化表取（stName 不含点号，路径可靠），
        -- 单位是主题 dp，交给 addLabelView 走 dp()；native 仅在表值取不到时兜底（px）。
        local tox = tonumber(channelField(stName, "", "offset_x"))
        local toy = tonumber(channelField(stName, "", "offset_y"))
        local tbPx = false
        if tox == nil and toy == nil then
            local tbOffStyles = { "toolbar.key", "key" }
            if type(stName) == "string" and stName ~= "" then table.insert(tbOffStyles, 1, stName) end
            local nx, ny = nativeOffset(tbOffStyles, "offset_x"), nativeOffset(tbOffStyles, "offset_y")
            if nx ~= nil or ny ~= nil then tox, toy, tbPx = nx, ny, true end
        end
        -- 主 click label：字体大小与键盘按键完全一致，不缩放。
        -- 真机工具栏按键就是 KeyView，mClick.setTextSize(mKeyStyle.getTextSize())，
        -- 和键盘主文字同一套（field("text_size") 直接用）。之前多乘 0.65 导致偏小。
        addLabelView(wrap, label or "", ts2,
                     type(tc2) == "number" and tc2 or nil, 8, nil, Gravity.CENTER,
                     tox, toy, nil, tbNativeStyles, tbPx, true)
        -- 真机工具栏键【显示 long_click 的 text】作为角标（用户真机确认）。
        -- 万象里 long_click.label 是私用区图标字符（需 iconfont），纯文字渲染、不查图片，
        -- 用真机字体（toolbar.key / stName），置于键右上角、小字号。
        if longLabel and longLabel ~= "" then
            -- 真机工具栏按键 = KeyView，long_click 角标 gravity 取 style.gravity，
            -- 默认 TOP+CENTER_HORIZONTAL（同键盘 long_click specs），不是写死右上角。
            local lgrav = parseGravity(channelField(stName, "long_click", "gravity"),
                                       Gravity.TOP + Gravity.CENTER_HORIZONTAL)
            local lbox = FrameLayout(activity)
            lbox.setLayoutParams(FrameLayout.LayoutParams(-2, -2, lgrav))
            local ltv = TextView(activity)
            -- 与键盘角标一致：真机 mLongClick.setTextSize(mLongClickStyle.getTextSize(8))，
            -- 取 long_click 自己 style 的 text_size（默认 8），不是主文字 ts2 的一半。
            local lts = tonumber(channelField(stName, "long_click", "text_size")) or 8
            -- 【r27.40】工具栏角标也走统一内容入口：桥接 long_click 文字能查到图就显示图，
            -- 否则显示文字。与键盘角标/addLabelView 同一套真机 getSpan 语义，不再裸 setText。
            local longPath = lookupContentImage(longLabel)
            drawContentOnView(ltv, longLabel, longPath, lts)
            ltv.setTextSize(lts)
            if type(tc2) == "number" then pcall(function() ltv.setTextColor(tc2) end) end
            ltv.setGravity(Gravity.CENTER)
            local lNative = { "toolbar.key", "tool", "key" }
            if type(stName) == "string" and stName ~= "" then table.insert(lNative, 1, stName) end
            -- 字体：默认字体主题回退本地 nativeFontOf（r27.31 撤销无效的真机字体链）。
            local ntf = nativeFontOf(lNative)
            if ntf then pcall(function() ltv.setTypeface(ntf) end) end
            -- 角标偏移：真机 long_click 角标用 getLongClickKeyStyle()（即 style.long_click）。
            local lox = tonumber(channelField(stName, "long_click", "offset_x"))
            local loy = tonumber(channelField(stName, "long_click", "offset_y"))
            local lpx = false
            if lox == nil and loy == nil then
                local lOffStyles = { "toolbar.key.long_click", "key.long_click" }
                if type(stName) == "string" and stName ~= "" then
                    table.insert(lOffStyles, 1, stName .. ".long_click")
                end
                local nx, ny = nativeOffset(lOffStyles, "offset_x"), nativeOffset(lOffStyles, "offset_y")
                if nx ~= nil or ny ~= nil then lox, loy, lpx = nx, ny, true end
            end
            if lox or loy then
                pcall(function()
                    ltv.setTranslationX(lpx and (lox or 0) or dp(lox or 0))
                    ltv.setTranslationY(lpx and (loy or 0) or dp(loy or 0))
                end)
            end
            ltv.setLayoutParams(FrameLayout.LayoutParams(-2, -2))
            lbox.addView(ltv)
            wrap.addView(lbox)
        end
        ;(target or itemsLay).addView(wrap, LinearLayout.LayoutParams(-2, tbH))
    end

    if tb.schema_switches == true then tbKeyView("方案") end
    if hasKeys then
        -- 排序后遍历：兼容 number 下标与字符串下标（桥接序列化可能是 ["1"]）
        local tbIdx = {}
        for k in pairs(tbkeys) do tbIdx[#tbIdx + 1] = numKeyFix(k) end
        table.sort(tbIdx)
        -- 复刻真机 Event.getLabel()：
        --  · string 事件 → resolveEventLabel（preset_keys / 去 {}）
        --  · number 事件 → 数字转串
        --  · table 事件（万象工具栏普遍如此）→ 真机 new Event(o).getLabel()：
        --      toggle+states → states[当前态]；否则 label / select / send / text 字段。
        --      → 返回 nil → 落到 fallback "?"，这就是功能键显示问号的根因。
        local function evLabel(x)
            if type(x) == "string" then
                local r = resolveEventLabel(x)
                return (r ~= nil and r ~= "") and r or x
            elseif type(x) == "number" then
                return tostring(x)
            elseif type(x) == "table" then
                local toggle = x.toggle
                if type(toggle) == "string" and toggle ~= "" and type(x.states) == "table" then
                    local st = x.states[1] or x.states["1"]
                    if st ~= nil and st ~= "" then return tostring(st) end
                end
                if x.label ~= nil and x.label ~= "" then return tostring(x.label) end
                if x.select ~= nil and x.select ~= "" then return tostring(x.select) end
                if x.send ~= nil and x.send ~= "" then return evLabel(x.send) end
                if x.text ~= nil and x.text ~= "" then return tostring(x.text) end
            end
            return nil
        end
        -- 【r27.32】桥接文字覆盖 helper：桥接 e.label（真机显示文字）优先，
        -- 空则回退脚本推导值（图片键桥接 txt 常为空，回退到 bunny.png 文件名，
        -- 再由 addLabelView 的图片分支渲染成图片）。
        local tbSeq = 0
        local function bridgedLabel(fallback, i)
            local le = liveTbEntry(i)
            if le and le.label and le.label ~= "" then return le.label end
            -- 【r27.35】桥接已到位但该键 txt 为空 = 真机这一键没有文字（图标/空白键）。
            -- 此时不再回退脚本内部名（Mode_switch / schema_name / 占位符），那不是桥接数据。
            -- 唯一例外：fallback 是图片文件名（bunny.png 等）——保留它仅用于找图，
            -- addLabelView 的图片分支会显示图片而非文件名文字。
            if le then
                if isImageFileName(fallback) then
                    return fallback
                end
                return ""
            end
            -- 桥接键越界（脚本键比桥接多）：桥接没覆盖到，才用脚本兜底
            return fallback
        end
        local function bridgedLong(fallback, i)
            local lt = liveTbLongText(liveTbEntry(i))
            if lt and lt ~= "" then return lt end
            return fallback
        end
        for _, ti in ipairs(tbIdx) do
            tbSeq = tbSeq + 1
            local o = tbkeys[ti] or tbkeys[tostring(ti)]
            if type(o) == "string" then
                tbKeyView(bridgedLabel(evLabel(o) or o, tbSeq), nil, nil, bridgedLong(nil, tbSeq))
            elseif type(o) == "table" then
                local label, stName = nil, nil
                if type(o.options) == "table" then
                    -- 真机 Switch.getState()=states[reset]，reset 默认 0 → states[1]
                    local states = type(o.states) == "table" and o.states or nil
                    label = (states and (states[1] or states["1"])) or o.name or ""
                else
                    -- 真机 ToolbarView：click 非 nil 时走 new Key(o)，显示文字 = Event(o.click).getLabel()
                    -- （从 click table 内部 label/toggle/select/send 取）；顶层 o.label 仅作兜底。
                    label = evLabel(o.label)  -- 顶层 label（任意类型）
                    if not label or label == "" then
                        label = evLabel(o.click)          -- 主：click table 内部（万象工具栏真源）
                    end
                    if not label or label == "" then
                        label = evLabel(o.send or o.text) -- 兜底：send / text / select
                    end
                    if not label or label == "" then
                        label = evLabel(o.select)
                    end
                    label = label or ""
                end
                if type(o.style) == "string" then stName = o.style end
                -- 真机工具栏显示 long_click 的 text（用户真机确认）：从 long_click table
                -- 内部 label 取，万象是私用区图标字符，需真机字体渲染。
                local longLabel = nil
                if type(o.long_click) ~= "nil" then
                    longLabel = evLabel(o.long_click)
                    if not longLabel or longLabel == "" then
                        if type(o.long_click) == "table" then
                            longLabel = evLabel(o.long_click.label or o.long_click.text or o.long_click.send)
                        end
                    end
                end
                tbKeyView(bridgedLabel(label or "", tbSeq), stName, nil, bridgedLong(longLabel, tbSeq))
            end
        end
        -- 【r27.32】桥接键数多于脚本键数时（真机 6 键 vs 脚本 4 键），把脚本没覆盖到的
        -- 尾部桥接键（如「悬浮关」「🐰 图片键」）按真机顺序补渲染，样式用默认 toolbar.key。
        -- 【r27.50】真机最右的收起键 mHide 是独立 KeyView（ToolbarView.root 下最后一个
        -- addView），桥接会把它当 toolbar 组最后一个键抓进来。工具下方已固定画了一个
        -- hideText 键，这里若再补渲染一次，最右边就出现两个 ▽。故跳过最后一个桥接键。
        if liveTbN > tbSeq then
            for i = tbSeq + 1, liveTbN - 1 do
                local le = liveTbEntry(i)
                local lb = (le and le.label) or ""
                local ll = liveTbLongText(le)
                -- 桥接 label 为空时，尝试从该键的角落里找任一非空文字，避免整键空白。
                if (not lb or lb == "") and le and type(le.corners) == "table" then
                    for _, c in ipairs(le.corners) do
                        if c.txt and c.txt ~= "" then lb = c.txt; break end
                    end
                end
                tbKeyView(lb, nil, nil, ll)
            end
        end
    end
    local hideText = "▽"
    if type(tb.hide) == "table" and type(tb.hide.text) == "string" then hideText = tb.hide.text
    elseif type(tb.hide) == "string" then hideText = tb.hide end
    tbKeyView(hideText, nil, row)
    -- 一次性诊断：工具栏里有多少私用区字符键、图标字体到底找到没有。
    -- 下次「图标又不显示」时，看这条就能分清是字体没找到还是字符本身是空的。
    if not _tbDiagDone then
        _tbDiagDone = true
        pcall(function()
            logErr("工具栏诊断", string.format(
                "键=%d，私用区字符键=%d，图标字体=%s，主题字体池=%d，toolbar.elevation=%s\n键表：%s",
                tbStat.n, tbStat.pua,
                (iconFontFallback() ~= nil) and "已找到" or "未找到",
                #themeFontList(),
                tostring(getValue("toolbar.elevation")),
                table.concat(tbStat.samples, " ")))
        end)
    end
    return row
end

-- ========== 候选栏预览 ==========
-- 示例文字只影响工具预览，不写进主题。
-- 用【普通打字时会出现的候选词】：之前用「键盘 / 设置 / 输入法」这类词，
-- 它们和界面上的按钮同名，预览里一点就以为是功能入口，容易误导。
local PREVIEW_WORDS_KEY = "studio_preview_words"
local DEFAULT_PREVIEW_WORDS = "你好,我们,今天,什么"
-- 旧版默认值。点过一次「应用」就会写进偏好，换默认后这些用户仍看到旧词，
-- 这里把旧默认当作「未设置」处理，让新默认对老用户也生效。
local LEGACY_PREVIEW_WORDS = "你好,输入法,键盘,设置"
function previewCandidateWords()
    local raw = tostring(readPref(PREVIEW_WORDS_KEY, DEFAULT_PREVIEW_WORDS) or "")
    if raw == "" or raw == LEGACY_PREVIEW_WORDS then raw = DEFAULT_PREVIEW_WORDS end
    -- 【必须按整字节切】旧写法 gmatch("[^,，;；]+") 在 Lua 5.1 里是按【字节】匹配的：
    -- 「，」= EF BC 8C、「；」= EF BC 9B，字符类因此排除了字节 0xEF/0xBC/0x8C/0x9B。
    -- 汉字「盘」= E7 9B 98 正好含 0x9B → 被劈成「键」+ 半个字节，候选栏就出现乱码。
    -- 先把全角逗号/分号换成半角逗号（gsub 的多字节字面量是整串匹配，安全），再按 "," 切。
    raw = raw:gsub("，", ","):gsub("；", ","):gsub(";", ",")
    local out = {}
    for w in raw:gmatch("[^,]+") do
        w = w:gsub("^%s+", ""):gsub("%s+$", "")
        if w ~= "" then out[#out + 1] = w end
        if #out >= 12 then break end
    end
    if #out == 0 then
        for w in DEFAULT_PREVIEW_WORDS:gmatch("[^,]+") do out[#out + 1] = w end
    end
    return out
end
function setPreviewCandidateWords(s)
    return pcall(function()
        local PM = luajava.bindClass("android.preference.PreferenceManager")
        local sp = PM.getDefaultSharedPreferences(activity)
        local ed = sp.edit()
        ed.putString(PREVIEW_WORDS_KEY, tostring(s or ""))
        ed.apply()
    end)
end

-- 点候选栏直接改候选样式：与真机 KeyStyle(candidate) 对齐的完整编辑面板。
-- 字段严格对应 CandidateView / CandidateAdapter 读取的键：
--   candidate.height / background / text_size / text_color
--   candidate.pressed.background / text_color（当前候选高亮）
--   candidate.comment.text_size / text_color / text（注释）
--   candidate.key.text / text_size / text_color / background（右侧更多候选按钮）
--   candidate.corner_radius（候选按钮圆角）
function candidateSettingsDialog()
    if not styleEnv then toast("样式还没加载好") return end
    local lay = LinearLayout(activity)
    lay.setOrientation(LinearLayout.VERTICAL)
    lay.setPadding(dp(14), dp(6), dp(14), dp(6))

    local function lab(t)
        local tv = TextView(activity)
        tv.setText(t); tv.setTextSize(11); tv.setTextColor(0xFF8B949E)
        tv.setPadding(0, dp(8), 0, dp(2))
        lay.addView(tv)
    end
    local function numEdit(init, hint)
        local et = EditText(activity)
        et.setSingleLine(true); et.setInputType(2)
        et.setText(init ~= nil and tostring(init) or "")
        et.setHint(hint or "")
        lay.addView(et, LinearLayout.LayoutParams(-1, -2))
        return et
    end
    local function txtEdit(init, hint)
        local et = EditText(activity)
        et.setSingleLine(true)
        et.setText(init ~= nil and tostring(init) or "")
        et.setHint(hint or "")
        lay.addView(et, LinearLayout.LayoutParams(-1, -2))
        return et
    end
    -- 颜色按钮：state.value 保存选择结果，应用时再写回（颜色控件本身无 reader）
    local function colorBtn(path, label)
        local st = { value = tonumber(getValue(path)) }
        local b = Button(activity)
        b.setAllCaps(false); b.setTextSize(11)
        local function paint()
            local n = st.value
            if type(n) == "number" then
                b.setText(label .. "  " .. string.format("#%08X", n))
                pcall(function() b.setBackgroundColor(n) end)
                local lum = ((math.floor(n / 0x10000) % 0x100) * 299
                    + (math.floor(n / 0x100) % 0x100) * 587 + (n % 0x100) * 114) / 1000
                pcall(function() b.setTextColor(lum > 128 and 0xFF000000 or 0xFFFFFFFF) end)
            else
                b.setText(label .. "  未设置（跟随继承）")
                pcall(function() b.setBackgroundColor(0xFF30363D) end)
                pcall(function() b.setTextColor(0xFF8B949E) end)
            end
        end
        paint()
        b.onClick = function()
            colorDialog("选择" .. label, type(st.value) == "number" and st.value or nil,
                function(v) if v then st.value = v; paint() end end)
        end
        lay.addView(b, LinearLayout.LayoutParams(-1, -2))
        return st
    end

    lab("── 基础（candidate）──")
    lab("候选字号 candidate.text_size")
    local tsEt = numEdit(tonumber(getValue("candidate.text_size")) or 20, "例如 22")
    lab("候选栏高度 candidate.height（dp）")
    local hEt = numEdit(tonumber(getValue("candidate.height")) or 44, "例如 44")
    lab("候选按钮圆角 candidate.corner_radius（dp）")
    local crEt = numEdit(tonumber(getValue("candidate.corner_radius")), "例如 6")
    local textColor = colorBtn("candidate.text_color", "候选文字色 text_color")

    lab("── 当前候选高亮（candidate.pressed）──")
    local hlBgColor = colorBtn("candidate.pressed.background", "高亮背景 pressed.background")
    local hlTextColor = colorBtn("candidate.pressed.text_color", "高亮文字 pressed.text_color")
    -- 预览用：是否把第一个候选显示成高亮（不写入主题）
    local hlState = { value = (_studioPreviewHl ~= false) }
    local hlBtn = Button(activity)
    hlBtn.setAllCaps(false); hlBtn.setTextSize(11)
    local function paintHl() hlBtn.setText("预览高亮第一个候选：" .. (hlState.value and "开" or "关")) end
    paintHl()
    hlBtn.onClick = function() hlState.value = not hlState.value; paintHl() end
    lay.addView(hlBtn, LinearLayout.LayoutParams(-1, -2))

    lab("── 候选注释（candidate.comment）──")
    local cmtEt = txtEdit(getValue("candidate.comment.text"), "例如 说明（留空=不显示注释）")
    local cmtTsEt = numEdit(tonumber(getValue("candidate.comment.text_size")), "例如 12")
    local cmtColor = colorBtn("candidate.comment.text_color", "注释文字色 comment.text_color")

    lab("── 右侧更多候选按钮（candidate.key）──")
    local keyTextEt = txtEdit(getValue("candidate.key.text"), "例如 ▽（留空=▽）")
    local keyTsEt = numEdit(tonumber(getValue("candidate.key.text_size")), "例如 20")
    local keyColor = colorBtn("candidate.key.text_color", "按钮文字色 key.text_color")
    local keyBgColor = colorBtn("candidate.key.background", "按钮背景 key.background")

    lab("─ 候选栏整体背景 candidate.background（颜色；图片请在「样式编辑/键盘设置」里填）─")
    local cdBgColor = colorBtn("candidate.background", "候选栏背景色 background")

    lab("示例候选（逗号分隔，仅预览用，不写入主题）")
    local wEt = txtEdit(table.concat(previewCandidateWords(), ","), "你好,我们,今天,什么")

    local sv = ScrollView(activity)
    sv.addView(lay)
    local dlg = LuaDialog(activity)
    dlg.setTitle("候选栏设置（与真机样式同步）")
    dlg.setView(sv)
    dlg.setButton("应用", function()
        local n = 0
        local function applyNum(path, et)
            local init = tonumber(getValue(path))
            local v = tonumber(tostring(et.getText()):match("[-%d%.]+") or "")
            if v and v ~= init then setValue(path, v); n = n + 1 end
        end
        local function applyColor(path, st)
            local v = st.value
            if v ~= tonumber(getValue(path)) then
                if type(v) == "number" then setValue(path, v) else unsetStyleValue(path) end
                n = n + 1
            end
        end
        local function applyText(path, et, fallback)
            local s = tostring(et.getText())
            if s == "" and fallback then s = fallback end
            local init = getValue(path)
            if s ~= tostring(init or "") then
                if s == "" then unsetStyleValue(path) else setValue(path, s) end
                n = n + 1
            end
        end
        applyNum("candidate.text_size", tsEt)
        applyNum("candidate.height", hEt)
        applyNum("candidate.corner_radius", crEt)
        applyColor("candidate.text_color", textColor)
        applyColor("candidate.pressed.background", hlBgColor)
        applyColor("candidate.pressed.text_color", hlTextColor)
        applyText("candidate.comment.text", cmtEt, nil)
        applyNum("candidate.comment.text_size", cmtTsEt)
        applyColor("candidate.comment.text_color", cmtColor)
        applyText("candidate.key.text", keyTextEt, nil)
        applyNum("candidate.key.text_size", keyTsEt)
        applyColor("candidate.key.text_color", keyColor)
        applyColor("candidate.key.background", keyBgColor)
        applyColor("candidate.background", cdBgColor)
        _studioPreviewHl = hlState.value
        setPreviewCandidateWords(tostring(wEt.getText()))
        dlg.dismiss()
        renderPreview()
        toast(n > 0 and ("已应用 " .. n .. " 项候选栏样式（保存主题时写入）")
                    or "仅更新了预览选项")
    end)
    dlg.setButton2("取消", function() dlg.dismiss() end)
    dlg.show()
end

-- 给候选「按钮」套背景：真机 CandidateAdapter 高亮用 candidate.pressed 的 background、
-- 普通态无背景；背景可图片或颜色，圆角/边框取同一 KeyStyle 的 corner_radius/stroke_*。
local function candItemBackground(view, prefix, reqW, reqH)
    local bg = getValue(prefix .. ".background")
    local applied = false
    if type(bg) == "string" then
        local p = findImage(bg)
        if p then pcall(function()
            local bmp = decodeImage(p, reqW or dp(120), reqH or dp(40))
            if bmp then view.setBackgroundDrawable(BitmapDrawable(activity.getResources(), bmp)); applied = true end
        end) end
    end
    if not applied and type(bg) == "number" then
        pcall(function()
            view.setBackgroundDrawable(areaDrawable(prefix, bg))
            applied = true
        end)
    end
    return applied
end

function buildCandidatePreview(W)
    local cd = styleEnv and styleEnv.candidate
    if type(cd) ~= "table" then return nil end
    -- 与 renderPreviewImpl 外层 cdH 用同一个 scale，避免内部高度和外部行高不一致
    local cdH = dp((tonumber(getValue("candidate.height")) or 44) * math.min(1, keyboardHeightScale()))
    local row = LinearLayout(activity)
    row.setOrientation(LinearLayout.HORIZONTAL)
    row.setGravity(Gravity.CENTER_VERTICAL)
    row.setLayoutParams(LinearLayout.LayoutParams(-1, cdH))
    -- 候选栏整体背景：真机 root 背景取 candidate.background
    local cdbg = getValue("candidate.background")
    if type(cdbg) == "string" then
        local p = findImage(cdbg)
        if p then pcall(function()
            local bmp = decodeImage(p, W, cdH)
            if bmp then row.setBackgroundDrawable(BitmapDrawable(activity.getResources(), bmp)) end
        end) end
    elseif type(cdbg) == "number" then
        pcall(function() row.setBackgroundDrawable(areaDrawable("candidate", cdbg)) end)
    end

    local cts = tonumber(getValue("candidate.text_size")) or 20
    local ctc = getValue("candidate.text_color")
    if type(ctc) ~= "number" then ctc = getValue("key.text_color") end
    -- 字体：真机 Style.getFont 优先级 candidate.font → candidate.text_font → keyboard.font
    local cdFont = resolveUIFont({"candidate.font", "candidate.text_font", "candidate.key.font",
        "font.candidate", "font.candidate_font", "candidate_font"})
    -- 候选栏字体：本地 nativeFontOf（r27.31 撤销无效的真机字体链）。
    local cdTf = nativeFontOf({ "candidate", "candidate.key", "key" })
    local function setCandFont(tv)
        if cdTf then pcall(function() tv.setTypeface(cdTf) end)
        elseif cdFont then pcall(function() local tf = loadTypeface(cdFont); if tf then tv.setTypeface(tf) end end) end
    end
    -- 高亮态（真机 candidate.pressed）：背景 + 文字色，缺省回退到普通态
    local hlBg = getValue("candidate.pressed.background")
    local hlTc = getValue("candidate.pressed.text_color")
    if type(hlTc) ~= "number" then hlTc = ctc end
    -- 注释样式（真机 candidate.comment）
    local cmtTs = tonumber(getValue("candidate.comment.text_size")) or 12
    local cmtTc = getValue("candidate.comment.text_color")
    if type(cmtTc) ~= "number" then cmtTc = ctc end
    local showComment = getValue("candidate.comment.text") ~= nil

    -- 横向滚动容器：真机 CandidateView 用 RecyclerView 横向列表
    local itemsLay = LinearLayout(activity)
    itemsLay.setOrientation(LinearLayout.HORIZONTAL)
    itemsLay.setGravity(Gravity.CENTER_VERTICAL)
    local hsv = HorizontalScrollView(activity)
    hsv.setHorizontalScrollBarEnabled(false)
    hsv.addView(itemsLay)
    row.addView(hsv, LinearLayout.LayoutParams(0, cdH, 1))

    local words = previewCandidateWords()
    local function candOnClick() candidateSettingsDialog() end
    for i, w in ipairs(words) do
        -- 第一个候选高亮，模拟真机「当前候选」；其余普通态（可在设置面板关掉）
        local isHl = (i == 1) and (_studioPreviewHl ~= false)
        local item = LinearLayout(activity)
        item.setOrientation(LinearLayout.VERTICAL)
        item.setGravity(Gravity.CENTER)
        item.setPadding(dp(10), dp(1), dp(10), dp(1))
        item.setMinimumHeight(cdH)
        if isHl then candItemBackground(item, "candidate.pressed", dp(160), cdH) end
        if showComment then
            local cm = TextView(activity)
            cm.setText(getValue("candidate.comment.text"))
            cm.setTextSize(math.max(7, cmtTs))
            if type(cmtTc) == "number" then pcall(function() cm.setTextColor(cmtTc) end) end
            cm.setGravity(Gravity.CENTER)
            setCandFont(cm)
            item.addView(cm, LinearLayout.LayoutParams(-2, -2))
        end
        local tv = TextView(activity)
        tv.setText(w)
        tv.setTextSize(math.max(8, cts))
        local tc = isHl and hlTc or ctc
        if type(tc) == "number" then pcall(function() tv.setTextColor(tc) end) end
        setCandFont(tv)
        tv.setGravity(Gravity.CENTER)
        item.addView(tv, LinearLayout.LayoutParams(-2, -2))
        item.onClick = candOnClick
        itemsLay.addView(item, LinearLayout.LayoutParams(-2, -1))
    end

    -- 右侧「更多候选 / 隐藏」按钮：真机 CandidateView 用 candidate.key 的完整 KeyStyle，
    -- 文字 = candidate.key.text（默认 ▽），点击 = 有候选→展开候选面板、无候选→隐藏键盘。
    local more = TextView(activity)
    local moreText = getValue("candidate.key.text")
    if type(moreText) ~= "string" or moreText == "" then moreText = "▽" end
    local kTs = tonumber(getValue("candidate.key.text_size")) or cts
    -- 【r27.42】候选栏右侧 hide/更多按钮纳入统一后缀判图：文字是图片文件名后缀
    -- （如 hide.png）就显示图，否则显示文字。候选【词】本身仍不查图（见上方遍历）。
    local morePath = lookupContentImage(moreText)
    drawContentOnView(more, moreText, morePath, math.max(8, kTs))
    local kTc = getValue("candidate.key.text_color")
    if type(kTc) ~= "number" then kTc = type(ctc) == "number" and ctc or 0xFF888888 end
    more.setTextSize(math.max(8, kTs))
    pcall(function() more.setTextColor(kTc) end)
    -- 按钮背景走 candidate.key 的 KeyStyle（颜色/图片 + 圆角）
    candItemBackground(more, "candidate.key", dp(48), cdH)
    local moreTf = cdTf or nativeFontOf({ "candidate", "key" })
    if moreTf then pcall(function() more.setTypeface(moreTf) end)
    elseif cdFont then pcall(function() local tf = loadTypeface(cdFont); if tf then more.setTypeface(tf) end end) end
    more.setGravity(Gravity.CENTER)
    more.setPadding(dp(6), 0, dp(6), 0)
    more.onClick = function()
        -- 有虚拟候选 → 模拟真机 showExtractedCandidatesView（弹出候选大字面板）
        if #words > 0 then showExtractedCandidates(table.concat(words, " "))
        else toast("（真机此处收起键盘）") end
    end
    row.addView(more, LinearLayout.LayoutParams(dp(44), -1))
    -- 点候选栏空白处 → 候选栏设置
    row.onClick = candOnClick
    return row
end

-- 模拟真机「展开更多候选」的全屏大字候选面板（点击右侧 hide/more 按钮触发）
function showExtractedCandidates(text)
    local sv = ScrollView(activity)
    local lay = LinearLayout(activity)
    lay.setOrientation(LinearLayout.VERTICAL)
    lay.setGravity(Gravity.CENTER)
    lay.setPadding(dp(16), dp(24), dp(16), dp(24))
    local tv = TextView(activity)
    tv.setText(text)
    tv.setTextSize(math.max(22, tonumber(getValue("candidate.text_size")) or 22))
    tv.setGravity(Gravity.CENTER)
    local ctc = getValue("candidate.text_color")
    if type(ctc) ~= "number" then ctc = 0xFF222222 end
    pcall(function() tv.setTextColor(ctc) end)
    local cdTf = nativeFontOf({ "candidate", "key" })
    if cdTf then pcall(function() tv.setTypeface(cdTf) end) end
    lay.addView(tv, LinearLayout.LayoutParams(-1, -2))
    local tip = TextView(activity)
    tip.setText("（真机：点候选上屏 / 再次点此按钮收起）")
    tip.setTextSize(10); tip.setTextColor(0xFF8B949E); tip.setGravity(Gravity.CENTER)
    lay.addView(tip, LinearLayout.LayoutParams(-1, -2))
    sv.addView(lay)
    local dlg = LuaDialog(activity)
    dlg.setTitle("更多候选")
    dlg.setView(sv)
    dlg.setButton("关闭", function() dlg.dismiss() end)
    dlg.show()
end

-- 取某通道样式表的字段值：先按该通道相对路径（含 styleEdits 覆盖），再回退 key 主样式
-- 按真机 Style.getKeyStyle("hint", this) 的 __index 继承链解析样式字段。
-- 真机链：stName.hint.up → stName.hint → stName → key.hint.up → key.hint → key。
-- ch 是相对子路径（"" / "long_click" / "hint" / "hint.up" / "pressed" / "pressed.hint.up" …）
function subCandidates(p)
    local segs = {}
    if p and p ~= "" then for s in p:gmatch("[^%.]+") do segs[#segs + 1] = s end end
    local out = {}
    for i = #segs, 1, -1 do out[#out + 1] = table.concat(segs, ".", 1, i) end
    for i = 2, #segs do out[#out + 1] = table.concat(segs, ".", i) end
    out[#out + 1] = ""
    return out
end
local UNSET = "\255UNSET\255"
-- "..offset_x=6" 这种 `..` 开头的真实路径）。必须把它当单个 key 直接索引，
-- 绝不能参与点号分段：否则 "." .. "." .. "background" = "..background"，
-- parsePath 按 [^%.]+ 吞掉空段 → {"background"}，取成顶层字段，
-- 句号键的背景/字体/圆角/偏移全部丢失。逗号键 "," 不含点号故此前正常。
local function rawStyleGet(rootName, pre, fieldName)
    if not styleEnv then return nil end
    local node = styleEnv[rootName]           -- 单个 key，绝不 parsePath
    if pre ~= "" then
        for seg in pre:gmatch("[^%.]+") do
            if type(node) ~= "table" then return nil end
            node = node[seg]
        end
    end
    if type(node) ~= "table" then return nil end
    return node[fieldName]
end
function channelField(stName, ch, key)
    local roots = {}
    if stName and stName ~= "" and stName ~= "key" then roots[#roots + 1] = stName end
    roots[#roots + 1] = "key"
    for _, root in ipairs(roots) do
        for _, pre in ipairs(subCandidates(ch)) do
            -- styleEdits 覆盖：沿用原拼接键格式，保证 studio 内编辑仍能生效
            local path = (pre ~= "") and (root .. "." .. pre .. "." .. key) or (root .. "." .. key)
            local edited = styleEdits[path]
            if edited ~= nil and edited ~= UNSET then return edited end
            local v = rawStyleGet(root, pre, key)
            if v ~= nil and v ~= UNSET then return v end
        end
    end
    return nil
end

-- 编辑面板的"当前值"回显：与真机渲染完全一致的取值口径。
-- 旧实现用 getValue(精确路径)，默认主题只在 key 主表定义少数字段，子表(pressed/hint/
-- long_click/margins…)大多没直接写 → 精确取值几乎全是 nil → 面板一大片"未设置"，
-- 但真机渲染走 channelField 的 __index 继承链(stName.hint→stName→key)其实是有值的。
-- 这里先走继承链，取不到再套渲染兜底默认值，让面板显示"该键实际生效值"。
local function isCornerStylePath(ch)
    return (ch and ch ~= "") and (ch:find("hint", 1, true) ~= nil or ch:find("long_click", 1, true) ~= nil) or false
end
local function defaultStyleValue(ch, f)
    local corner = isCornerStylePath(ch)
    if f == "text_color" then return corner and 0x99FFFFFF or 0xFF000000 end
    if f == "text_size" then return corner and 8 or 18 end
    if f == "show" then return true end
    if f == "offset_x" or f == "offset_y" or f == "corner_radius" or f == "stroke_width"
        or f == "elevation" or f == "left" or f == "top" or f == "right" or f == "bottom"
        or f == "translation_x" or f == "translation_y" or f == "translation_z" then return 0 end
    if f == "scale_x" or f == "scale_y" then return 1 end
    return nil
end
-- 面板回显值：先按继承链解析生效值，整条链都没有再取渲染缺省值。
function effectiveStyleValue(stName, ch, f)
    local v = channelField(stName, ch or "", f)
    if v == nil then v = defaultStyleValue(ch, f) end
    return v
end

-- 严格复刻真机 KeyStyle.hasKey(k) = !mTable.rawget(k).isnil()：只认样式表【直接定义】的子键。
-- 真机建角标 View 前必须先过这一关（见 KeyView.java）：
--   setHintText 638 行        : if (!mKeyStyle.hasKey("hint"))        return;
--   setLongClickText 598 行   : if (!mKeyStyle.hasKey("long_click"))  return;
--   initKey 886/899/912/925 行: if (mHintKeyStyle.hasKey("up"/"down"/"left"/"right")) ... addHint(...)
-- 之前工具只判 channelField(show)~=false（show 会沿 key.hint→key 继承回退），漏掉 hasKey，
-- 于是"有事件但样式未定义该通道子键"的键也被画了角标——万象 g 键的下滑 ▼ 正是如此。
-- ch: "hint" / "long_click" / "hint.up" / "hint.down" / "hint.left" / "hint.right"
-- 子键必须在【最终样式节点】上 rawget：hint.xxx 的父节点是 hint（可来自 stName 或回退 key）。
local function channelHasKeyStyle(stName, ch)
    local parent, child = ch:match("^(.*)%.([^%.]+)$")
    if not parent then parent, child = "", ch end
    local roots = {}
    if stName and stName ~= "" and stName ~= "key" then roots[#roots + 1] = stName end
    roots[#roots + 1] = "key"
    for _, root in ipairs(roots) do
        local node = styleEnv and styleEnv[root]
        if parent ~= "" then
            for seg in parent:gmatch("[^%.]+") do
                if type(node) ~= "table" then node = nil; break end
                node = rawget(node, seg)
            end
        end
        if type(node) == "table" and rawget(node, child) ~= nil then return true end
    end
    return false
end

-- 取某 style 的 margins/padding 四边值（含 key 继承链），对齐 KeyView 的
-- mKeyStyle.getStyle("margins"/"padding").getSize(...)。主题里值单位按 dp 处理。
local function styleInset4(stName, which)
    local v = channelField(stName, "", which)
    if type(v) ~= "table" then
        -- 单一数值：四边相同
        local n = tonumber(v)
        if n then return { left = n, top = n, right = n, bottom = n } end
        return {}
    end
    return {
        left = tonumber(v.left), top = tonumber(v.top),
        right = tonumber(v.right), bottom = tonumber(v.bottom),
    }
end

-- 生成按键背景 Drawable（颜色 / 图片 + 圆角 + 描边），严格对齐 Style.getDrawable：
--   真机 Style.getDrawable：radiusPx = dp(corner_radius)（不缩放）；
--   strokeWidth = dp(stroke_width)，strokeColor = stroke_color，strokeWidth>0 才描边。
-- ========== 图片解码缓存（防 OOM：这是「偶尔闪退」最容易被忽略的一处） ==========
-- 真实主题的图片背景常见 1000~4000 px。BitmapFactory.decodeFile 不采样会把整张图按
-- ARGB_8888 展开（4000×4000 ≈ 61 MB），而预览每重建一次就要为每个键解码一次背景图：
-- 36 键 × 2（普通 + 按下态）+ 工具栏 + 候选栏，一次拖动滑块就能触发几十上百次全尺寸解码
-- → 堆被吃满 → OutOfMemoryError / native 分配失败 → 同进程的输入法直接闪退。
-- 这里做两件事：
--   ① 按目标显示尺寸算 inSampleSize，绝不把整张大图展开；
--   ② 同一路径 + 同一参数只解码一次，后续复用同一张 Bitmap。
-- 淘汰时【不能 recycle】：旧 Bitmap 仍被 BitmapDrawable / View 引用，
-- recycle 后下一次绘制会抛 "trying to use a recycled bitmap"，那同样是崩溃。
local bmpCache, bmpCacheN, BMP_CACHE_MAX = {}, 0, 48

local function bmpCachePut(k, v)
    if bmpCache[k] == nil then
        if bmpCacheN >= BMP_CACHE_MAX then bmpCache, bmpCacheN = {}, 0 end
        bmpCacheN = bmpCacheN + 1
    end
    bmpCache[k] = v
    return v
end

-- reqW/reqH = 目标显示尺寸（px）；传 nil/0 时只做总像素上限保护
local bmpOptionsUsable = true   -- 个别机型/AndroLua 版本拿不到 BitmapFactory.Options 时降级
function decodeImage(path, reqW, reqH)
    if type(path) ~= "string" or path == "" then return nil end
    local key = "d|" .. path .. "|" .. tostring(reqW or 0) .. "x" .. tostring(reqH or 0)
    local hit = bmpCache[key]
    if hit ~= nil then return hit or nil end
    local bmp = nil
    if bmpOptionsUsable then
        local ok, r = pcall(function()
            local o1 = BitmapFactory.Options()
            o1.inJustDecodeBounds = true
            BitmapFactory.decodeFile(path, o1)
            local w, h = o1.outWidth, o1.outHeight
            if not w or not h or w <= 0 or h <= 0 then return nil end
            local sample = 1
            local maxW, maxH = tonumber(reqW) or 0, tonumber(reqH) or 0
            if maxW > 0 and maxH > 0 then
                -- 留 2 倍余量，避免高 DPI 下糊掉
                while (w / sample) > maxW * 2 and (h / sample) > maxH * 2 do sample = sample * 2 end
            end
            -- 硬上限：单张不超过约 240 万像素（ARGB_8888 ≈ 9.6 MB）
            while (w / sample) * (h / sample) > 2400000 do sample = sample * 2 end
            local o2 = BitmapFactory.Options()
            o2.inSampleSize = sample
            o2.inPreferredConfig = Bitmap.Config.ARGB_8888
            return BitmapFactory.decodeFile(path, o2)
        end)
        if ok then
            bmp = r
        else
            bmpOptionsUsable = false   -- 不再尝试，后续统一走普通解码
        end
    end
    if not bmp then
        local ok, r = pcall(function() return BitmapFactory.decodeFile(path) end)
        if ok then bmp = r end
    end
    if not bmp then bmpCachePut(key, false); return nil end
    return bmpCachePut(key, bmp)
end

-- 关键修复：图片背景也要加圆角和边框（真机用 LuaBitmapDrawable，工具改为
--   先用 Canvas 把图片裁成圆角矩形，再叠加边框描边），不能像旧代码那样直接返回
--   无圆角的 BitmapDrawable。
local function roundedBitmap(bmp, radiusPx, strokeWpx, strokeColor)
    local w, h = bmp.getWidth(), bmp.getHeight()
    if radiusPx <= 0 and strokeWpx <= 0 then return bmp end
    local out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    local canvas = Canvas(out)
    local paint = Paint(Paint.ANTI_ALIAS_FLAG)
    -- 画圆角图片
    local shader = BitmapShader(bmp, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
    paint.setShader(shader)
    local rect = RectF(0, 0, w, h)
    if radiusPx > 0 then
        canvas.drawRoundRect(rect, radiusPx, radiusPx, paint)
    else
        canvas.drawRect(rect, paint)
    end
    -- 叠加边框（描边画在内侧，避免被裁掉）
    if strokeWpx > 0 and type(strokeColor) == "number" then
        paint.setShader(nil)
        paint.setStyle(Paint.Style.STROKE)
        paint.setStrokeWidth(strokeWpx)
        paint.setColor(strokeColor)
        local half = strokeWpx / 2
        local inner = RectF(half, half, w - half, h - half)
        if radiusPx > 0 then
            canvas.drawRoundRect(inner, radiusPx, radiusPx, paint)
        else
            canvas.drawRect(inner, paint)
        end
    end
    return out
end

-- 圆角/描边结果同样缓存：同一张键背景图在 36 个键上会被裁 36 次，
-- 每次都新建一张同尺寸 Bitmap + Canvas（内存与耗时都是 36 倍）。
local function roundedCached(path, bmp, radiusPx, strokeWpx, strokeColor)
    local key = "r|" .. tostring(path) .. "|" .. tostring(radiusPx) .. "|"
        .. tostring(strokeWpx) .. "|" .. tostring(strokeColor)
    local hit = bmpCache[key]
    if hit ~= nil then return hit or nil end
    local ok, rb = pcall(roundedBitmap, bmp, radiusPx, strokeWpx, strokeColor)
    if not ok or not rb then bmpCachePut(key, false); return nil end
    return bmpCachePut(key, rb)
end

function makeKeyBackground(stName, bg, radius, strokeW, strokeColor)
    local radiusPx = dp(tonumber(radius) or 0)          -- 与真机一致：不乘缩放系数
    local strokeWpx = dp(tonumber(strokeW) or 0)
    if type(bg) == "string" then
        local p = findImage(bg)
        if p then
            -- 单个键的显示尺寸约 100~150 px，按 160dp 采样已足够清晰
            local bmp = decodeImage(p, dp(160), dp(160))
            if bmp then
                local rb = roundedCached(p, bmp, radiusPx, strokeWpx, strokeColor)
                if rb then return BitmapDrawable(activity.getResources(), rb) end
            end
        end
    end
    local gd = GradientDrawable()
    gd.setColor(type(bg) == "number" and bg or 0xFF222222)
    if radiusPx > 0 then gd.setCornerRadius(radiusPx) end
    if strokeWpx > 0 and type(strokeColor) == "number" then gd.setStroke(strokeWpx, strokeColor) end
    return gd
end

-- 真机 gravity 字符串（如 "top|center"）解析为 Gravity 位或，复刻 Style.parse
local GRAV_MAP = {
    top = Gravity.TOP, bottom = Gravity.BOTTOM, left = Gravity.LEFT, right = Gravity.RIGHT,
    center = Gravity.CENTER, center_vertical = Gravity.CENTER_VERTICAL,
    center_horizontal = Gravity.CENTER_HORIZONTAL, start = Gravity.START, ["end"] = Gravity.END,
}
function parseGravity(s, def)
    if type(s) ~= "string" or s == "" then return def end
    local r = 0
    for part in s:lower():gmatch("[^|]+") do
        local g = GRAV_MAP[part:match("^%s*(.-)%s*$")]
        -- 与真机 Style.parse 的 result |= ... 逐位一致：Gravity 常量有重叠位
        -- （center=0x11 同时含 center_horizontal=0x01 / center_vertical=0x10；
        --  left=0x03、top=0x30 也都与 center 位重叠）。用 + 会产生进位、
        --  把 left|center(真机 0x13) 算成 0x14、top|center_vertical 算成非法值，
        --  换主题后文本就贴错边——这正是用户反馈的「hint/click 位置和真机不同」根因之一。
        if g then r = bitOr(r, g) end
    end
    return r == 0 and def or r
end
-- 按位或（Lua 5.1 无位运算符）：真机 Gravity 常量有重叠位（TOP=0x30 与
-- CENTER_VERTICAL=0x10 共享 0x10），必须用 | 不能用 +，否则 0x30+0x11=0x41 会破坏 TOP 位。
function bitOr(a, b)
    local r, bit = 0, 1
    while a > 0 or b > 0 do
        if a % 2 == 1 or b % 2 == 1 then r = r + bit end
        a, b = math.floor(a / 2), math.floor(b / 2)
        bit = bit * 2
    end
    return r
end
-- 判断 g 是否含有 mask 的全部位（避免用 Lua 5.1 不支持的位运算符）
function hasBits(g, mask)
    local bit = 1
    while mask > 0 do
        if mask % 2 == 1 and math.floor(g / bit) % 2 ~= 1 then return false end
        mask = math.floor(mask / 2); bit = bit * 2
    end
    return true
end

-- 手指移出按键边界后按主导轴判定滑动方向，逐行复刻 KeyView.handleSwipeEvent：
--   dx/dy 为越出左右/上下边界的距离；两者都 < 12dp 时为 NONE；
--   dx>dy 判左右，否则判上下。键内任意位置抬起都算 click。
local SWIPE_MIN_PX = dp(12)
function swipeDirFromMove(x, y, w, h)
    if not w or not h or w <= 0 or h <= 0 then return nil end
    local dx, dy = 0, 0
    if x < 0 then dx = -x elseif x > w then dx = x - w end
    if y < 0 then dy = -y elseif y > h then dy = y - h end
    if dx < SWIPE_MIN_PX and dy < SWIPE_MIN_PX then return nil end
    if dx > dy then return (x < 0) and "swipe_left" or "swipe_right" end
    return (y < 0) and "swipe_up" or "swipe_down"
end

-- 【r27.8】真机 KeyView 序号 ↔ 工具渲染序号 的自适应校准。
-- 现象：坐标本身是对的（dump 命中、cXY>0），但角标整体移到相邻键（"错位一个 key"）。
-- 根因：两侧键序列存在偏移——渲染时空白键也 `gRenderSeq+1` 占号，而结构化 dump 只采
-- 真机 KeyView；一旦某处真机没有对应 KeyView（被隐藏/合并/不创建），从这里开始每个键
-- 都取到"下一个键"的角标。固定规则（"空白键必占号"）不可能对所有主题成立。
-- 解法：逐键用"主标签"做锚定——原位命中就用原位；否则在 ±3 内找同 label 的真机键
-- （大小写无关）。这样整体偏移、局部偏移（某行有 spacer）都能自动纠正，且不依赖
-- 任何写死假设。命中结果记忆为 __off，供 label 本身不同（Enter↔回车）的键沿用。
local function resolveLiveSeq(seq, label)
    if not seq or not liveKeyTexts or type(liveKeyTexts.keys) ~= "table" then return seq end
    local keys = liveKeyTexts.keys
    if label and label ~= "" then
        local want = tostring(label):lower()
        local c0 = keys[seq]
        if c0 and c0.label and tostring(c0.label):lower() == want then
            liveKeyTexts.__off = 0
            return seq
        end
        -- 由近及远向两侧找：+d 优先（错位通常是"取到下一个键"）。
        for d = 1, 3 do
            local a = keys[seq + d]
            if a and a.label and tostring(a.label):lower() == want then
                liveKeyTexts.__off = d
                return seq + d
            end
            local b = keys[seq - d]
            if b and b.label and tostring(b.label):lower() == want then
                liveKeyTexts.__off = -d
                return seq - d
            end
        end
    end
    -- 无法用文字锚定（如 Enter↔回车）：沿用最近一次锚定出的偏移；没有就原位。
    local off = liveKeyTexts.__off
    if off and off ~= 0 and seq + off >= 1 and seq + off <= (liveKeyTextsN or 0) then
        return seq + off
    end
    return seq
end

function makeKeyView(label, st, stName, w, h, r, k, margins, seq)
    local _tr = "K[" .. tostring(r) .. "," .. tostring(k) .. "]#" .. tostring(seq) .. "(" .. tostring(label) .. "/" .. tostring(stName) .. ")"
    -- 【r27.8】按真机结构校准消费序号（见 resolveLiveSeq 注释）。
    local useSeq = resolveLiveSeq(seq, label)
    -- 【真机文字源】取本键在真机 dump 里的实际显示文字（布局/样式仍走 kbdEnv）。
    -- 仅当 dump 可用、序号有效、且主标签匹配（或预览 label 为空）时才采用，避免键盘
    -- 不一致时按序映射错位。lt=nil 表示本键不采用真机文字，完全回退现有推导。
    local lt = nil
    local keyLiveOff = liveTextsDisabledKeys[keySlot(r, k)] == true
    if not liveTextsDisabled and not keyLiveOff and liveKeyTexts and useSeq and useSeq >= 1 and useSeq <= liveKeyTextsN then
        local cand = liveKeyTexts.keys[useSeq]
        -- 【r23 根因】label 相等不能作为硬条件：工具的 label 是【键盘脚本原始占位符】
        -- （如 Enter / schema_name / {X}），真机 dump 的 cand.label 是【Rime 转换后的
        -- 显示文字】（如 回车 / 万象拼音）。二者天然不同，强求相等会让几乎所有键
        -- lt=nil → 角标权威坐标(c.x/c.y)从没进 e.dumpX/dumpY → 只能靠 gravity 推导，
        -- 而主题给角标配的 center_vertical 工具读不到 → 全部贴顶 y=0（用户实测）。
        -- seq（行优先）才是权威对齐依据：gRenderSeq 与 parseRootDumpToKeys 锚点顺序
        -- 一一对应，cand 存在即采用。label 一致仍优先（双保险），不一致也接受。
        if cand then
            lt = cand
            if type(_G.__kbdDiag) == "table" then
                _G.__kbdDiag.rendered = (_G.__kbdDiag.rendered or 0) + 1
                _G.__kbdDiag.ltHit = (_G.__kbdDiag.ltHit or 0) + 1
            end
        elseif type(_G.__kbdDiag) == "table" then
            _G.__kbdDiag.rendered = (_G.__kbdDiag.rendered or 0) + 1
        end
    end
    -- 严格复刻真机两层结构：
    --  外层 fl  = RowKeyboardView 的格子，尺寸 w×h（合计恰 100%），不带间距 → 不超出屏幕。
    --  内层 keyRoot = KeyView 内的 keyRoot，MATCH_PARENT 填满格子，带 margins（键间隙）
    --  和 padding（内容内缩）。键间视觉间隙来自 margins，且不影响外层尺寸合计。
    local fl = FrameLayout(activity)
    local kvLp = LinearLayout.LayoutParams(w, h)
    fl.setLayoutParams(kvLp)
    -- 真机 KeyView.initView：关掉裁剪，让角标（hint/long_click，gravity 贴边）能超出
    -- keyRoot 边界显示，不被背景/格子裁掉（下滑角标被遮挡的根因）。
    pcall(function()
        fl.setClipChildren(false)
        fl.setClipToPadding(false)
    end)
    local function field(key) return channelField(stName, "", key) end
    local hide = (stName == "hide_key") or st.hide == true or field("show") == false

    local keyRoot = FrameLayout(activity)
    pcall(function()
        keyRoot.setClipChildren(false)
        keyRoot.setClipToPadding(false)
    end)
    local krLp = FrameLayout.LayoutParams(-1, -1)
    local mg = styleInset4(stName, "margins")
    krLp.setMargins(dp(mg.left or 0), dp(mg.top or 0), dp(mg.right or 0), dp(mg.bottom or 0))
    keyRoot.setLayoutParams(krLp)
    local pd = styleInset4(stName, "padding")
    keyRoot.setPadding(dp(pd.left or 0), dp(pd.top or 0), dp(pd.right or 0), dp(pd.bottom or 0))
    fl.addView(keyRoot)

    -- 背景（复刻：颜色/图片 + 圆角 + 描边 + elevation 阴影）——画在内层 keyRoot 上
    local bg = field("background")
    local radius = tonumber(field("corner_radius")) or 0
    if not hide then
        local drawable = makeKeyBackground(stName, bg, radius, field("stroke_width"), field("stroke_color"))
        keyRoot.setBackgroundDrawable(drawable)
        local elev = tonumber(field("elevation"))
        if elev and elev > 0 then
            pcall(function()
                keyRoot.setElevation(dp(elev))
                local sc = field("shadow_color")
                if type(sc) == "number" then
                    keyRoot.setOutlineSpotShadowColor(sc)
                    keyRoot.setOutlineAmbientShadowColor(sc)
                end
            end)
        end
    end

    -- 中心主文字：复刻 KeyView 的 mClick（样式取本键 style 的 text_color/size/font/gravity/offset）
    -- 真机 mClick 字号直接用 getTextSize()（sp），不做额外缩放
    -- 【r27.39】渲染门槛修正：旧判断 `if label and label ~= ""` 只看【脚本占位 label】。
    -- 桥接 dump 里 txt=[中文] 的键（如 seq=52）在脚本里常是占位/空 label，导致整段被
    -- 跳过——桥接文字明明拿到了却不显示。改为：脚本 label 或桥接 label 有一个非空就渲染。
    local __bridgedText = (lt and lt.label and lt.label ~= "") and lt.label or nil
    if ((label and label ~= "") or __bridgedText) and not hide then
        local tc = field("text_color") or 0xFF000000
        local ts = tonumber(field("text_size")) or 18
        -- 严格对齐 trime2 Style.getFont("font")：当前 style.font → keyboard.font，
        -- font 可为字符串或字体数组（fallback 链，取第一个能定位到真实字体的）。
        -- 旧代码 field("font") 只取裸值，既不查 keyboard.font 兜底也不处理数组 → 字体加载错误。
        local fontPaths = {}
        if stName and stName ~= "" then fontPaths[#fontPaths + 1] = stName .. ".font" end
        fontPaths[#fontPaths + 1] = "key.font"
        fontPaths[#fontPaths + 1] = "keyboard.font"
        local font = resolveUIFont(fontPaths)
        local ox, oy = tonumber(field("offset_x")), tonumber(field("offset_y"))
        local grav = parseGravity(field("gravity"), Gravity.CENTER)
        local nativeStyles = {}
        if stName and stName ~= "" then nativeStyles[#nativeStyles + 1] = stName end
        nativeStyles[#nativeStyles + 1] = "key"
        -- 【真机偏移权威取值】mClick 用本键 style 的 offset_x/y。优先直接调真机
        -- KeyStyle.getSize()（已处理继承 + dp2px，返回像素），取不到才回退 Lua 表值 + dp()。
        local nox, noy = nativeOffset(nativeStyles, "offset_x"), nativeOffset(nativeStyles, "offset_y")
        local pxOffsets = false
        if nox ~= nil or noy ~= nil then
            ox, oy, pxOffsets = nox, noy, true
        end
        -- 【r27.18】click 主标签改与角标同构：有桥接权威坐标(lt.clickX/Y)时像角标一样
        -- 绝对定位（传给 addLabelView 的 absX/absY），不再用主题 gravity+offset 推导，
        -- 消除各主题推导结果不同造成的位置差异。无桥接坐标时仍回退原主题推导。
        local clickAbsX, clickAbsY = nil, nil
        if lt and lt.clickX ~= nil and lt.clickY ~= nil then
            clickAbsX, clickAbsY = lt.clickX, lt.clickY
        end
        -- 【纯桥接 / r27.35】主标签文字只取桥接 KSCLICK 的 txt（真机 Rime 显示文字）。
        -- 桥接键已命中(lt 非 nil)但 txt 为空 → 真机这键无文字，显示空，不再回退脚本内部名
        -- （Enter / Mode_switch / schema_name 这类占位符不是桥接数据）。只有 lt=nil（桥接
        -- 未覆盖到该键）时才回退脚本 label，保证桥接缺失时仍能显示。
        local clickText
        if lt then
            clickText = (lt.label ~= nil and lt.label ~= "") and lt.label or ""
            -- 桥接到位但 txt 空、且脚本本来有 label → 记一次"脚本内部名被屏蔽"
            if clickText == "" and label and label ~= "" and type(_G.__kbdDiag) == "table" then
                _G.__kbdDiag.scriptMasked = (_G.__kbdDiag.scriptMasked or 0) + 1
            end
        else
            clickText = label
        end
        addLabelView(keyRoot, clickText, ts, type(tc) == "number" and tc or nil, 8, font, grav, ox, oy,
                     nil, nativeStyles, pxOffsets, true, nil, nil, clickAbsX, clickAbsY)
    end

    -- 各通道角标：【纯桥接模式】完全由真机 dump 的 KSCORNER 建立，删去一切主题推导与
    -- 方向池抢占。dump 有一条角标就画一条，文字/通道/坐标全取桥接；样式（字体/色/大小/
    -- gravity/offset）仍走主题，因为桥接不采集样式——这部分保持原样在下方渲染循环里。
    local kdef = kbdEnv and kbdEnv.rows and kbdEnv.rows[r] and kbdEnv.rows[r].keys[k]
    if type(kdef) == "table" and not hide then
        -- 通道 → spec（stPath 决定样式继承链，defG 仅在无 dump 坐标时作渲染回退）
        local specs = {
            { id="long_click",  stPath="long_click",  defG=bitOr(Gravity.TOP, Gravity.CENTER) },
            { id="click",       stPath="hint",        defG=bitOr(Gravity.BOTTOM, Gravity.CENTER) },
            { id="swipe_up",    stPath="hint.up",     defG=bitOr(Gravity.TOP, Gravity.CENTER) },
            { id="swipe_down",  stPath="hint.down",   defG=bitOr(Gravity.BOTTOM, Gravity.CENTER) },
            { id="swipe_left",  stPath="hint.left",   defG=bitOr(Gravity.LEFT, Gravity.CENTER) },
            { id="swipe_right", stPath="hint.right",  defG=bitOr(Gravity.RIGHT, Gravity.CENTER) },
        }
        local specById = {}
        for _, S in ipairs(specs) do specById[S.id] = S end
        local shown = {}
        if lt then
            -- 一条 KSCORNER = 一个角标。c.chan 是 Java 反射 mHints[] 得来的权威通道；
            -- 无 chan 的旧 dump 才用方向 grav 兜底映射到该方向默认通道，且每方向只取首条，
            -- 绝不再让 long_click 去 TOP 池抢 swipe_up 的角标（这是错位根因）。
            local dirDefault = { TOP="long_click", BOTTOM="click", LEFT="swipe_left", RIGHT="swipe_right" }
            local usedDir = {}
            for _, c in ipairs(lt.corners or {}) do
                if c.txt and c.txt ~= "" then
                    local id = specById[c.chan] and c.chan or nil
                    if not id then
                        local dflt = dirDefault[c.grav]
                        if dflt and not usedDir[c.grav] then
                            id = dflt
                            usedDir[c.grav] = true
                        end
                    end
                    local S = id and specById[id] or nil
                    if S then
                        shown[id] = {
                            S = S, grav = S.defG,
                            text = utf8Cut(c.txt, 4), rawText = c.txt, orig = c.txt,
                            dumpX = c.x, dumpY = c.y, dumpW = c.w, dumpH = c.h,
                        }
                        if type(_G.__kbdDiag) == "table" then
                            _G.__kbdDiag.cornerWithXY = (_G.__kbdDiag.cornerWithXY or 0) + 1
                        end
                    end
                end
            end
        end
        for _, id in ipairs({"long_click", "click", "swipe_up", "swipe_down", "swipe_left", "swipe_right"}) do
            local e = shown[id]
            -- 【r27.18】角标改回桥接权威坐标定位（与 r27.8 同）：有 dump 坐标就绝对定位，
            -- 不再让主题 gravity+offset 推导结果主导位置，消除各主题差异。
            -- 无 dump 坐标（桥接未到/退化）才回退主题推导，保证角标仍能显示。
            if e then
                local S = e.S
                local ic = channelField(stName, S.stPath, "text_color") or 0x99FFFFFF
                local its = tonumber(channelField(stName, S.stPath, "text_size")) or 8
                local ifont = channelField(stName, S.stPath, "font")
                -- 【r27.17】与 click 主标签同构：角标位置由本通道 style 的
                -- gravity + offset_x/offset_y 推导（gravity 在 e.grav 里，见上方 specs 解析）。
                -- 走 nativeOffset → realOffset → dp 的同一条链路，不再用 dump 坐标定位。
                local hox = tonumber(channelField(stName, S.stPath, "offset_x"))
                local hoy = tonumber(channelField(stName, S.stPath, "offset_y"))
                local hintNativeOff = {}
                if stName and stName ~= "" and stName ~= "key" then
                    hintNativeOff[#hintNativeOff + 1] = stName .. "." .. S.stPath
                end
                hintNativeOff[#hintNativeOff + 1] = "key." .. S.stPath
                local nhox = nativeOffset(hintNativeOff, "offset_x")
                local nhoy = nativeOffset(hintNativeOff, "offset_y")
                local hpx = false
                if nhox ~= nil or nhoy ~= nil then
                    hox, hoy, hpx = nhox, nhoy, true
                end
                -- 真机 KeyView 三处角标（setLongClickText:620 / setHintText:657 /
                -- addHint:950）布局参数完全一致：
                --   new FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, gravity)
                -- 角标尺寸完全由内容（getSpan 产出的图片/文字 + text_size）决定。
                -- 工具旧代码用固定 w*0.42 × h*0.34 框，把上标 ☩译 挤窄、下标 ▼ 撑大
                -- （uiautomator 实测：工具 ▼ 40x47，真机 27x25）。改为 WRAP_CONTENT +
                -- gravity，与真机布局参数逐字一致；内部 TextView 同样用 WRAP_CONTENT
                -- （wrapLp=true），两层叠加后角标位置/尺寸与真机单层效果相同。
                -- 【r20】角标直接挂 keyRoot，与真机 KeyView 单层结构逐行一致：
                --   真机 setLongClickText/setHintText/addHint 均为
                --   keyRoot.addView(tv, LP(WRAP,WRAP,gravity)) + tv.setTranslation(offset)。
                -- 旧版多包一层 box（box 用 LP(WRAP,WRAP,gravity) 挂 keyRoot、tv 再挂 box）：
                --   · dump 打印 tv.getLeft() 是相对 box 的 → 全是 @0,0，无法与真机对照；
                --   · 双层 WRAP_CONTENT + gravity 叠加，换主题时角标位置与真机单层不一致
                --     （用户反馈「数字键上下滑动 hint 位置不对」）。
                -- 现在 addLabelView 内部按 wrapLp=true 设 LP(-2,-2)+gravity，直接 addView 到 keyRoot。
                -- 图片查找用完整事件串（e.rawText），文字显示用截断后的 e.text，
                -- 与真机 getSpan 用完整 text 找图、找不到才显示文字的行为一致。
                -- 角标字体：真机 hint/long_click 的 KeyStyle.getFont() 通常继承自主 key style。
                local hintNativeStyles = {}
                if stName and stName ~= "" then hintNativeStyles[#hintNativeStyles + 1] = stName end
                hintNativeStyles[#hintNativeStyles + 1] = "key"
                -- 通道派生路径 = S.stPath（hint / long_click / hint.up / hint.down …），传给
                -- nativeSpan 精确复现真机 getSpan 用的 KeyStyle 实例。g 键 ▼ 是单独 hint
                -- （S.id=="click" → stPath="hint"），真机用 getHintKeyStyle() 染色成 27x25 灰三角；
                -- 之前扁平实例染成白色大梯形，正是 derive 缺失所致。所有通道一视同仁走源码逻辑。
                local derive = S.stPath
                -- 真机 KeyView：mHint/mLongClick.setTextSize(COMPLEX_UNIT_DIP, style.getTextSize(8))
                -- 及 addHint 内 hint.setTextSize(COMPLEX_UNIT_DIP, mHintStyle.getTextSize(8))：
                -- 角标字体 = 该通道 style 的 text_size 原值（缺省 8），不做任何缩放。
                -- 旧代码 math.max(6, its*0.6) 把缺省 8 压成 6、其余缩 0.6 → 所有上标偏小。
                -- tight=true：角标复用真机 TightTextView（真实绘制/测量逻辑），与源码一致。
                -- 【r22】把真机 dump 权威坐标在 addView 之前传给 addLabelView：
                -- 它在 setLabelLp 里一次性建好 LP(TOP|LEFT + margins=坐标)，addView 时
                -- 立即按此 layout。r21 的事后 setLayoutParams 是异步 requestLayout，
                -- dump 同一帧取 getLeft 仍是旧值（实测坐标纹丝不动），故改为源头传入。
                -- 【r27.18】与 click 主标签同构：两者都用桥接权威坐标绝对定位。
                -- 有 e.dumpX/Y → setLabelLp 按坐标定位；无 → absX/Y=nil 自动回退主题推导。
                -- 【r27.33】只给 long_click 的 label 与按键 hint（S.id=="click"）右移；
                -- 上下左右滑动 hint（swipe_*）本就正常，不偏移。仍仅限桥接绝对定位的角标
                -- （回退 gravity/offset 推导的角标 dumpX=nil 不动）。
                local nudgeDp = (S.id == "long_click" or S.id == "click")
                                and (CORNER_X_NUDGE_DP or 0) or 0
                local cornerAbsX = e.dumpX and (e.dumpX + dp(nudgeDp)) or nil
                local hintView = addLabelView(keyRoot, e.text, its, type(ic) == "number" and ic or 0x99FFFFFF,
                             0, ifont, e.grav, hox, hoy, e.rawText or e.text, hintNativeStyles, hpx, true, derive, true,
                             cornerAbsX, e.dumpY, e.dumpW, e.dumpH)
                -- 角标保留点击热区：直接打开该通道的事件编辑器（样式在独立入口改）。
                -- addLabelView 现已返回实际 tv，点击直接挂在 tv 上（不再需要 box 包装层）。
                if hintView then
                    pcall(function()
                        hintView.onClick = function()
                            selKeyR, selKeyK = r, k
                            if channelEditDialog then channelEditDialog(r, k, S.id) end
                        end
                    end)
                end
            end
        end
    end

    -- 选中高亮：绝不能再画实心描边盖住真实边框（用户改边框色/宽度后被草绿框遮住，
    -- 看起来"改了没变化"）。改成很淡的半透明填充，选中可见，同时真实边框色/宽度都能看到。
    if selKeyR == r and selKeyK == k then
        local hl = GradientDrawable()
        hl.setColor(0x3330C190)   -- 低透明度青绿填充，不遮挡边框
        hl.setCornerRadius(dp(radius))
        local hlv = View(activity)
        local hlp = FrameLayout.LayoutParams(-1, -1)
        local inset = dp(2)        -- 略微内缩，避开真实边框所在的边缘
        hlp.setMargins(inset, inset, inset, inset)
        hlv.setLayoutParams(hlp)
        hlv.setBackgroundDrawable(hl)
        keyRoot.addView(hlv)
    end

    -- 真机手势：点击(任意键内位置)=click，按住超时=long_click，滑出边界=对应 swipe
    -- 手势结束后只做一件事：打开被识别通道的【真实 event + 相关样式】编辑器。
    local downX, downY = 0, 0
    local curDir = nil
    local longFired = false
    local longTime = tonumber(field("long_click_time")) or 1000  -- 对齐 KeyStyle.getLongClickTime() 默认
    local longRunnable = luajava.createProxy("java.lang.Runnable", {
        run = function()
            if curDir == nil then longFired = true end
        end
    })
    local function openChannel(id)
        selKeyR, selKeyK = r, k
        uiHandler.post(function() renderPreview() end)
        if channelEditDialog then channelEditDialog(r, k, id) end
    end
    local function finishGesture(v)
        uiHandler.removeCallbacks(longRunnable)
        local chosen
        if curDir then chosen = curDir
        elseif longFired then chosen = "long_click"
        else chosen = "click" end
        openChannel(chosen)
    end
    pcall(function()
        keyRoot.setOnTouchListener(luajava.createProxy("android.view.View$OnTouchListener", {
            onTouch = function(v, event)
                local a = event.getAction()
                local x, y = event.getX(), event.getY()
                if a == event.ACTION_DOWN then
                    downX, downY = x, y
                    curDir, longFired = nil, false
                    uiHandler.postDelayed(longRunnable, longTime)
                    return true
                elseif a == event.ACTION_MOVE then
                    local d = swipeDirFromMove(x, y, v.getWidth(), v.getHeight())
                    if d ~= curDir then
                        curDir = d
                        if curDir ~= nil then uiHandler.removeCallbacks(longRunnable) end
                    end
                    return true
                elseif a == event.ACTION_UP or a == event.ACTION_CANCEL then
                    finishGesture(v)
                    return true
                end
                return false
            end
        }))
    end)
    return fl
end

-- rows 可能是稀疏表（万象脚本用 rows[i+2] 从下标 3 起填），#rows 会返回 0。
-- 必须定义在 renderPreviewImpl 之前：Lua 的 local 先定义后可见，否则渲染函数调用时
-- 它是 global nil → "attempt to call nil (global 'rowsCount')" → 键盘全黑。
function rowsCount(rows)
    if type(rows) ~= "table" then return 0 end
    local n = 0
    local hasKeys = false
    for k, v in pairs(rows) do
        if type(k) == "number" and k > n then n = k end
        if type(v) == "table" and type(v.keys) == "table" then hasKeys = true end
    end
    return (n > 0 and hasKeys) and n or 0
end

function renderPreviewImpl()
    resetGlyphBudget()          -- 每次渲染重置字形探测预算，防止累积耗尽
    -- 内容源命中计数（供启动 [SRC] 状态行展示；轻量、无 JNI 开销）
    _G.__kbdDiag = { rendered = 0, ltHit = 0, cornerWithXY = 0, scriptMasked = 0 }
    local W = previewBox.getWidth() - previewBox.getPaddingLeft() - previewBox.getPaddingRight()
    if W <= 0 then
        if renderRetry < 10 then
            renderRetry = renderRetry + 1
            uiHandler.postDelayed(function() renderPreview() end, 200)
        end
        return
    end
    renderRetry = 0
    previewBox.removeAllViews()

    -- 【r27.45】背景渲染移到下方 col 组装之后：主题 background 是「键盘背景」，
    -- 应贴合键盘内容块（候选栏+工具栏+按键区），不是整个预览画布。旧版铺在 previewBox
    -- 上（weight=1 占满剩余空间），数字颜色还会覆盖画布深色底 → 浅灰铺满溢出键盘。

    local cdRow = showCandidateFlag and buildCandidatePreview(W) or nil
    local tbRow = buildToolbarPreview(W)

    local pvH = previewBox.getHeight()
    -- 候选栏与工具栏各自独立成行，从上到下：候选栏 → 工具栏 → 键盘。
    -- 旧版把工具栏盖在候选栏上（同一个 FrameLayout），改候选样式时看不到工具栏，
    -- 改工具栏时又挡住候选，调哪一块都别扭。
    -- 真机键盘/候选栏高度都乘 height scale（用户可调，见 keyboardHeightScale）。
    local kbScale = keyboardHeightScale()
    -- 真机候选栏高度 = style.candidate.height × min(1, scale)（只减不增）
    local cdScale = math.min(1, kbScale)
    local cdH = cdRow and dp((tonumber(getValue("candidate.height")) or 44) * cdScale) or 0
    -- 工具栏高度与真机 ToolbarView 一致：getCandidateHeight() - gap。
    -- 值可能写成 "4dp"，纯 tonumber 读不到单位，补一次数字提取。
    local gapRaw = getValue("toolbar.elevation")
    local gapDp = tonumber(gapRaw) or tonumber(tostring(gapRaw or ""):match("[-%d%.]+")) or 2
    local tbH = 0
    if tbRow then
        tbH = tonumber(TB_PREVIEW_H) or 0
        if tbH <= 0 then tbH = dp(tonumber(getValue("candidate.height")) or 40) end
    end

    -- 真机键盘高度 = style.keyboard.height × Config.getKeyboardHeightScale()，
    -- 用户拖过「键盘高度」后 scale≠1。工具之前漏乘，换主题/调高度后就和真机不符。
    -- kbScale 已在上方（候选栏高度前）算好，这里直接复用。
    local kbH = dp((tonumber(getValue("keyboard.height")) or 216) * kbScale)
    -- 键盘至少留 45%，其余给候选/工具栏；两者加起来超出就等比压缩，保证三块都看得见。
    local availH = pvH > 0 and math.floor(pvH * 0.95) or 0
    if availH > 0 then
        local chrome = cdH + tbH
        local chromeMax = math.max(0, availH - math.floor(availH * 0.45))
        if chrome > chromeMax and chrome > 0 then
            local k = chromeMax / chrome
            local ncd = math.floor(cdH * k)
            local ntb = math.floor(tbH * k)
            -- 压缩后至少留得下一行文字：0 或负高度会让 LinearLayout 反复测量，
            -- 表现为界面「卡住不刷新」。
            if cdRow and cdH > 0 then ncd = math.max(ncd, dp(16)) end
            if tbRow and tbH > 0 then ntb = math.max(ntb, dp(16)) end
            cdH, tbH = ncd, ntb
        end
        local room = availH - cdH - tbH
        if room > 0 and kbH > room then kbH = room end
        -- 键盘保底高度：宁可让候选/工具栏再缩，也不要键盘塌成一条线。
        local kbMin = dp(48)
        if kbH < kbMin then
            kbH = kbMin
            local over = cdH + tbH - math.max(0, availH - kbH)
            if over > 0 and (cdH + tbH) > 0 then
                local k2 = math.max(0, availH - kbH) / (cdH + tbH)
                cdH = math.floor(cdH * k2)
                tbH = math.floor(tbH * k2)
            end
        end
    end

    local col = LinearLayout(activity)
    col.setOrientation(LinearLayout.VERTICAL)
    local colLp = FrameLayout.LayoutParams(-1, -2)
    colLp.gravity = Gravity.CENTER
    col.setLayoutParams(colLp)
    if cdRow and cdH > 0 then
        col.addView(cdRow, LinearLayout.LayoutParams(-1, cdH))
    end
    if tbRow and tbH > 0 then
        -- 底部留出 toolbar.elevation：与真机一致，工具栏和按键区之间露出键盘整体背景。
        local innerH = math.max(dp(8), tbH - dp(gapDp))
        local tbLp = LinearLayout.LayoutParams(-1, innerH)
        tbLp.bottomMargin = dp(gapDp)
        col.addView(tbRow, tbLp)
    end

    if not _layoutDiagDone then
        _layoutDiagDone = true
        pcall(function()
            local msg = string.format("previewBox宽=%d高=%d, keyboard.height=%s×scale=%.2f→kbH=%d, 候选栏高=%d, 工具栏高=%d, gap=%ddp",
                previewBox.getWidth(), pvH, tostring(getValue("keyboard.height")), kbScale,
                kbH, cdH, tbH, gapDp)
            logErr("布局诊断", msg)
        end)
    end

    local kb = LinearLayout(activity)
    kb.setOrientation(LinearLayout.VERTICAL)
    -- 严格对齐真机 RowKeyboardView：键盘容器高度 = mHeight = getKeyboardHeight()，固定值。
    -- 各行用「kbH × height%」算出高度并按 topMargin 累加定位（工具用 LinearLayout 顺序堆叠，
    -- 效果等价）。预留行 height=0 → 不占空间。容器高度不应自适应内容，否则与真机尺寸不符。
    kb.setLayoutParams(LinearLayout.LayoutParams(-1, kbH))
    local kbg = getValue("keyboard.background")
    if type(kbg) == "string" then
        local p = findImage(kbg)
        if p then pcall(function()
            local bmp = decodeImage(p, W, kbH)
            if bmp then kb.setBackgroundDrawable(BitmapDrawable(activity.getResources(), bmp)) end
        end) end
    elseif type(kbg) == "number" then
        pcall(function() kb.setBackgroundDrawable(areaDrawable("keyboard", kbg)) end)
    end
    col.addView(kb)

    -- 【r27.45 背景贴合】主题 background 是键盘背景，只覆盖键盘内容块 col，绝不铺满画布。
    -- col 本身是 WRAP_CONTENT + CENTER，高度恰好=候选栏+工具栏+按键区，把背景直接设到 col 上
    -- 必然贴合，无需另建背景层（另建层用 WRAP_CONTENT 套 MATCH_PARENT 子 view 测量不可靠）。
    --  · 数字颜色：areaDrawable("",gb) 铺满 col；
    --  · 图片：BitmapDrawable + Gravity.FILL 拉伸铺满 col（等价 ImageView 的 FIT_XY）。
    -- 画布 previewBox 保留自己的深色底（上下留白露深色），两个主题都不再溢出。
    local gb = getValue("background")
    if type(gb) == "string" then
        local p = findImage(gb)
        if p then pcall(function()
            local bmp = decodeImage(p, W, kbH)
            if bmp then
                local bd = BitmapDrawable(activity.getResources(), bmp)
                bd.setGravity(Gravity.FILL)
                col.setBackgroundDrawable(bd)
            end
        end) end
    elseif type(gb) == "number" then
        pcall(function() col.setBackgroundDrawable(areaDrawable("", gb)) end)
    end

    previewBox.addView(col)

    -- 【真机文字源】键渲染顺序序号：与 parseRootDumpToKeys 的锚点顺序（行优先）一一对应。
    -- 每遇到一个真实键（含空白占位键）+1；makeKeyView 用它取 liveKeyTexts[seq] 的真机文字。
    local gRenderSeq = 0

    if kbdEnv and type(kbdEnv.rows) == "table" then
        -- 稀疏 rows（下标从 3 起）不能用 ipairs/#，否则 row[1]=nil 立即中断、行数也算错。
        -- 收集所有【真正含 keys 的行】的数字下标排序后遍历；行数 = 实际行数，不是最大下标。
        local rowIdx = {}
        for k, row in pairs(kbdEnv.rows) do
            if type(k) == "number" and type(row) == "table" and type(row.keys) == "table" then
                rowIdx[#rowIdx + 1] = k
            end
        end
        table.sort(rowIdx)
        local nRows = #rowIdx  -- 实际行数
        -- 【严格对齐真机 RowKeyboardView.loadRows/loadRow 的 optdouble 语义】
        -- 真机：mRowHeight = key_height（若设），否则 100/行数；
        --       每行高度百分比 = row.height（若是数字，含 0），否则 mRowHeight。
        -- 行像素高 = kbH × 百分比/100，不做封顶/最小值/归一化：0% 就是 0px、不显示。
        -- 修复"只剩数字键一行"的真正根因：之前把【未显式写 height 的行】用 `or 0`
        -- 压成了 0，真机这些行用 key_height 兜底、应正常显示；只有显式 height=0 的
        -- 预留行才是 0px 不显示。
        local defaultRowPct = (nRows > 0) and (100 / nRows) or 20
        local mRowHeight = tonumber(getKbdValue("key_height") or kbdEnv.key_height) or defaultRowPct
        -- 【宽度同理，严格对齐真机 loadRows 的 mKeyWidth】
        -- 真机：mKeyWidth = key_width（若设），否则 100 / 第一行的键数。
        local firstRow = rowIdx[1] and kbdEnv.rows[rowIdx[1]]
        local firstKeyCount = (firstRow and type(firstRow.keys) == "table") and rowsCount(firstRow.keys) or 0
        local defaultKeyW = (firstKeyCount > 0) and (100 / firstKeyCount) or 10
        local mKeyWidth = tonumber(getKbdValue("key_width") or kbdEnv.key_width) or defaultKeyW
        local km = getFrom(styleEnv, "key.margins") or {}
        local margins = {
            left = tonumber(km.left) or 0, top = tonumber(km.top) or 0,
            right = tonumber(km.right) or 0, bottom = tonumber(km.bottom) or 0,
        }
        for _, ri in ipairs(rowIdx) do
            local row = kbdEnv.rows[ri]
            if type(row) == "table" and type(row.keys) == "table" then
                -- 真机 optdouble：row.height 是数字（含 0）就用它，否则用 mRowHeight 兜底。
                -- 注意 0 是有效值，绝不能被 `or` 吞掉；预留行显式 height=0 → rowH=0 → 不显示。
                local rawRowH = getKbdValue("rows." .. ri .. ".height")
                if rawRowH == nil then rawRowH = row.height end
                local rowHPctRow = tonumber(rawRowH)
                if rowHPctRow == nil then rowHPctRow = mRowHeight end
                local rowH = math.floor(kbH * rowHPctRow / 100)  -- 0% → 0px，不显示
                -- 真机 optdouble：row.width 是数字就用它，否则用 mKeyWidth 兜底。
                local rawRowW = getKbdValue("rows." .. ri .. ".width")
                if rawRowW == nil then rawRowW = row.width end
                local rowWPct = tonumber(rawRowW)
                if rowWPct == nil then rowWPct = mKeyWidth end
                local rowLay = LinearLayout(activity)
                rowLay.setOrientation(LinearLayout.HORIZONTAL)
                rowLay.setLayoutParams(LinearLayout.LayoutParams(-1, rowH))
                local keyIdx = {}
                for k in pairs(row.keys) do if type(k) == "number" then keyIdx[#keyIdx + 1] = k end end
                table.sort(keyIdx)
                -- 【严格对齐真机 RowKeyboardView.loadRow/loadKey】源码不归一化：
                -- mKeyWidth = key_width or 100/首行键数；每键 width% = key.width or row.width or mKeyWidth；
                -- kw = (int)(mWidth × width% / 100)，mWidth→预览框 W。主题各行 width% 之和恰为 100%，
                -- 直接换算即铺满，无需除以行内总和（那会改变真机在 width%≠100% 时的真实行为）。
                local keyWPctMap = {}
                for _, ki in ipairs(keyIdx) do
                    local kd = row.keys[ki]
                    if type(kd) == "table" then
                        local kp = "rows." .. ri .. ".keys." .. ki
                        local rw = getKbdValue(kp .. ".width")
                        if rw == nil then rw = kd.width end
                        local wp = tonumber(rw)
                        if wp == nil then wp = rowWPct end
                        if wp < 0 then wp = 0 end
                        keyWPctMap[ki] = wp
                    end
                end
                for _, ki in ipairs(keyIdx) do
                    local keyDef = row.keys[ki]
                    if type(keyDef) == "table" then
                        local kpath = "rows." .. ri .. ".keys." .. ki
                        -- 严格源码 RowKeyboardView.loadKey:76 → width = (int)(mWidth × width% / 100)。
                        -- 这里 mWidth 取预览框宽 W（等比映射真机屏幕宽），不做归一化、不做最小值兜底。
                        local keyWPct = keyWPctMap[ki] or rowWPct
                        local kw = math.floor(W * keyWPct / 100)  -- (int) 截断；0% → 0px
                        -- margins 只由 layoutParams 应用一次，绝不预先从宽高里扣除。
                        -- 真机 loadKey：height = kbH × key.height.optdouble(行百分比)/100，
                        -- 即 key.height 是数字（含 0）就用它，否则回退到所在行的百分比。
                        local rawKeyH = getKbdValue(kpath .. ".height")
                        if rawKeyH == nil then rawKeyH = keyDef.height end
                        local keyHPct = tonumber(rawKeyH)
                        if keyHPct == nil then keyHPct = rowHPctRow end
                        -- 严格源码 RowKeyboardView.loadKey:77 → height = (int)(mHeight × height% / 100)。
                        -- mHeight→kbH；0% → 0px → 该键不显示（与真机一致，不做最小 1px 兜底）。
                        local kh = math.floor(kbH * keyHPct / 100)
                        local label = getKbdValue(kpath .. ".label")
                        local click = getKbdValue(kpath .. ".click")
                        -- label/click 都可能是 number（桥接 LuaJ 保留数值类型），统一转字符串
                        if type(label) == "number" then label = tostring(label) end
                        if type(click) == "number" then click = tostring(click) end
                        if (label == nil or label == "") and type(click) == "string" then
                            label = resolveEventLabel(click)
                            if label == "" then label = nil end
                        end
                        if not click and not label then
                            -- 【r27.43】空白/占位键：脚本骨架里没有任何内容（无 label/click），
                            -- 真机 dump 里也只是一个 0×0 锚点、没有任何样式。旧代码在这里
                            -- fallback 到 key.background + 4dp 圆角 + 选中高亮，等于工具凭空
                            -- 给空壳加了一块可见背景（红圈里多出来的方块）。改为：只保留一个
                            -- 透明占位 view 维持 kw×kh 布局与 seq 对齐，不画任何背景/圆角/
                            -- margins/padding/高亮——用户没给的样式，工具绝不自作主张添加。
                            -- onClick 保留，仍可点开通道编辑器给它加 event。
                            local sp = FrameLayout(activity)
                            sp.setLayoutParams(LinearLayout.LayoutParams(kw, kh))
                            sp.onClick = function()
                                selKeyR, selKeyK = ri, ki
                                renderPreview()
                                if channelEditDialog then channelEditDialog(ri, ki, "click") end
                            end
                            gRenderSeq = gRenderSeq + 1  -- 空白键在 dump 里也是锚点，占一个序号
                            rowLay.addView(sp)
                        else
                            -- 真机 Key.java:223 权威规则：style 名 = style 字段，否则回退 click，
                            -- 否则 "key"。万象等主题多数按键不写 style，靠 click 当 style 名
                            -- （数字键 click="1" → style "1"，逗号键 click="," → style ","）。
                            -- 工具此前只读 .style，导致 stName 为空 → offset/字体/背景全取默认 key，
                            -- 这正是"偏移没效果"以及诸多样式不对的总根因。
                            local stName = getKbdValue(kpath .. ".style")
                            if not stName or stName == "" then
                                local clickName = getKbdValue(kpath .. ".click")
                                if clickName == nil then clickName = keyDef.click end
                                if type(clickName) == "number" then clickName = tostring(clickName) end
                                if type(clickName) == "string" and clickName ~= "" then
                                    stName = clickName
                                end
                            end
                            local st = {}
                            if stName and type(styleEnv[stName]) == "table" then st = styleEnv[stName] end
                            if not label and st.label then label = st.label end
                            gRenderSeq = gRenderSeq + 1
                            local kv = makeKeyView(label, st, stName, kw, kh, ri, ki, margins, gRenderSeq)
                            rowLay.addView(kv)
                        end
                    end
                end
                kb.addView(rowLay)
            end
        end
    else
        local tv = TextView(activity)
        tv.setText("（未选择键盘）")
        tv.setGravity(Gravity.CENTER)
        kb.addView(tv)
    end
end

-- 【渲染节流】拖动颜色/尺寸滑块时，每个 onTouch 帧都会调 renderPreview：
-- 一次全量渲染要重建整棵预览树（几十个键 × 若干 View）并解码全部背景图，
-- 连续触发会把主线程占满几十秒 —— 表现为「卡死」，严重时被系统判 ANR 杀掉。
-- 这里把 60 ms 内的多次请求合并成一次；合并后一定执行，读取的是当时的内存值，
-- 因此最终画面始终正确，只是少了中间帧。
-- 真实时钟（毫秒）。os.clock() 是 CPU 时间：主线程空闲时它几乎不走，
-- 用它做节流会把"间隔很久"误判成"刚刚渲染过"，导致画面一直慢半拍。
local JSystem = nil
pcall(function() JSystem = luajava.bindClass("java.lang.System") end)
local function wallMs()
    if JSystem then
        local ok, v = pcall(function() return JSystem.currentTimeMillis() end)
        if ok and type(v) == "number" then return v end
    end
    return os.time() * 1000
end

local renderQueued, renderLastT = false, 0
renderPreview = function()
    -- 工具界面已销毁（用户退出）后不再碰 View：Activity 已 detach 时做 addView/layout
    -- 会抛 BadTokenException / IllegalStateException，逃到 Handler 的 Runnable 里
    -- 就是进程级未捕获异常（同进程 = 输入法一起挂）。
    if type(activityDead) == "function" and activityDead() then return end
    local t = wallMs()
    if t - renderLastT < 50 then
        if not renderQueued then
            renderQueued = true
            uiHandler.postDelayed(function()
                renderQueued = false
                if type(activityDead) == "function" and activityDead() then return end
                renderLastT = wallMs()
                local ok, e = pcall(renderPreviewImpl)
                if not ok then logErr("预览渲染", e) end
            end, 60)
        end
        return
    end
    renderLastT = t
    local ok, e = pcall(renderPreviewImpl)
    if not ok then
        logErr("预览渲染", e)
    else
        -- 单次渲染超过 1.2s 就是卡顿/ANR 的前兆，记进报错面板便于定位是哪个主题。
        local cost = wallMs() - t
        if cost > 1200 then
            logErr("预览渲染", "本次耗时 " .. cost .. "ms（主题 " .. tostring(currentTheme)
                .. " / 键盘 " .. tostring(currentKbdFile) .. "），界面会明显卡顿")
        end
    end
end

-- ========== 通用对话框 ==========
-- items: 选项数组（字符串，或任意值 + opts.label 生成显示文本）
-- opts（可选）:
--   filter     = true 时列表顶部加筛选框：空格分隔多个关键字，需全部命中；不区分大小写
--   label      = function(v) 生成显示文本（缺省 tostring(v)）
--   filterHint = 筛选框提示文字
function listDialog(title, items, cb, opts)
    opts = opts or {}
    local function textOf(v)
        if opts.label then
            local ok, s = pcall(opts.label, v)
            if ok and s ~= nil then return tostring(s) end
        end
        return tostring(v)
    end

    local dlg = LuaDialog(activity)
    dlg.setTitle(title)
    local item = {
        LinearLayout;
        layout_width = "fill";
        layout_height = "wrap";
        padding = "14dp";
        { TextView; id = "tv"; textSize = "15sp"; layout_width = "fill"; layout_height = "wrap"; };
    }
    local lv = ListView(activity)
    local shown = {}   -- 当前列表实际显示的项（筛选后与 items 不同）
    local function show(list)
        shown = list
        local adapter = LuaAdapter(activity, item)
        for _, v in ipairs(list) do adapter.add({tv = {text = textOf(v)}}) end
        lv.setAdapter(adapter)
    end
    show(items)
    lv.onItemClick = function(l, v, p, i)
        local sel = shown[p + 1]
        if sel ~= nil then dlg.dismiss(); cb(sel) end
    end

    if not opts.filter then
        dlg.setView(lv)
        dlg.show()
        return
    end

    -- 带筛选框：输入框固定高度，列表随内容伸缩（超出窗口时列表内部滚动）
    local rootL = LinearLayout(activity)
    rootL.setOrientation(LinearLayout.VERTICAL)

    local et = EditText(activity)
    et.setSingleLine(true)
    et.setTextSize(13)
    et.setHint(opts.filterHint or ("输入关键字筛选（共 " .. #items .. " 项）"))
    rootL.addView(et, LinearLayout.LayoutParams(-1, dp(44)))

    local emptyTv = TextView(activity)
    emptyTv.setText("没有匹配项")
    emptyTv.setTextSize(12)
    emptyTv.setTextColor(0xFF8B949E)
    emptyTv.setPadding(dp(16), dp(10), dp(16), dp(10))
    emptyTv.setVisibility(8)   -- 初始 GONE
    rootL.addView(emptyTv, LinearLayout.LayoutParams(-1, -2))
    rootL.addView(lv, LinearLayout.LayoutParams(-1, -2))

    local function filterList(q)
        q = tostring(q or ""):lower()
        if q:match("^%s*$") then return items end
        local terms = {}
        for t in q:gmatch("%S+") do terms[#terms + 1] = t end
        local out = {}
        for _, v in ipairs(items) do
            local hay = textOf(v):lower()
            local hit = true
            for _, t in ipairs(terms) do
                -- plain=true：用户输入的 % - ( 等字符按字面匹配，不当 Lua 模式
                if not hay:find(t, 1, true) then hit = false; break end
            end
            if hit then out[#out + 1] = v end
        end
        return out
    end

    local function apply(q)
        local list = filterList(q)
        show(list)
        if #list == 0 then
            lv.setVisibility(8); emptyTv.setVisibility(0)
        else
            lv.setVisibility(0); emptyTv.setVisibility(8)
        end
    end

    local watcher = {
        afterTextChanged = function(ed)
            -- Editable.toString() 一定给文本；tostring(ed) 在某些 LuaJ 版本给类名，留作兜底
            local s = ""
            local ok, v = pcall(function() return ed.toString() end)
            if ok and type(v) == "string" then
                s = v
            else
                local ok2, v2 = pcall(function() return tostring(ed) end)
                if ok2 and type(v2) == "string" then s = v2 end
            end
            apply(s)
        end,
        beforeTextChanged = function(s, st, c, a) end,
        onTextChanged = function(s, st, b, c) end,
    }
    -- AndroLua 一般支持「表直接当接口」，失败再退回 luajava 代理
    local okWatch = pcall(function() et.addTextChangedListener(watcher) end)
    if not okWatch then
        pcall(function()
            et.addTextChangedListener(luajava.createProxy("android.text.TextWatcher", watcher))
        end)
    end

    dlg.setView(rootL)
    dlg.show()
    -- 弹输入法时让对话框整体上移，列表不被键盘整块盖住
    pcall(function() dlg.getWindow().setSoftInputMode(16) end)
end

-- 简单输入对话框
function inputDialog(title, hint, initial, cb)
    local lay = LinearLayout(activity)
    lay.setOrientation(LinearLayout.VERTICAL)
    lay.setPadding(dp(16), dp(10), dp(16), dp(4))
    local et = EditText(activity)
    et.setSingleLine(true)
    et.setHint(hint or "")
    if initial then et.setText(tostring(initial)) end
    et.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
    lay.addView(et)
    local dlg = LuaDialog(activity)
    dlg.setTitle(title)
    dlg.setView(lay)
    dlg.setButton("确定", function()
        dlg.dismiss()
        cb(tostring(et.getText()))
    end)
    dlg.setButton2("取消", function() dlg.dismiss() end)
    dlg.show()
end

-- HSV 取色（复用经过验证的纯 Lua 实现 + Bitmap 预渲染）
function rgbToHsv(r, g, b)
    r, g, b = r / 255, g / 255, b / 255
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local d = max - min
    local h = 0
    if d > 0 then
        if max == r then h = ((g - b) / d) % 6
        elseif max == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h * 60
    end
    local s = max == 0 and 0 or d / max
    return h, s, max
end
function hsvToRgb(h, s, v)
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b
    if h < 60 then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    return math.floor((r + m) * 255 + 0.5), math.floor((g + m) * 255 + 0.5), math.floor((b + m) * 255 + 0.5)
end
function composeColor(a, h, s, v)
    local r, g, b = hsvToRgb(h, s, v)
    return math.floor(a * 255 + 0.5) * 0x1000000 + r * 0x10000 + g * 0x100 + b
end

-- onPick(numberColor) 回调；允许清空=撤销该样式项传 nil
function colorDialog(title, curNum, onPick)
    curNum = (type(curNum) == "number") and curNum or 0xFF888888
    local a0 = math.floor(curNum / 0x1000000) % 0x100
    local a = a0 / 255
    -- 极低 alpha 的占位色（如主题边框 0x11444444，alpha=17/255≈6.7%）几乎不可见：
    -- 直接继承会让用户选的新颜色依旧透明、宽度也看不出来。编辑时默认提升为不透明，
    -- 让用户选的颜色真实可见；需要半透明时仍可拖动下方透明度滑块调回。
    if a0 < 0x40 then a = 1.0 end
    local r = math.floor(curNum / 0x10000) % 0x100
    local g = math.floor(curNum / 0x100) % 0x100
    local b = curNum % 0x100
    local h, s, v = rgbToHsv(r, g, b)

    local lay = LinearLayout(activity)
    lay.setOrientation(LinearLayout.VERTICAL)
    lay.setPadding(dp(12), dp(8), dp(12), dp(4))
    local midRow = LinearLayout(activity)
    midRow.setOrientation(LinearLayout.HORIZONTAL)
    lay.addView(midRow)
    local SV_H = dp(200)

    local svBox = FrameLayout(activity)
    svBox.setLayoutParams(LinearLayout.LayoutParams(0, SV_H, 1))
    midRow.addView(svBox)
    local svImg = ImageView(activity)
    svImg.setLayoutParams(FrameLayout.LayoutParams(-1, -1))
    svImg.setScaleType(ImageView.ScaleType.FIT_XY)
    svBox.addView(svImg)
    local ring = View(activity)
    local RING = dp(16)
    ring.setLayoutParams(FrameLayout.LayoutParams(RING, RING))
    local ringGd = GradientDrawable()
    ringGd.setShape(GradientDrawable.OVAL)
    ringGd.setStroke(dp(2), 0xFFFFFFFF)
    ringGd.setColor(0x00000000)
    ring.setBackgroundDrawable(ringGd)
    svBox.addView(ring)

    local hueBox = FrameLayout(activity)
    local hueLp = LinearLayout.LayoutParams(dp(24), SV_H)
    hueLp.setMargins(dp(10), 0, 0, 0)
    hueBox.setLayoutParams(hueLp)
    midRow.addView(hueBox)
    local hueImg = ImageView(activity)
    hueImg.setLayoutParams(FrameLayout.LayoutParams(-1, -1))
    hueImg.setScaleType(ImageView.ScaleType.FIT_XY)
    hueBox.addView(hueImg)
    local hueLine = View(activity)
    hueLine.setLayoutParams(FrameLayout.LayoutParams(-1, dp(2)))
    hueLine.setBackgroundColor(0xFFFFFFFF)
    hueBox.addView(hueLine)

    local SV_N = 96
    local function buildSvBitmap()
        local ok, bmp = pcall(function()
            local b0 = Bitmap.createBitmap(SV_N, SV_N, Bitmap.Config.ARGB_8888)
            -- 【必须批量写】旧实现逐像素 setPixel：96×96 = 9216 次 JNI 调用/帧，
            -- 色相条一拖就是每秒几十万次跨语言调用 → 主线程被钉死，输入法同进程一起卡/ANR。
            -- 改成先在 Lua 表里算完，再一次性 setPixels 送过去（LuaJ 不支持时回退逐个写）。
            local px, i = {}, 1
            for y = 0, SV_N - 1 do
                local vv = 1 - y / (SV_N - 1)
                for x = 0, SV_N - 1 do
                    local rr, gg, bb = hsvToRgb(h, x / (SV_N - 1), vv)
                    px[i] = 0xFF000000 + rr * 0x10000 + gg * 0x100 + bb
                    i = i + 1
                end
            end
            local okSet = pcall(function() b0.setPixels(px, 0, SV_N, 0, 0, SV_N, SV_N) end)
            if not okSet then
                i = 1
                for y = 0, SV_N - 1 do
                    for x = 0, SV_N - 1 do b0.setPixel(x, y, px[i]); i = i + 1 end
                end
            end
            return b0
        end)
        if ok then return bmp end
        return nil
    end
    local function buildHueBitmap()
        local HN = 180
        local ok, bmp = pcall(function()
            local b0 = Bitmap.createBitmap(12, HN, Bitmap.Config.ARGB_8888)
            for y = 0, HN - 1 do
                local rr, gg, bb = hsvToRgb(y / (HN - 1) * 360, 1, 1)
                local cc = 0xFF000000 + rr * 0x10000 + gg * 0x100 + bb
                for x = 0, 11 do b0.setPixel(x, y, cc) end
            end
            return b0
        end)
        if ok then return bmp end
        return nil
    end
    local hueBmp = buildHueBitmap()
    if hueBmp then hueImg.setImageBitmap(hueBmp) end
    local function currentColor() return composeColor(a, h, s, v) end

    local hexTv = TextView(activity)
    hexTv.setLayoutParams(LinearLayout.LayoutParams(-1, dp(40)))
    hexTv.setGravity(Gravity.CENTER)
    hexTv.setTextSize(15)
    lay.addView(hexTv)
    local function refreshAll(rebuildSv)
        if rebuildSv ~= false then
            local bmp = buildSvBitmap()
            if bmp then svImg.setImageBitmap(bmp) end
        end
        local bw, bh = svBox.getWidth(), svBox.getHeight()
        if bw > 0 and bh > 0 then
            ring.setX(s * bw - RING / 2)
            ring.setY((1 - v) * bh - RING / 2)
            hueLine.setY(h / 360 * bh)
        end
        local c = currentColor()
        pcall(function() hexTv.setBackgroundColor(c) end)
        hexTv.setText("#" .. string.format("%08X", c))
        local cr = math.floor(c / 0x10000) % 0x100
        local cg = math.floor(c / 0x100) % 0x100
        local cb = c % 0x100
        hexTv.setTextColor((cr * 299 + cg * 587 + cb * 114) / 1000 > 128 and 0xFF000000 or 0xFFFFFFFF)
    end
    svBox.setOnTouchListener(function(view, event)
        local act = event.getAction()
        if act == 0 or act == 2 then
            local w, hh = view.getWidth(), view.getHeight()
            s = math.min(1, math.max(0, event.getX() / w))
            v = math.min(1, math.max(0, 1 - event.getY() / hh))
            refreshAll(false)
        end
        return true
    end)
    -- 色相条拖动：色板必须跟着变，但重建 96×96 位图有成本。限制到 ~14 fps，
    -- 中间帧只更新指示线与数值，手感不受影响，主线程也不会被占满。
    local lastSvT = -1000
    hueBox.setOnTouchListener(function(view, event)
        local act = event.getAction()
        if act == 0 or act == 2 then
            h = math.min(360, math.max(0, event.getY() / view.getHeight() * 360))
            local t = wallMs()
            if act == 0 or t - lastSvT >= 70 then
                lastSvT = t
                refreshAll(true)
            else
                refreshAll(false)
            end
        end
        return true
    end)
    local aRow = LinearLayout(activity)
    aRow.setOrientation(LinearLayout.HORIZONTAL)
    aRow.setGravity(Gravity.CENTER_VERTICAL)
    lay.addView(aRow)
    local aTv = TextView(activity)
    aTv.setText("透明度"); aTv.setTextSize(13)
    aTv.setLayoutParams(LinearLayout.LayoutParams(dp(52), -2))
    aRow.addView(aTv)
    local aSb = SeekBar(activity)
    aSb.setMax(100); aSb.setProgress(math.floor(a * 100 + 0.5))
    aSb.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    aRow.addView(aSb)
    aSb.setOnSeekBarChangeListener({
        onProgressChanged = function(view, progress, fromUser) if fromUser then a = progress / 100 refreshAll() end end,
        onStartTrackingTouch = function() end, onStopTrackingTouch = function() end,
    })
    local hexRow = LinearLayout(activity)
    hexRow.setOrientation(LinearLayout.HORIZONTAL)
    hexRow.setGravity(Gravity.CENTER_VERTICAL)
    lay.addView(hexRow)
    local hexEdit = EditText(activity)
    hexEdit.setSingleLine(true); hexEdit.setHint("hex，如 FFD4DFD7")
    hexEdit.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    hexRow.addView(hexEdit)
    local btnHex = Button(activity)
    btnHex.setText("取色"); btnHex.setAllCaps(false); btnHex.setLayoutParams(LinearLayout.LayoutParams(-2, -2))
    hexRow.addView(btnHex)
    refreshAll()
    btnHex.onClick = function()
        local s0 = tostring(hexEdit.getText()):gsub("#", ""):gsub("0x", ""):gsub("0X", "")
        local n = tonumber(s0, 16)
        if n then
            if #s0 <= 6 then n = n + 0xFF000000 end
            onPick(n)
        else toast("hex 无效") end
    end
    local dlg = LuaDialog(activity)
    dlg.setTitle(title); dlg.setView(lay)
    dlg.setButton("确定", function() dlg.dismiss(); onPick(currentColor()) end)
    dlg.setButton2("取消 / 清空", function() dlg.dismiss(); onPick(nil) end)
    dlg.show()
    uiHandler.postDelayed(function() pcall(function() refreshAll(false) end) end, 150)
end

-- ========== 按键“完整状态”编辑面板（本版核心重写） ==========
-- 点一个键 → 展示：① 该键的全部功能字段（键盘文件）② 该键引用样式表的全部可改样式项（样式文件）
-- 每一项都回显【当前值】，可直接修改；改完点“应用修改”统一落地。

-- 判断一个数值是否像颜色（ARGB / RGB）
function looksLikeColor(key, v)
    if type(v) ~= "number" then return false end
    if key:lower():find("color") or key:lower():find("background") then return true end
    return v > 0xFFFFFF
end

-- 给 ScrollView 容器添加一行标签 + 控件
function addFieldRow(parent, name, widget)
    local row = LinearLayout(activity)
    row.setOrientation(LinearLayout.VERTICAL)
    row.setPadding(0, dp(2), 0, dp(2))
    local tv = TextView(activity)
    tv.setText(name); tv.setTextSize(11)
    tv.setTextColor(0xFF8B949E)
    row.addView(tv)
    row.addView(widget)
    parent.addView(row)
end

-- 样式项控件：按当前值类型给出合适的编辑器
function makeStyleWidget(path, name, cur, onChange)
    if looksLikeColor(name, cur) then
        local b = Button(activity)
        b.setAllCaps(false)
        b.setTextSize(12)
        b.setLayoutParams(LinearLayout.LayoutParams(-1, dp(38)))
        local function paint(n)
            b.setText(name .. "  " .. (type(n) == "number" and string.format("#%08X", n) or "未设置"))
            if type(n) == "number" then
                pcall(function() b.setBackgroundColor(n) end)
                local lum = ((math.floor(n / 0x10000) % 0x100) * 299 + (math.floor(n / 0x100) % 0x100) * 587 + (n % 0x100) * 114) / 1000
                b.setTextColor(lum > 128 and 0xFF000000 or 0xFFFFFFFF)
            end
        end
        paint(cur)
        b.onClick = function()
            colorDialog("修改 " .. name, type(cur) == "number" and cur or nil, function(n)
                if n then onChange(n) paint(n) end
            end)
        end
        return b
    elseif type(cur) == "number" then
        local et = EditText(activity)
        et.setSingleLine(true); et.setInputType(2)  -- number
        et.setText(tostring(cur))
        et.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
        return et, function() return tonumber(tostring(et.getText())) end
    else
        local et = EditText(activity)
        et.setSingleLine(true)
        et.setText(cur == nil and "" or tostring(cur))
        et.setHint("留空=未设置")
        et.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
        return et, function()
            local s = tostring(et.getText())
            if s == "" then return nil end   -- 注意：Lua 里 `x and nil or y` 在 x 为真时仍返回 y
            return s
        end
    end
end

-- ===== 单键专属样式（改一个键的样式只影响它自己）=====
-- trime2 里样式是共享的：多个键可指向同一个 style 表（多数键回退到 "key"）。
-- 直接改 stName.<字段> 会波及所有同款键。为做到"只影响当前键"，首次编辑某键样式时，
-- 把该键当前生效的样式（含从 key 继承的字段，按 channelField 的解析链展开）深拷贝成
-- 一份独立表 studio_r{r}k{k}，并把该键的 style 字段改指向它。以后该键所有样式编辑
-- 都落到这张专属表上，其他键不受影响。
local function deepCopyTable(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, sub in pairs(v) do out[deepCopyTable(k, seen)] = deepCopyTable(sub, seen) end
    return out
end

-- 该键专属样式表名（含行列，稳定唯一）。名字避免与真实主题样式名冲突。
local function ownStyleName(r, k)
    return string.format("__studio_r%dk%d", r, k)
end

-- 把某键当前生效的样式字段展开到一张新表（含继承链），返回该表及涉及的字段路径。
-- 字段全集取 STYLE_FIELDS + channelStyleItems 各通道清单 + 样式表里真实存在的叶子，
-- 用 channelField(stName,"",field) / 子路径取值，保证专属表与原键显示逐字段一致。
local function snapshotKeyStyle(stName, r, k)
    local snap = {}
    local fields = {}
    local seenF = {}
    local function addField(f)
        if type(f) == "string" and f ~= "" and not seenF[f] then seenF[f] = true; fields[#fields + 1] = f end
    end
    -- 关键标量字段（与 STYLE_FIELDS 主集合一致；这里内联以免依赖后方 local 定义）
    local CORE = {"background", "text_color", "text_size", "corner_radius", "stroke_width",
        "stroke_color", "elevation", "shadow_color", "font", "gravity", "offset_x", "offset_y",
        "long_click_time", "repeat_click_time", "vibration_enabled", "sound_enabled", "show",
        "label", "size", "width"}
    for _, f in ipairs(CORE) do addField(f) end
    -- 递归收集样式表里所有叶子键名（相对路径），连同嵌套（pressed.*/hint.*/margins.*…）
    local function collect(node, prefix, depth)
        if type(node) ~= "table" or depth > 6 then return end
        for kk, vv in pairs(node) do
            if type(kk) == "string" then
                local rel = (prefix ~= "" and (prefix .. "." .. kk) or kk)
                if type(vv) == "table" then collect(vv, rel, depth + 1) else addField(rel) end
            end
        end
    end
    local roots = {}
    if stName and stName ~= "" then roots[#roots + 1] = stName end
    roots[#roots + 1] = "key"
    for _, root in ipairs(roots) do
        if styleEnv and type(styleEnv[root]) == "table" then collect(styleEnv[root], "", 0) end
    end
    -- 展开每个字段的当前生效值（含 styleEdits 覆盖 + 继承链）
    for _, f in ipairs(fields) do
        local parent, child = f:match("^(.*)%.([^%.]+)$")
        if not parent then parent, child = "", f end
        local v = channelField(stName, parent, child)
        if v == nil then v = getValue((stName or "key") .. "." .. f) end
        if v ~= nil and v ~= UNSET then setIn(snap, f, v) end
    end
    return snap, fields
end

-- 计算某键当前"生效样式名"（渲染Rule：style 字段 → click 回退 → key）。纯读，不改任何东西。
-- 若该键已有专属表则返回专属名。
local function keyEffectiveStyleName(r, k)
    local base = "rows." .. r .. ".keys." .. k
    local stName = getKbdValue(base .. ".style")
    if type(stName) == "string" and stName ~= "" then return stName end
    local c = getKbdValue(base .. ".click")
    if type(c) == "number" then c = tostring(c) end
    if type(c) == "string" and c ~= "" then return c end
    return "key"
end

-- 确保某键已有专属样式表；返回专属样式名。失败返回 nil。
-- 会复制当前生效样式、改 style 指针 —— 有副作用，只在用户点"应用修改"时调用。
local function ensureOwnStyle(r, k)
    local base = "rows." .. r .. ".keys." .. k
    local own = ownStyleName(r, k)
    local cur = getKbdValue(base .. ".style")
    if cur == own and styleEnv and type(styleEnv[own]) == "table" then return own end
    if not styleEnv then return nil end
    local stName = keyEffectiveStyleName(r, k)
    local snap = snapshotKeyStyle(stName, r, k)
    styleEnv[own] = snap
    newStyleTables[own] = true
    -- 把该键 style 指针改到专属表（这样渲染/取值都用新表，只影响本键）
    -- 用非 dirty 变体：style 指针不影响文字/序号，保留真机文字快照，角标不回退
    setKbdStyleValue(base .. ".style", own)
    return own
end

-- ===== 事件通道编辑器（核心新交互）=====
-- 样式字段 -> 中文名。弹窗里显示中文，写入仍按 it.path 的真实字段名，不受影响。
local FIELD_CN = {
    background = "背景", text_color = "文字颜色", text_size = "文字大小",
    corner_radius = "圆角", stroke_width = "描边宽度", stroke_color = "描边颜色",
    stroke = "描边", elevation = "阴影高度", shadow_color = "阴影颜色",
    font = "字体", gravity = "对齐方式", offset_x = "水平偏移", offset_y = "垂直偏移",
    show = "是否显示", vibration_enabled = "按键震动", sound_enabled = "按键音效",
    scale_x = "横向缩放", scale_y = "纵向缩放",
    translation_x = "水平位移", translation_y = "垂直位移", translation_z = "层级位移",
    left = "左", top = "上", right = "右", bottom = "下",
    label = "键面文字", width = "键宽", height = "键高", size = "字号", ascii = "ASCII 覆盖",
    long_click_time = "长按判定(毫秒)", repeat_click_time = "长按重复(毫秒)",
    pressed = "按下", hint = "角标", margins = "外边距", padding = "内边距",
    image = "图片", alpha = "不透明度", typeface = "字形", color = "颜色",
}
local function fieldCN(f)
    return FIELD_CN[f] or f
end

-- 列出某通道相关的样式项（路径 + 名称 + 当前值）。既有策展的常用项，也保留样式表里
-- 实际存在的额外项；每一项都回显当前值（getValue 已含内存改动的覆盖）。
function channelStyleItems(stName, chId)
    local items, seen = {}, {}
    -- cur 改为走继承链的生效值（见 effectiveStyleValue），与真机渲染口径一致；
    -- 写入路径 path 不变（仍落到本键专属表 own.<rel>）。
    local function addItem(path, name, rel, f)
        if seen[path] then return end
        seen[path] = true
        table.insert(items, { path = path, name = name, cur = effectiveStyleValue(stName, rel, f) })
    end
    local function join(a, b)
        if a == nil or a == "" then return b end
        if b == nil or b == "" then return a end
        return a .. "." .. b
    end
    local function addFields(relBase, fields, prefix)
        local base = join(stName, relBase) or ""
        for _, f in ipairs(fields) do
            addItem(join(base, f), prefix .. fieldCN(f), relBase, f)
        end
        -- 额外字段：样式表里真实存在但不在策展清单里的字符串/数值项
        local t = getFrom(styleEnv, base)
        if type(t) == "table" then
            local extra = {}
            for kk, vv in pairs(t) do
                if type(kk) == "string" and (type(vv) == "number" or type(vv) == "string" or type(vv) == "boolean") then
                    local has = false
                    for _, f in ipairs(fields) do if f == kk then has = true break end end
                    if not has then table.insert(extra, kk) end
                end
            end
            table.sort(extra)
            for _, kk in ipairs(extra) do
                addItem(join(base, kk), prefix .. fieldCN(kk), relBase, kk)
            end
        end
    end

    local MAIN = {"background", "text_color", "text_size", "corner_radius", "elevation", "shadow_color",
        "stroke_width", "stroke_color", "font", "gravity", "offset_x", "offset_y", "show",
        "vibration_enabled", "sound_enabled"}
    local PRESSED = {"background", "text_color", "shadow_color", "scale_x", "scale_y",
        "translation_x", "translation_y", "translation_z", "show"}
    local HINT = {"text_color", "text_size", "font", "show", "gravity", "offset_x", "offset_y"}
    local LONG = {"text_color", "text_size", "font", "show", "gravity", "offset_x", "offset_y",
        "vibration_enabled", "sound_enabled"}

    if chId == "click" then
        addFields("", MAIN, "常规·")
        addFields("pressed", PRESSED, "按下·")
        addFields("margins", {"left", "top", "right", "bottom"}, "留白·")
        addFields("padding", {"left", "top", "right", "bottom"}, "内边距·")
    elseif chId == "long_click" then
        addFields("long_click", LONG, "长按·")
        addFields("pressed.long_click", {"text_color", "show"}, "按下(长按)·")
    else
        local dir = chId:match("swipe_(.+)") or ""
        addFields("hint." .. dir, HINT, "提示·")
        addFields("hint", HINT, "提示(通用)·")
        addFields("pressed.hint." .. dir, {"text_color", "show"}, "按下(提示)·")
    end
    return items
end

-- 布尔/颜色/数值/字符串 通用控件
function channelWidget(path, name, cur, onChange)
    local kind = type(cur)
    if kind == "boolean" then
        local b = Button(activity)
        b.setAllCaps(false); b.setTextSize(12)
        b.setLayoutParams(LinearLayout.LayoutParams(-1, dp(36)))
        local val = cur
        local function paint()
            b.setText(name .. "    " .. (val == nil and "（未设置）" or (val and "是" or "否")))
        end
        paint()
        b.onClick = function()
            if val == true then val = false else val = true end
            paint(); onChange(val)
        end
        return b, function() return val end
    end
    return makeStyleWidget(path, name, cur, onChange)
end

-- ========== 批量样式编辑（快捷工具：一次改一批）==========
-- 这是"一次改所有/部分键"的快捷入口，按作用范围（全部/字母/数字/功能键）批量落到多个 style 表。
-- 单个按键的完整编辑（含该键自己的样式）在 channelEditDialog 里，改单键样式只影响该键（专属副本）。
-- 注意：已被专属化的键 style 指向 __studio_rXkY，批量入口会连同这些专属表一起改（等于用户主动要一起改）。
local STYLE_SCOPES = {
    { id = "all",      name = "全部按键" },
    { id = "letter",   name = "字母键" },
    { id = "digit",    name = "数字键" },
    { id = "function", name = "功能键" },
    { id = "toolbar",  name = "工具栏按键" },
}
-- 通用样式字段（trime2 KeyStyle 的常见项）；写值时按 <style名>.<字段> 落到每个 style 表。
local STYLE_FIELDS = {
    {"background", "背景(颜色/图片)"}, {"text_color", "文字颜色"}, {"text_size", "文字大小"},
    {"corner_radius", "圆角"}, {"stroke_width", "边框宽度"}, {"stroke_color", "边框颜色"},
    {"elevation", "阴影高度"}, {"shadow_color", "阴影颜色"},
    {"font", "字体"}, {"gravity", "对齐"}, {"offset_x", "偏移X"}, {"offset_y", "偏移Y"},
    {"long_click_time", "长按响应(ms)"}, {"repeat_click_time", "长按重复(ms)"},
    {"vibration_enabled", "按键震动"}, {"sound_enabled", "按键音效"},
    {"pressed.background", "按下·背景"}, {"pressed.text_color", "按下·文字色"},
    {"pressed.shadow_color", "按下·阴影色"}, {"pressed.corner_radius", "按下·圆角"},
    {"scale_x", "缩放X"}, {"scale_y", "缩放Y"},
    {"translation_x", "平移X"}, {"translation_y", "平移Y"}, {"translation_z", "平移Z"},
    {"hint.background", "提示·背景"}, {"hint.text_color", "提示·文字色"},
    {"hint.text_size", "提示·文字大小"},
    {"long_click.background", "长按·背景"}, {"long_click.text_color", "长按·文字色"},
    {"long_click.text_size", "长按·文字大小"},
    {"margins.left", "留白·左"}, {"margins.top", "留白·上"},
    {"margins.right", "留白·右"}, {"margins.bottom", "留白·下"},
    {"padding.left", "内距·左"}, {"padding.top", "内距·上"},
    {"padding.right", "内距·右"}, {"padding.bottom", "内距·下"},
}
-- 计算某键定义用的 style 名（与渲染 Rule 一致：style 字段 → click 回退 → key）
local function styleNameOfKeyDef(def)
    if type(def) ~= "table" then return nil end
    local s = def.style
    if type(s) == "string" and s ~= "" then return s end
    local c = def.click
    if type(c) == "number" then c = tostring(c) end
    if type(c) == "string" and c ~= "" then return c end
    return "key"
end
-- 按类别返回该范围涉及的 style 名（去重）与键数量统计
local function styleNamesInScope(scope)
    local names, seen, keyCount = {}, {}, 0
    -- 工具栏 / 候选栏范围：style 名固定，不来自键盘 rows
    if scope == "toolbar" then
        local function add(sn)
            if type(sn) == "string" and sn ~= "" and not seen[sn] then
                seen[sn] = true; names[#names + 1] = sn; keyCount = keyCount + 1
            end
        end
        add("toolbar.key")
        if type(styleEnv) == "table" and type(styleEnv.toolbar) == "table"
            and type(styleEnv.toolbar.keys) == "table" then
            for _, o in pairs(styleEnv.toolbar.keys) do
                if type(o) == "table" and type(o.style) == "string" then add(o.style) end
            end
        end
        table.sort(names)
        return names, keyCount
    end
    if type(kbdEnv) ~= "table" or type(kbdEnv.rows) ~= "table" then return names, 0 end
    for _, row in pairs(kbdEnv.rows) do
        if type(row) == "table" and type(row.keys) == "table" then
            for _, def in pairs(row.keys) do
                if type(def) == "table" then
                    local label = def.label
                    if label == nil and type(def.click) == "string" then label = def.click end
                    label = tostring(label or "")
                    local cat
                    if label:match("^[A-Za-z]$") then cat = "letter"
                    elseif label:match("^[0-9]$") then cat = "digit"
                    else cat = "function" end
                    local include = (scope == "all") or (cat == scope)
                    if include then
                        local sn = styleNameOfKeyDef(def)
                        if sn and not seen[sn] then seen[sn] = true; names[#names + 1] = sn end
                        keyCount = keyCount + 1
                    end
                end
            end
        end
    end
    table.sort(names)
    return names, keyCount
end

-- ============ 通用「分类按钮 + 项目按钮」编辑面板（与按键编辑面板同款界面）============
-- 供样式编辑 / 键盘调整复用：分类按钮(每行3个，动态编号①…) + 两列项目按钮(名称灰/当前值蓝)
-- 项目 item = { name, kind, cur, v, commit, onEdit, isAction, onClick }
--   kind: bool/color/number/text/event；onEdit 可选，自定义编辑器(item, done)
--   isAction: 动作项，渲染成整行按钮，点击直接执行 onClick
local function utf16units(s)
    local n, i = 0, 1
    while i <= #s do
        local c = s:byte(i)
        local cp
        if c < 0x80 then cp = c; i = i + 1
        elseif c < 0xE0 then cp = (c - 0xC0) * 0x40 + (s:byte(i+1) - 0x80); i = i + 2
        elseif c < 0xF0 then cp = (c - 0xE0) * 0x1000 + (s:byte(i+1) - 0x80) * 0x40 + (s:byte(i+2) - 0x80); i = i + 3
        else cp = (c - 0xF0) * 0x40000 + (s:byte(i+1) - 0x80) * 0x1000 + (s:byte(i+2) - 0x80) * 0x40 + (s:byte(i+3) - 0x80); i = i + 4 end
        n = n + (cp >= 0x10000 and 2 or 1)
    end
    return n
end

local function catSame(a, b)
    if a == nil and b == nil then return true end
    if a == nil or b == nil then return false end
    return tostring(a) == tostring(b)
end

local function catValText(v, kind)
    if v == nil then return "（未设置）" end
    if kind == "bool" then return v and "开" or "关" end
    if kind == "color" and type(v) == "number" then return string.format("#%06X", v % 0x1000000) end
    return tostring(v)
end

-- 名称=中性灰，当前值=强调蓝；颜色项在值前加一个小色块■（染实际色，不撑满按钮）
local function paintCatBtn(btn, it, accent)
    accent = accent or 0xFF58A6FF
    local name = it.name or ""
    local val = catValText(it.v, it.kind) or ""
    local isColor = (it.kind == "color" and type(it.v) == "number")
    local swatch = isColor and "■ " or ""
    local text = name .. "\n  " .. swatch .. val
    local spanned = false
    if _SpannableString and _Spannable and _FgSpan then
        pcall(function()
            local ss = _SpannableString(text)
            local total = ss.length()
            local valStart = math.max(0, total - utf16units(val))
            local swStart = math.max(0, valStart - utf16units(swatch))
            if total > 0 then
                ss.setSpan(_FgSpan(0xFF8B949E), 0, swStart, _Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                if isColor and valStart > swStart then
                    ss.setSpan(_FgSpan(it.v), swStart, valStart, _Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                end
                if total > valStart then
                    ss.setSpan(_FgSpan(accent), valStart, total, _Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                end
            end
            btn.setText(ss)
            spanned = true
        end)
    end
    if not spanned then btn.setText(text) end
end

local function editCatItem(it, done)
    if it.onEdit then it.onEdit(it, done); return end
    if it.kind == "bool" then
        done(not it.v)
    elseif it.kind == "color" then
        colorDialog("修改 " .. it.name, type(it.v) == "number" and it.v or nil,
            function(n) if n then done(n) end end)
    elseif it.kind == "event" then
        local opts = { "✎ 手动输入…" }
        local keyList = {}
        for key, _ in pairs(presetKeysCache or {}) do keyList[#keyList + 1] = key end
        table.sort(keyList)
        for _, key in ipairs(keyList) do
            local l = resolveEventLabel(key)
            opts[#opts + 1] = (l and l ~= "" and l ~= key) and (key .. "  " .. l) or key
        end
        listDialog("选择 " .. it.name, opts, function(sel)
            if sel == "✎ 手动输入…" then
                inputDialog(it.name, "如 a / space / Return", it.v, function(s) done(s ~= "" and s or nil) end)
            else
                done(sel:match("^([^%s]+)") or sel)
            end
        end, { filter = true, filterHint = "输入关键字筛选预置事件" })
    else
        local isNum = (it.kind == "number")
        inputDialog("修改 " .. it.name, isNum and "输入数字" or "留空=删除该项", it.v, function(s)
            if isNum then
                local n = tonumber(s)
                if n == nil then toast("请输入数字") return end
                done(n)
            else
                done(s ~= "" and s or nil)
            end
        end)
    end
end

-- cfg = { title, accent, tip, applyText, cancelText, groups, scopeButtons, headText, onApply }
--   onApply: function() return changedCount end；返回 0/nil 视为无改动
--   scopeButtons: {{name, active, onClick}} 顶部作用范围切换行(可选)
function categoryPanelDialog(cfg)
    local accent = cfg.accent or 0xFF58A6FF
    local dlg = LuaDialog(activity)
    local lay = LinearLayout(activity)
    lay.setOrientation(LinearLayout.VERTICAL)
    lay.setPadding(dp(10), dp(6), dp(10), dp(6))

    if cfg.scopeButtons and #cfg.scopeButtons > 0 then
        local scRow = LinearLayout(activity); scRow.setOrientation(LinearLayout.HORIZONTAL)
        for _, sb in ipairs(cfg.scopeButtons) do
            local b = Button(activity); b.setAllCaps(false); b.setTextSize(9); b.setText(sb.name)
            b.setLayoutParams(LinearLayout.LayoutParams(0, dp(34), 1))
            if sb.active then b.setTextColor(accent) end
            b.onClick = sb.onClick
            scRow.addView(b)
        end
        lay.addView(scRow)
    end
    if cfg.headText then
        local htv = TextView(activity); htv.setTextSize(11); htv.setTextColor(0xFF8B949E)
        htv.setText(cfg.headText); lay.addView(htv)
    end

    local NUM_CN = { "①","②","③","④","⑤","⑥","⑦","⑧","⑨","⑩","⑪","⑫","⑬","⑭","⑮" }
    local groups = cfg.groups or {}
    for i, g in ipairs(groups) do g.name = (NUM_CN[i] or (i .. ".")) .. " " .. (g.name or "") end

    local catBtns, contentBox = {}, LinearLayout(activity)
    contentBox.setOrientation(LinearLayout.VERTICAL)

    local function showGroup(idx)
        local g = groups[idx]
        contentBox.removeAllViews()
        for ci, b in ipairs(catBtns) do b.setTextColor(ci == idx and accent or 0xFF8B949E) end
        if not g then return end
        local items = g.items or {}
        if #items == 0 then
            local tv = TextView(activity); tv.setText("（本分类暂无可修改项）")
            tv.setTextColor(0xFF8B949E); tv.setTextSize(12); contentBox.addView(tv)
        end
        local row, col = nil, 0
        for _, it in ipairs(items) do
            if it.isAction then
                local b = Button(activity); b.setAllCaps(false); b.setTextSize(11); b.setText(it.name)
                b.setLayoutParams(LinearLayout.LayoutParams(-1, dp(42)))
                b.onClick = it.onClick
                contentBox.addView(b); col = 0
            else
                if col % 2 == 0 then
                    row = LinearLayout(activity); row.setOrientation(LinearLayout.HORIZONTAL)
                    contentBox.addView(row, LinearLayout.LayoutParams(-1, dp(48)))
                end
                local b = Button(activity); b.setAllCaps(false); b.setTextSize(11)
                b.setLayoutParams(LinearLayout.LayoutParams(0, dp(48), 1))
                paintCatBtn(b, it, accent)
                local captured = b
                b.onClick = function()
                    editCatItem(it, function(v) it.v = v; paintCatBtn(captured, it, accent) end)
                end
                row.addView(b); col = col + 1
            end
        end
    end

    local catRow
    for i, g in ipairs(groups) do
        if (i - 1) % 3 == 0 then
            catRow = LinearLayout(activity); catRow.setOrientation(LinearLayout.HORIZONTAL); lay.addView(catRow)
        end
        local b = Button(activity); b.setAllCaps(false); b.setTextSize(10); b.setText(g.name)
        b.setLayoutParams(LinearLayout.LayoutParams(0, dp(36), 1))
        b.onClick = function() showGroup(i) end
        catRow.addView(b); catBtns[#catBtns + 1] = b
    end

    local tip = TextView(activity); tip.setTextSize(10); tip.setTextColor(0xFF8B949E)
    tip.setText(cfg.tip or "点分类 → 点项目按钮改值 → 应用修改")
    lay.addView(tip)
    lay.addView(contentBox)

    dlg.setTitle(cfg.title or "编辑")
    local sv = ScrollView(activity); sv.addView(lay); dlg.setView(sv)
    dlg.setButton(cfg.applyText or "应用修改", function()
        local n = cfg.onApply and cfg.onApply() or 0
        if n == 0 then toast("没有修改任何项"); return end
        dlg.dismiss(); renderPreview()
        toast("已应用 " .. n .. " 项改动")
    end)
    dlg.setButton2(cfg.cancelText or "取消", function() dlg.dismiss() end)
    if #groups > 0 then showGroup(1) end
    dlg.show()
    return dlg
end

-- 背景二选一编辑器：图片文件名 或 纯色（与真机 Style.getDrawable 一致）
function backgroundEditDialog(title, cur, done)
    local dlg = LuaDialog(activity)
    local lay = LinearLayout(activity); lay.setOrientation(LinearLayout.VERTICAL)
    lay.setPadding(dp(12), dp(6), dp(12), dp(6))
    local colorInit = type(cur) == "number" and cur or nil
    local imgInit = type(cur) == "string" and cur or ""
    local state = { value = colorInit }
    local tv = TextView(activity); tv.setTextSize(11); tv.setTextColor(0xFF8B949E)
    tv.setText("填图片文件名，或选一个纯色（二者互斥，后定的为准）"); lay.addView(tv)
    local cb = Button(activity); cb.setAllCaps(false); cb.setTextSize(11)
    local function paintColor(n)
        if type(n) == "number" then
            cb.setText("颜色：" .. string.format("#%08X", n))
            pcall(function() cb.setBackgroundColor(n) end)
            local lum = ((math.floor(n/0x10000)%0x100)*299 + (math.floor(n/0x100)%0x100)*587 + (n%0x100)*114)/1000
            pcall(function() cb.setTextColor(lum > 128 and 0xFF000000 or 0xFFFFFFFF) end)
        else
            cb.setText("颜色：未设置")
            pcall(function() cb.setBackgroundColor(0xFF30363D); cb.setTextColor(0xFFD0D0D0) end)
        end
    end
    paintColor(colorInit)
    cb.onClick = function()
        colorDialog("选择背景色", state.value, function(n) if n then state.value = n; paintColor(n) end end)
    end
    lay.addView(cb, LinearLayout.LayoutParams(-1, dp(40)))
    local et = EditText(activity); et.setSingleLine(true); et.setText(imgInit); et.setHint("留空=用背景颜色")
    lay.addView(et, LinearLayout.LayoutParams(-1, dp(40)))
    dlg.setTitle(title)
    dlg.setButton("确定", function()
        local t = tostring(et.getText()):gsub("^%s+", ""):gsub("%s+$", "")
        if t ~= imgInit then done(t == "" and nil or t)
        elseif not catSame(state.value, colorInit) then done(state.value)
        else done(cur) end
        dlg.dismiss()
    end)
    dlg.setButton2("取消", function() dlg.dismiss() end)
    local sv = ScrollView(activity); sv.addView(lay); dlg.setView(sv); dlg.show()
end

-- 样式编辑（批量，按作用范围）：分类-项目按钮界面，与按键编辑面板同款
styleEditorDialog = function(curScope)
    curScope = curScope or "all"
    if not styleEnv then toast("样式还没加载好") return end
    local names, cnt = styleNamesInScope(curScope)
    local scopeName = "全部按键"
    for _, sc in ipairs(STYLE_SCOPES) do if sc.id == curScope then scopeName = sc.name end end
    local rep = names[1] or "key"

    local myDlg
    local scopeButtons = {}
    for _, sc in ipairs(STYLE_SCOPES) do
        scopeButtons[#scopeButtons + 1] = {
            name = sc.name, active = (sc.id == curScope),
            onClick = function()
                pcall(function() if myDlg then myDlg.dismiss() end end)
                styleEditorDialog(sc.id)
            end,
        }
    end

    local function fieldGroup(f)
        if f:find("^pressed%.") then return "按下样式" end
        if f:find("^hint%.") then return "提示样式" end
        if f:find("^long_click%.") then return "长按样式" end
        if f:find("^margins%.") then return "留白边距" end
        if f:find("^padding%.") then return "内距" end
        return "常规样式"
    end

    local groups, gmap, allItems = {}, {}, {}
    local function grp(nm)
        if not gmap[nm] then gmap[nm] = { name = nm, items = {} }; groups[#groups + 1] = gmap[nm] end
        return gmap[nm]
    end
    for _, fd in ipairs(STYLE_FIELDS) do
        local fpath, fname = fd[1], fd[2]
        local fullPath = rep .. "." .. fpath
        local cur = getValue(fullPath)
        local kind = "text"
        if looksLikeColor(fname, cur) then kind = "color"
        elseif type(cur) == "boolean" then kind = "bool"
        elseif type(cur) == "number" then kind = "number" end
        local it = { name = fname, kind = kind, cur = cur, v = cur }
        it.commit = function(v)
            for _, sn in ipairs(names) do
                local path = sn .. "." .. fpath
                if v == nil then unsetStyleValue(path) else setValue(path, v) end
            end
        end
        grp(fieldGroup(fpath)).items[#grp(fieldGroup(fpath)).items + 1] = it
        allItems[#allItems + 1] = it
    end

    local head = "作用范围：" .. scopeName .. "　影响 " .. cnt .. " 个键 / " .. #names .. " 个样式表\n"
        .. (#names > 0 and ("样式：" .. table.concat(names, ", ")) or "（该范围未找到按键）")
        .. "\n当前值取自代表样式 " .. rep .. "，应用时写入该范围全部样式表"

    myDlg = categoryPanelDialog({
        title = "样式编辑 · " .. scopeName,
        accent = 0xFFE3B341,
        headText = head,
        scopeButtons = scopeButtons,
        groups = groups,
        applyText = "应用到此范围",
        onApply = function()
            if #names == 0 then toast("该范围没有按键") return 0 end
            local n = 0
            for _, it in ipairs(allItems) do
                if not catSame(it.v, it.cur) then it.commit(it.v); n = n + 1 end
            end
            return n
        end,
    })
end

function channelEventSummary(r, k, ch)
    local ev = getKbdValue("rows." .. r .. ".keys." .. k .. "." .. ch.ev)
    if type(ev) == "string" and ev ~= "" then
        local l = resolveEventLabel(ev)
        return ev .. ((l and l ~= "" and ("（" .. l .. "）")) or "")
    end
    return "（未设置）"
end

-- 源码显示文字逻辑（Key.getLabel / Event.getLabel，见渲染 3913-3921）：
-- 该状态 view 上显示的文字 = 显式显示字段(label / hint_*) 优先；为空时从本状态的
-- 事件串(ev) 用 resolveEventLabelFull 推导（preset / 去{} / table 的 label·send·text）。
-- 面板回显不能"没写 label 就是未设置"——那会漏掉真机实际从事件推导出来的显示文字。
function resolveDisplayText(r, k, ch)
    local base = "rows." .. r .. ".keys." .. k
    local textField = ch.label or ch.hint
    local explicit = textField and getKbdValue(base .. "." .. textField) or nil
    if type(explicit) == "string" and explicit ~= "" then return explicit end
    if type(explicit) == "number" then return tostring(explicit) end
    -- 显式字段为空：按源码从本状态事件串推导（string/number/table 都覆盖）
    local ev = getKbdValue(base .. "." .. ch.ev)
    if ev ~= nil then
        local full = resolveEventLabelFull(ev)
        if type(full) == "string" and full ~= "" then return full end
    end
    return nil
end

channelEditDialog = function(r, k, chId)
    local ch = channelById(chId) or CHANNELS[1]
    local base = "rows." .. r .. ".keys." .. k
    local kdef = kbdEnv and kbdEnv.rows and kbdEnv.rows[r] and kbdEnv.rows[r].keys[k]
    if type(kdef) ~= "table" then return end

    local own = ownStyleName(r, k)
    local stNameNow = keyEffectiveStyleName(r, k)
    local dlg = LuaDialog(activity)

    local lay = LinearLayout(activity)
    lay.setOrientation(LinearLayout.VERTICAL)
    lay.setPadding(dp(10), dp(6), dp(10), dp(6))

    -- 通道切换按钮行（一处不重开窗口，直接切换编辑通道）
    local swRow = LinearLayout(activity)
    swRow.setOrientation(LinearLayout.HORIZONTAL)
    for _, c in ipairs(CHANNELS) do
        local b = Button(activity)
        b.setAllCaps(false); b.setTextSize(9); b.setText(c.name)
        b.setLayoutParams(LinearLayout.LayoutParams(0, dp(34), 1))
        if c.id == ch.id then b.setTextColor(c.color) end
        b.onClick = function()
            dlg.dismiss()
            channelEditDialog(r, k, c.id)
        end
        swRow.addView(b)
    end
    lay.addView(swRow)

    local title = TextView(activity)
    title.setTextSize(12); title.setTextColor(ch.color)
    local curEv0 = getKbdValue(base .. "." .. ch.ev)
    title.setText("第" .. r .. "行第" .. k .. "键 · " .. ch.name .. "　当前事件：" ..
        (type(curEv0) == "string" and curEv0 ~= "" and curEv0 or "（未设置）"))
    lay.addView(title)

    -- ============ 构建所有编辑项（持久表：切换分类不丢未应用的改动）============
    -- item = { name, kind, v(当前待写值), cur(初始值), commit(v), isStyle }
    local groups = {}
    local allItems = {}
    -- 分组名不带编号：click 通道比其它通道多一个"下标提示"组，硬编码编号会出现
    -- 子编号或缺号。改为构建完成后按实际顺序统一动态编号（见分类按钮前的编号循环）。
    -- isActions 标记"位置增删"动作组，showGroup 据此识别，不再靠组名字符串匹配。
    local function newGroup(name, isActions)
        local g = { name = name, items = {}, isActions = isActions and true or false }
        groups[#groups + 1] = g
        return g
    end
    local function addItem(g, name, kind, cur, commit, isStyle)
        local it = { name = name, kind = kind, v = cur, cur = cur, commit = commit, isStyle = isStyle and true or false }
        g.items[#g.items + 1] = it
        allItems[#allItems + 1] = it
        return it
    end
    local function valText(v, kind)
        if v == nil then return "（未设置）" end
        if kind == "bool" then return v and "开" or "关" end
        if kind == "color" and type(v) == "number" then return string.format("#%06X", v % 0x1000000) end
        return tostring(v)
    end

    -- 事件串
    local gEvent = newGroup("事件")
    local curEv = getKbdValue(base .. "." .. ch.ev)
    addItem(gEvent, "事件字符串", "event",
        (type(curEv) == "string" and curEv ~= "" and curEv) or nil,
        function(v)
            local path = base .. "." .. ch.ev
            if v == nil or v == "" then
                if getKbdValue(path) ~= nil then unsetKbdValue(r, k, ch.ev) end
            else
                setKbdValue(path, tostring(v))
            end
            disableLiveTextOfKey(r, k)
        end, false)

    -- ② 显示文字：就是这个状态 view 上当前显示的文字，和"事件"是两个不同字段。
    --    click 通道 → label 字段（键面文字）；长按/各方向 → 各自的角标文字字段(ch.hint)。
    --    事件(ev) 决定触发动作，显示文字(label/hint_*) 决定键上呈现的字符。
    local textField = ch.label or ch.hint
    if textField then
        local gText = newGroup("显示文字")
        -- 按源码显示逻辑回显：显式字段优先，为空则从事件串推导（不是"没 label 就未设置"）
        local curText = resolveDisplayText(r, k, ch)
        addItem(gText, "显示文字", "text",
            (type(curText) == "string" and curText ~= "" and curText) or nil,
            function(v)
                local path = base .. "." .. textField
                if v == nil or v == "" then
                    if getKbdValue(path) ~= nil then unsetKbdValue(r, k, textField) end
                else
                    setKbdValue(path, tostring(v))
                end
                disableLiveTextOfKey(r, k)
            end, false)
    end

    -- 下标提示（仅 click 通道，单独一组）：真机 mHints[0]——独立 hint。
    --     它的显示文字(ch.hint="hint" 字段) + 全部样式项(key.hint.*：偏移/字体/颜色/大小/对齐/显示)
    --     都归到这一组里，作为一个完整的独立单元。
    if ch.id == "click" then
        local gSub = newGroup("下标提示")
        -- 下标提示的显示文字
        local curSubText = getKbdValue(base .. "." .. ch.hint)
        addItem(gSub, "下标提示文字", "text",
            (type(curSubText) == "string" and curSubText ~= "" and curSubText) or nil,
            function(v)
                local path = base .. "." .. ch.hint
                if v == nil or v == "" then
                    if getKbdValue(path) ~= nil then unsetKbdValue(r, k, ch.hint) end
                else
                    setKbdValue(path, tostring(v))
                end
                disableLiveTextOfKey(r, k)
            end, false)
        -- 下标提示的样式项
        local subFields = { "text_color", "text_size", "font", "show", "gravity", "offset_x", "offset_y" }
        for _, f in ipairs(subFields) do
            local cur = effectiveStyleValue(stNameNow, "hint", f)
            local path = own .. ".hint." .. f
            local kind = "text"
            if looksLikeColor(fieldCN(f), cur) then kind = "color"
            elseif type(cur) == "boolean" then kind = "bool"
            elseif type(cur) == "number" then kind = "number" end
            addItem(gSub, "下标·" .. fieldCN(f), kind, cur,
                function(v) if v == nil then unsetStyleValue(path) else setValue(path, v) end end, true)
        end
    end

    -- ③~⑧ 样式项：合并三个通道的清单（覆盖所有样式字段 + 主题里真实存在的额外字段），
    --     按名称前缀分类；写入目标一律是本键专属表 own.<字段>。
    local styleGroups = {}
    local function sg(name)
        if not styleGroups[name] then styleGroups[name] = newGroup(name) end
        return styleGroups[name]
    end
    local seenPath = {}
    for _, cid in ipairs({ "click", "long_click", "swipe_up" }) do
        for _, it in ipairs(channelStyleItems(stNameNow, cid)) do
            if not seenPath[it.path] then
                seenPath[it.path] = true
                local nm = it.name or ""
                local gn
                if nm:find("按下(长按)", 1, true) or nm:find("长按", 1, true) then
                    gn = "长按样式"
                elseif nm:find("按下(提示)", 1, true) or nm:find("提示", 1, true) then
                    gn = "提示样式"
                elseif nm:find("按下", 1, true) then
                    gn = "按下样式"
                elseif nm:find("留白", 1, true) or nm:find("内边距", 1, true) then
                    gn = "边距内距"
                elseif nm:find("常规", 1, true) then
                    gn = "常规样式"
                else
                    gn = "其他样式"
                end
                local rel = it.path:sub(#stNameNow + 1)  -- 以 "." 开头
                local ownPath = own .. rel
                local kind = "text"
                if looksLikeColor(it.name, it.cur) then kind = "color"
                elseif type(it.cur) == "boolean" then kind = "bool"
                elseif type(it.cur) == "number" then kind = "number" end
                local shortName = it.name:match("·([^·]+)$") or it.name
                addItem(sg(gn), shortName, kind, it.cur,
                    function(v)
                        if v == nil then unsetStyleValue(ownPath) else setValue(ownPath, v) end
                    end, true)
            end
        end
    end

    -- 整键通用属性（label 已归入 click 通道的"显示文字"，此处不再重复）
    local gCommon = newGroup("整键属性")
    for _, fd in ipairs({ { "width", "键宽(%)" }, { "ascii", "ASCII覆盖" } }) do
        local field, name = fd[1], fd[2]
        local cur = getKbdValue(base .. "." .. field)
        local init = (type(cur) == "string" and cur ~= "" and cur) or (cur ~= nil and tostring(cur) or nil)
        addItem(gCommon, name, "text", init,
            function(v)
                local path = base .. "." .. field
                if v == nil or v == "" then
                    if getKbdValue(path) ~= nil then unsetKbdValue(r, k, field) end
                else
                    setKbdValue(path, tostring(v))
                end
            end, false)
    end

    -- 位置与增删（动作组，不走 commit）
    newGroup("位置增删", true)

    -- ============ 分类按钮 + 内容区 ============
    local catBtns = {}
    local contentBox = LinearLayout(activity)
    contentBox.setOrientation(LinearLayout.VERTICAL)

    -- 名称与当前值分两段染不同色：名称=中性灰，当前值=强调蓝，一眼区分。
    -- 颜色项不再整块刷背景（那样会与其它按钮外观不一致），而是在值前面放一个小色块
    -- "■" 染成实际颜色，按钮本身保持和其它按钮一样的默认外观。
    local function paintItemBtn(btn, it)
        local name = it.name or ""
        local val = valText(it.v, it.kind) or ""
        local isColor = (it.kind == "color" and type(it.v) == "number")
        -- 色块前缀只占一个字符（■ 是 BMP，UTF-16 1 单元），放在值段最前面
        local swatch = isColor and "■ " or ""
        local text = name .. "\n  " .. swatch .. val
        -- Java String.length()/Spannable 下标都是 UTF-16 code unit 数，而 Lua 的 # 是字节数、
        -- 码点数又和 UTF-16 单元数不同：emoji(辅助平面) 1 个码点=2 个 UTF-16 单元(代理对)。
        -- 各段起点用「总 UTF16 长 - 后缀 UTF16 长」从末尾反推；若用码点数会让 span 起点
        -- 切进 emoji 的代理对中间 → 乱码。这里逐码点累加其 UTF-16 单元数。
        local function utf16units(s)
            local n, i = 0, 1
            while i <= #s do
                local c = s:byte(i)
                local cp
                if c < 0x80 then cp = c; i = i + 1
                elseif c < 0xE0 then cp = (c - 0xC0) * 0x40 + (s:byte(i + 1) - 0x80); i = i + 2
                elseif c < 0xF0 then cp = (c - 0xE0) * 0x1000 + (s:byte(i + 1) - 0x80) * 0x40 + (s:byte(i + 2) - 0x80); i = i + 3
                else cp = (c - 0xF0) * 0x40000 + (s:byte(i + 1) - 0x80) * 0x1000 + (s:byte(i + 2) - 0x80) * 0x40 + (s:byte(i + 3) - 0x80); i = i + 4 end
                n = n + (cp >= 0x10000 and 2 or 1)
            end
            return n
        end
        -- 名称/色块/值 三段起点（从末尾反推，emoji 安全）
        local spanned = false
        if _SpannableString and _Spannable and _FgSpan then
            pcall(function()
                local ss = _SpannableString(text)
                local total = ss.length()
                local valStart = math.max(0, total - utf16units(val))
                local swStart = math.max(0, valStart - utf16units(swatch))
                if total > 0 then
                    -- 名称段（含换行缩进）：中性灰
                    ss.setSpan(_FgSpan(0xFF8B949E), 0, swStart, _Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    -- 色块段：染成实际颜色值
                    if isColor and valStart > swStart then
                        ss.setSpan(_FgSpan(it.v), swStart, valStart, _Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    end
                    -- 值段：强调蓝（颜色项也一样，颜色已由色块表达）
                    if total > valStart then
                        ss.setSpan(_FgSpan(0xFF58A6FF), valStart, total, _Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    end
                end
                btn.setText(ss)
                spanned = true
            end)
        end
        if not spanned then btn.setText(text) end
    end

    local function editItem(it, btn)
        local function done(v) it.v = v; paintItemBtn(btn, it) end
        if it.kind == "bool" then
            done(not it.v)
        elseif it.kind == "color" then
            colorDialog("修改 " .. it.name, type(it.v) == "number" and it.v or nil,
                function(n) if n then done(n) end end)
        elseif it.kind == "event" then
            local opts = { "✎ 手动输入…" }
            local keyList = {}
            for key, _ in pairs(presetKeysCache or {}) do keyList[#keyList + 1] = key end
            table.sort(keyList)
            for _, key in ipairs(keyList) do
                local l = resolveEventLabel(key)
                opts[#opts + 1] = (l and l ~= "" and l ~= key) and (key .. "  " .. l) or key
            end
            listDialog("选择 " .. it.name, opts, function(sel)
                if sel == "✎ 手动输入…" then
                    inputDialog("事件字符串", "如 a / space / Return", it.v, function(s) done(s ~= "" and s or nil) end)
                else
                    done(sel:match("^([^%s]+)") or sel)
                end
            end, { filter = true, filterHint = "输入关键字筛选预置事件" })
        else
            local isNum = (it.kind == "number")
            inputDialog("修改 " .. it.name, isNum and "输入数字" or "留空=删除该项", it.v, function(s)
                if isNum then
                    local n = tonumber(s)
                    if n == nil then toast("请输入数字") return end
                    done(n)
                else
                    done(s ~= "" and s or nil)
                end
            end)
        end
    end

    local function showGroup(idx)
        local g = groups[idx]
        contentBox.removeAllViews()
        for ci, btn in ipairs(catBtns) do
            if ci == idx then btn.setTextColor(ch.color) else btn.setTextColor(0xFF8B949E) end
        end
        if g.isActions then
            local function rowBtns(defs)
                local row = LinearLayout(activity); row.setOrientation(LinearLayout.HORIZONTAL)
                for _, d in ipairs(defs) do
                    local b = Button(activity); b.setText(d[1]); b.setAllCaps(false); b.setTextSize(11)
                    b.setLayoutParams(LinearLayout.LayoutParams(0, dp(38), 1)); b.onClick = d[2]; row.addView(b)
                end
                contentBox.addView(row)
            end
            rowBtns({
                { "← 左移", function() if opSwap(r, k, k - 1) then dlg.dismiss(); renderPreview() end end },
                { "右移 →", function() if opSwap(r, k, k + 1) then dlg.dismiss(); renderPreview() end end },
                { "↑ 上移", function() if opMove(r, k, r - 1) then dlg.dismiss(); renderPreview() end end },
                { "↓ 下移", function() if opMove(r, k, r + 1) then dlg.dismiss(); renderPreview() end end },
            })
            rowBtns({
                { "左侧插键", function() dlg.dismiss(); insertKeyChoice(r, k) end },
                { "右侧插键", function() dlg.dismiss(); insertKeyChoice(r, k + 1) end },
                { "删除本键", function() dlg.dismiss(); if opDelete(r, k) then selKeyR, selKeyK = nil, nil; renderPreview() end end },
            })
        else
            if #g.items == 0 then
                local tv = TextView(activity); tv.setText("（本分类暂无可修改项）")
                tv.setTextColor(0xFF8B949E); tv.setTextSize(12)
                contentBox.addView(tv)
            end
            -- 二级项目按钮：每行 2 个，各占一半宽度（按钮文字两行：名称 + 当前值）
            local itemRow
            for ii, it in ipairs(g.items) do
                if (ii - 1) % 2 == 0 then
                    itemRow = LinearLayout(activity); itemRow.setOrientation(LinearLayout.HORIZONTAL)
                    contentBox.addView(itemRow, LinearLayout.LayoutParams(-1, dp(48)))
                end
                local b = Button(activity); b.setAllCaps(false); b.setTextSize(11)
                b.setLayoutParams(LinearLayout.LayoutParams(0, dp(48), 1))
                paintItemBtn(b, it)
                local captured = b
                b.onClick = function() editItem(it, captured) end
                itemRow.addView(b)
            end
        end
    end

    -- 统一动态编号：按 groups 实际顺序编号 ①②③…，click 多一个"下标提示"组也
    -- 不会出现子编号或跳号；动作组(位置增删)也纳入同一序列。
    local NUM_CN = { "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩", "⑪", "⑫" }
    for i, g in ipairs(groups) do
        g.name = (NUM_CN[i] or (i .. ".")) .. " " .. g.name
    end

    -- 分类按钮：每行 3 个
    local catRow
    for i, g in ipairs(groups) do
        if (i - 1) % 3 == 0 then
            catRow = LinearLayout(activity); catRow.setOrientation(LinearLayout.HORIZONTAL); lay.addView(catRow)
        end
        local b = Button(activity); b.setAllCaps(false); b.setTextSize(10); b.setText(g.name)
        b.setLayoutParams(LinearLayout.LayoutParams(0, dp(36), 1))
        b.onClick = function() showGroup(i) end
        catRow.addView(b); catBtns[#catBtns + 1] = b
    end
    local tip = TextView(activity); tip.setTextSize(10); tip.setTextColor(0xFF8B949E)
    tip.setText("点分类 → 点项目按钮改值 → 应用修改")
    lay.addView(tip)
    lay.addView(contentBox)

    dlg.setTitle(ch.name .. " · 第" .. r .. "行第" .. k .. "键")
    local sv = ScrollView(activity); sv.addView(lay); dlg.setView(sv)

    local function applyAll()
        local hasStyle = false
        for _, it in ipairs(allItems) do
            if it.isStyle and tostring(it.v) ~= tostring(it.cur) then hasStyle = true; break end
        end
        if hasStyle and not ensureOwnStyle(r, k) then toast("专属样式创建失败") return end
        local n = 0
        for _, it in ipairs(allItems) do
            if tostring(it.v) ~= tostring(it.cur) then it.commit(it.v); n = n + 1 end
        end
        return n
    end
    dlg.setButton("应用修改", function()
        applyAll()
        selKeyR, selKeyK = nil, nil
        dlg.dismiss()
        renderPreview()
        toast("已应用 " .. ch.name .. " 的修改")
    end)
    dlg.setButton2("取消", function() dlg.dismiss() end)
    dlg.setButton3("整键总览", function() applyAll(); selKeyR, selKeyK = nil, nil; dlg.dismiss(); keyEditDialog(r, k) end)
    showGroup(1)
    dlg.show()
end

-- 整键总览：列出 6 个通道各自的当前 event，点一个进入通道编辑器（兼容旧的“点键”入口）
keyEditDialog = function(r, k)
    local base = "rows." .. r .. ".keys." .. k
    local kdef = kbdEnv and kbdEnv.rows and kbdEnv.rows[r] and kbdEnv.rows[r].keys[k]
    if type(kdef) ~= "table" then return end
    local items, ids = {}, {}
    for _, c in ipairs(CHANNELS) do
        table.insert(items, c.name .. "（字段 " .. c.ev .. "）　当前：" .. channelEventSummary(r, k, c))
        table.insert(ids, c.id)
    end
    local tail = "── 键面文字 / 键宽 / 样式（按点击通道编辑）──"
    table.insert(items, tail)
    listDialog("第" .. r .. "行第" .. k .. "键 · 选择要编辑的事件通道", items, function(sel)
        for i, it in ipairs(items) do
            if it == sel and ids[i] then channelEditDialog(r, k, ids[i]); return end
        end
        channelEditDialog(r, k, "click")
    end)
end

-- 插键类型选择
function insertKeyChoice(tr, pos)
    listDialog("插入按键类型", {
        "普通键（click + label + width）",
        "空白间隔键（仅 width = 5）",
    }, function(choice)
        local spacer = choice:find("空白") ~= nil
        if opInsert(tr, pos, spacer) then
            renderPreview()
            toast(spacer and "已插入空白间隔键" or "已插入新键（点击它编辑）")
        end
    end)
end

-- 键盘设置：尺寸 + 三块区域背景（各自圆角/描边）+ 工具栏与按键区间距。
-- 字段与真机对应（Style.getDrawable / RowKeyboardView / ToolbarView）：
--   键盘整体背景 = background            （RootInputView.mRoot，最底层，候选区/工具栏/按键区都叠在它上面）
--   按键区域背景 = keyboard.background   （RowKeyboardView / FlexboxKeyboardView 的底）
--   工具栏区背景 = toolbar.background    （ToolbarView.root）
--   圆角/描边    = 同一前缀的 corner_radius / stroke_width / stroke_color
--   工具栏间距   = toolbar.elevation（真机 ToolbarView 就按它让出底部空间，缺省 2dp）
-- 所有项只在「与打开面板时不同」才写入，没动的字段一个都不碰。
-- 键盘调整：分类-项目按钮界面，与按键编辑面板同款
function kbdSettingsDialog()
    if not kbdEnv then toast("未加载键盘") return end
    if not styleEnv then toast("样式还没加载好") return end

    local function join(prefix, field)
        return prefix == "" and field or (prefix .. "." .. field)
    end
    local groups, allItems = {}, {}
    local function grp(nm)
        groups[#groups + 1] = { name = nm, items = {} }
        return groups[#groups]
    end

    -- 一块区域：背景(颜色/图片二选一) + 圆角 + 描边
    local function addArea(g, prefix)
        local bgPath = join(prefix, "background")
        local cur = getValue(bgPath)
        local it = { name = "背景(颜色/图片)", kind = "color", cur = cur, v = cur }
        it.onEdit = function(item, done) backgroundEditDialog("修改 " .. item.name, item.v, done) end
        it.commit = function(v) if v == nil then unsetStyleValue(bgPath) else setValue(bgPath, v) end end
        g.items[#g.items + 1] = it; allItems[#allItems + 1] = it
        for _, fd in ipairs({
            { "corner_radius", "圆角(dp)", "number" },
            { "stroke_width", "描边宽度(dp)", "number" },
            { "stroke_color", "描边颜色", "color" },
        }) do
            local path = join(prefix, fd[1])
            local c = getValue(path)
            local item = { name = fd[2], kind = fd[3], cur = c, v = c }
            item.commit = function(v) if v == nil then unsetStyleValue(path) else setValue(path, v) end end
            g.items[#g.items + 1] = item; allItems[#allItems + 1] = item
        end
    end

    addArea(grp("键盘整体背景（最底层）"), "")
    addArea(grp("按键区域背景"), "keyboard")
    addArea(grp("工具栏区背景"), "toolbar")

    -- 间距与尺寸
    local gMisc = grp("间距与尺寸")
    do
        local path = "toolbar.elevation"
        local c = getValue(path)
        local it = { name = "与按键区间距(dp)", kind = "number", cur = c, v = c }
        it.commit = function(v) if v == nil then unsetStyleValue(path) else setValue(path, v) end end
        gMisc.items[#gMisc.items + 1] = it; allItems[#allItems + 1] = it
    end
    for _, fd in ipairs({ { "key_width", "默认键宽(%)" }, { "key_height", "键高(行高%)" } }) do
        local c = tonumber(getKbdValue(fd[1]) or kbdEnv[fd[1]])
        local it = { name = fd[2], kind = "number", cur = c, v = c }
        it.commit = function(v) setKbdTop(fd[1], v) end
        gMisc.items[#gMisc.items + 1] = it; allItems[#allItems + 1] = it
    end

    -- 候选栏入口（动作项）：打开子面板前先关掉本面板（避免叠窗）
    local gMore = grp("候选栏")
    local myDlg
    gMore.items[#gMore.items + 1] = {
        name = "打开候选栏设置 →", isAction = true,
        onClick = function()
            pcall(function() if myDlg then myDlg.dismiss() end end)
            candidateSettingsDialog()
        end,
    }

    myDlg = categoryPanelDialog({
        title = "键盘调整 · 高度 / 背景 / 圆角 / 间距",
        accent = 0xFF3FB950,
        headText = "三块区域背景各自独立；改动的项才写入，未动的字段不碰。候选栏入口见最后一类。",
        groups = groups,
        onApply = function()
            local n = 0
            for _, it in ipairs(allItems) do
                if not catSame(it.v, it.cur) then it.commit(it.v); n = n + 1 end
            end
            return n
        end,
    })
end

-- 工具栏整体样式设置：与真机 ToolbarView 对齐的字段
--   toolbar.background（整体背景）/ toolbar.elevation（与键区间距、阴影）
--   toolbar.key.*（按键 KeyStyle：字号/字色/背景/圆角，走「样式编辑-工具栏按键」更全）
--   toolbar.hide.text / toolbar.hide.background / toolbar.hide.text_color / toolbar.hide.text_size
--   toolbar.schema_switches（方案切换键开关）
function toolbarSettingsDialog()
    if not styleEnv or type(styleEnv.toolbar) ~= "table" then
        toast("当前主题没有工具栏样式") return
    end
    local lay = LinearLayout(activity)
    lay.setOrientation(LinearLayout.VERTICAL)
    lay.setPadding(dp(14), dp(6), dp(14), dp(6))
    local function lab(t)
        local tv = TextView(activity)
        tv.setText(t); tv.setTextSize(11); tv.setTextColor(0xFF8B949E)
        tv.setPadding(0, dp(8), 0, dp(2)); lay.addView(tv)
    end
    local function numEdit(v, hint)
        local et = EditText(activity)
        et.setSingleLine(true); et.setInputType(2)
        et.setText(v ~= nil and tostring(v) or ""); et.setHint(hint or "")
        lay.addView(et, LinearLayout.LayoutParams(-1, -2)); return et
    end
    local function colorBtn(path, label)
        local st = { value = tonumber(getValue(path)) }
        local b = Button(activity); b.setAllCaps(false); b.setTextSize(11)
        local function paint()
            local n = st.value
            if type(n) == "number" then
                b.setText(label .. "  " .. string.format("#%08X", n))
                pcall(function() b.setBackgroundColor(n) end)
                local lum = ((math.floor(n / 0x10000) % 0x100) * 299
                    + (math.floor(n / 0x100) % 0x100) * 587 + (n % 0x100) * 114) / 1000
                pcall(function() b.setTextColor(lum > 128 and 0xFF000000 or 0xFFFFFFFF) end)
            else
                b.setText(label .. "  未设置（跟随继承）")
                pcall(function() b.setBackgroundColor(0xFF30363D) end)
                pcall(function() b.setTextColor(0xFF8B949E) end)
            end
        end
        paint()
        b.onClick = function()
            colorDialog("选择" .. label, type(st.value) == "number" and st.value or nil,
                function(v) if v then st.value = v; paint() end end)
        end
        lay.addView(b, LinearLayout.LayoutParams(-1, -2)); return st
    end

    lab("工具栏背景色 toolbar.background（图片请在样式编辑里填）")
    local bgColor = colorBtn("toolbar.background", "工具栏背景色")
    lab("与键区间距 toolbar.elevation（dp，缺省 2）")
    local elevationEt = numEdit(tonumber(getValue("toolbar.elevation")), "例如 2")

    lab("── 工具栏按键 toolbar.key ──")
    lab("按键字号 toolbar.key.text_size")
    local kTsEt = numEdit(tonumber(getValue("toolbar.key.text_size")), "留空=跟随 key.text_size")
    lab("按键圆角 toolbar.key.corner_radius")
    local kCrEt = numEdit(tonumber(getValue("toolbar.key.corner_radius")), "例如 6")
    local kColor = colorBtn("toolbar.key.text_color", "按键文字色")
    local kBgColor = colorBtn("toolbar.key.background", "按键背景色")

    lab("── 右侧隐藏键 toolbar.hide ──")
    lab("隐藏键文字 toolbar.hide.text（默认 ▽）")
    local hideTextEt = EditText(activity)
    hideTextEt.setSingleLine(true)
    hideTextEt.setText(getValue("toolbar.hide.text") ~= nil and tostring(getValue("toolbar.hide.text")) or "")
    hideTextEt.setHint("▽")
    lay.addView(hideTextEt, LinearLayout.LayoutParams(-1, -2))
    lab("隐藏键字号 toolbar.hide.text_size")
    local hTsEt = numEdit(tonumber(getValue("toolbar.hide.text_size")), "留空=跟随按键")
    local hColor = colorBtn("toolbar.hide.text_color", "隐藏键文字色")
    local hBgColor = colorBtn("toolbar.hide.background", "隐藏键背景色")

    local sv = ScrollView(activity); sv.addView(lay)
    local dlg = LuaDialog(activity)
    dlg.setTitle("工具栏样式设置")
    dlg.setView(sv)
    dlg.setButton("应用", function()
        local n = 0
        local function applyNum(path, et)
            local init = tonumber(getValue(path))
            local v = tonumber(tostring(et.getText()):match("[-%d%.]+") or "")
            if v and v ~= init then setValue(path, v); n = n + 1 end
        end
        local function applyColor(path, st)
            local v = st.value
            if v ~= tonumber(getValue(path)) then
                if type(v) == "number" then setValue(path, v) else unsetStyleValue(path) end
                n = n + 1
            end
        end
        local function applyText(path, et)
            local s = tostring(et.getText())
            local init = getValue(path)
            if s ~= tostring(init or "") then
                if s == "" then unsetStyleValue(path) else setValue(path, s) end
                n = n + 1
            end
        end
        applyColor("toolbar.background", bgColor)
        applyNum("toolbar.elevation", elevationEt)
        applyNum("toolbar.key.text_size", kTsEt)
        applyNum("toolbar.key.corner_radius", kCrEt)
        applyColor("toolbar.key.text_color", kColor)
        applyColor("toolbar.key.background", kBgColor)
        applyText("toolbar.hide.text", hideTextEt)
        applyNum("toolbar.hide.text_size", hTsEt)
        applyColor("toolbar.hide.text_color", hColor)
        applyColor("toolbar.hide.background", hBgColor)
        dlg.dismiss(); renderPreview()
        toast(n > 0 and ("已应用 " .. n .. " 项工具栏样式（保存主题时写入）") or "没有修改任何项")
    end)
    dlg.setButton("按键列表", function()
        dlg.dismiss()
        if tbKeysDialog then tbKeysDialog() end
    end)
    dlg.setButton2("关闭", function() dlg.dismiss() end)
    dlg.show()
end

-- 工具栏按键点击入口：选择编辑按键列表 / 工具栏样式
function toolbarEntryDialog()
    listDialog("工具栏设置", {
        "工具栏样式（背景/间距/按键/隐藏键）",
        "按键列表 keys（增删/事件）",
        "批量样式编辑（含工具栏/候选栏范围）",
    }, function(sel)
        if sel:find("样式（背景") then toolbarSettingsDialog()
        elseif sel:find("按键列表") then if tbKeysDialog then tbKeysDialog() end
        else styleEditorDialog() end
    end)
end

-- 工具栏 keys 原文编辑
tbKeysDialog = function()
    if not styleEnv or type(styleEnv.toolbar) ~= "table" then return end
    local ks = styleEnv.toolbar.keys
    local parts = {}
    if type(ks) == "table" then
        for _, o in ipairs(ks) do
            if type(o) == "string" then table.insert(parts, luaQuote(o))
            elseif type(o) == "table" then table.insert(parts, serializeValue(o)) end
        end
    end
    local raw = table.concat(parts, ",\n  ")
    local lay = LinearLayout(activity)
    lay.setOrientation(LinearLayout.VERTICAL)
    lay.setPadding(dp(12), dp(8), dp(12), dp(4))
    local tv = TextView(activity)
    tv.setText("逗号分隔；字符串=preset键名，表={label=\"菜单\", send=\"...\"}\n留空=清空工具栏按键")
    tv.setTextSize(11); lay.addView(tv)
    local et = EditText(activity)
    et.setGravity(Gravity.TOP)
    et.setMinLines(6)
    et.setText(raw)
    et.setLayoutParams(LinearLayout.LayoutParams(-1, dp(220)))
    lay.addView(et)
    local dlg = LuaDialog(activity)
    dlg.setTitle("工具栏按键列表 keys")
    dlg.setView(lay)
    dlg.setButton("写入", function()
        local s = tostring(et.getText())
        local ok, tbl = pcall(function() return load("return {" .. s .. "}")() end)
        if ok and type(tbl) == "table" then
            setValue("toolbar.keys", tbl)
            dlg.dismiss(); renderPreview()
            toast("已更新工具栏（保存主题时写入）")
        else
            toast("Lua 语法错误：" .. tostring(tbl))
        end
    end)
    dlg.setButton2("取消", function() dlg.dismiss() end)
    dlg.show()
end

-- ========== 保存引擎：覆盖原主题 / 生成新主题文件夹 ==========
local BLOCK_BEGIN = "-- >>>>> Theme Studio 生成，请勿手改 >>>>>"
local BLOCK_END   = "-- <<<<< Theme Studio 生成结束 <<<<<"

-- ===== 原子写文件：先写 .tsnew 临时文件，再 rename 覆盖 =====
-- 覆盖原主题是直接改写真机主题文件。若 writeFile 写到一半中断，文件会被截断成
-- 半截 Lua，整个主题直接废掉。rename(2) 是原子的：最坏只留下一个 .tsnew，原文件完好。
local JWFile
pcall(function() JWFile = luajava.bindClass("java.io.File") end)
function atomicWriteFile(path, s)
    if not JWFile then return writeFile(path, s) end
    local tmp = path .. ".tsnew"
    if not writeFile(tmp, s) then return writeFile(path, s) end
    local moved = false
    pcall(function() moved = JWFile(tmp):renameTo(JWFile(path)) end)
    if not moved then
        -- 少数实现下"目标已存在"会让 rename 失败：先把原件挪成 .tsbak，再改名，成功后再删备份
        local bak = path .. ".tsbak"
        local backed = false
        pcall(function() backed = JWFile(path):renameTo(JWFile(bak)) end)
        pcall(function() moved = JWFile(tmp):renameTo(JWFile(path)) end)
        if moved then
            pcall(function() JWFile(bak):delete() end)
        else
            if backed then pcall(function() JWFile(bak):renameTo(JWFile(path)) end) end
            pcall(function() JWFile(tmp):delete() end)
            return writeFile(path, s)
        end
    end
    return true
end

-- 把一条键盘操作转成可执行的 Lua 语句
function opToLua(op)
    local R = op.r
    if op.kind == "swap" then
        return string.format("rows[%d].keys[%d], rows[%d].keys[%d] = rows[%d].keys[%d], rows[%d].keys[%d]",
            R, op.k, R, op.k2, R, op.k2, R, op.k)
    elseif op.kind == "move" then
        return string.format("table.insert(rows[%d].keys, %d, table.remove(rows[%d].keys, %d))",
            op.r2, op.pos, R, op.k)
    elseif op.kind == "insert" then
        return string.format("table.insert(rows[%d].keys, %d, %s)", R, op.pos, serializeValue(op.key))
    elseif op.kind == "delete" then
        return string.format("table.remove(rows[%d].keys, %d)", R, op.k)
    elseif op.kind == "top" then
        return op.field .. " = " .. serializeValue(op.value)
    end
    return nil
end

-- 向文件追加生成块（保留原内容）
-- 【改为"追加"而非"先删旧块再写"】覆盖原主题需要连续保存：上一次保存的块已经落盘，
-- 若这次先 strip 掉它再只写本次增量，上一次的改动就全丢了（块是增量补丁，不是全量快照）。
-- 追加多个块时后者覆盖前者，语义正好是"在已保存结果上继续改"，天然幂等且不丢历史改动。
function appendBlockTo(path, lines)
    if #lines == 0 then return true end
    local src = readFile(path) or ""
    if not src:find("\n$") then src = src .. "\n" end
    local out = { src, "\n", BLOCK_BEGIN, "  -- ", os.date("%Y-%m-%d %H:%M:%S"), "\n" }
    for _, ln in ipairs(lines) do table.insert(out, ln); table.insert(out, "\n") end
    table.insert(out, BLOCK_END)
    table.insert(out, "\n")
    return atomicWriteFile(path, table.concat(out))
end

-- ================== 保存主题：覆盖原主题 / 生成新主题 ==================
-- 生成新主题要复制整个目录（几百个文件）。这段复制必须分批让出 UI 线程：
-- 一次性同步复制会让输入法进程 ANR 被系统杀掉（工具与输入法同进程，一起闪退）。
local uiStatusTv = nil          -- 保存状态行：只对已有 View 做 setText，绝不新建窗口
local exporting = false
local exportCtx = nil
local exportKeep = {}           -- 强引用异步任务与横幅，防 Lua GC 回收

local SysClock
pcall(function() SysClock = luajava.bindClass("android.os.SystemClock") end)

-- 更快的整文件复制通道（API 26+）：Files.copy 内部走 native 复制，
-- 一次调用搞定，小文件多的时候能省掉大量 JNI 往返（826 文件的场景差别很明显）。
local JFiles, JPaths, JFile
pcall(function()
    local v = luajava.bindClass("android.os.Build$VERSION")
    local sdk = tonumber(v.SDK_INT) or 0
    if sdk >= 26 then
        JFiles = luajava.bindClass("java.nio.file.Files")
        JPaths = luajava.bindClass("java.nio.file.Paths")
    end
end)
pcall(function() JFile = luajava.bindClass("java.io.File") end)

local function nowMs()
    if SysClock then
        local ok, v = pcall(function() return SysClock.uptimeMillis() end)
        if ok and v then return tonumber(v) end
    end
    return math.floor(os.clock() * 1000)
end
local _EXPORT_LOG = "/sdcard/Download/主题工作室_导出.txt"
local function xexp(s)
    pcall(function()
        local f = io.open(_EXPORT_LOG, "a")
        if f then
            f:write(os.date("%m-%d %H:%M:%S") .. " " .. tostring(s) .. "\n")
            f:close()
        end
    end)
end
local function exlog(s)
    xexp(tostring(s))
end

-- 单文件复制：Files.copy 一次 JNI 完成整文件（API 26+），失败则回退 io 分块。
function copyFileFast(src, dst)
    if JFiles and JPaths then
        if pcall(function() JFiles.copy(JPaths.get(src), JPaths.get(dst)) end) then return true end
        -- 目标已存在等情况：删掉再试一次（新主题目录正常不会有同名文件）
        if pcall(function()
            if JFile then JFile(dst):delete() end
            JFiles.copy(JPaths.get(src), JPaths.get(dst))
        end) then return true end
    end
    return copyFileBin(src, dst)
end

-- 只遍历目录、建目标子目录、收集文件清单（毫秒级，不做复制）
local function buildCopyPlan(src, dst, files)
    mkdirs(dst)
    for _, name in ipairs(listDir(src)) do
        local s, d = src .. "/" .. name, dst .. "/" .. name
        if isDir(s) then buildCopyPlan(s, d, files)
        else files[#files + 1] = { s, d } end
    end
end

-- 把当前累积的改动编译成"要写进文件的语句"（样式行 + 键盘行 + 真实键盘文件名）
-- 覆盖原主题与生成新主题共用这一段，保证两种保存方式写出的内容完全一致。
function buildWriteLines()
    -- 键盘真实文件名校正：currentKbdFile 可能只是显示名（"万象"），磁盘上并无此文件，
    -- 或者是历史导出留下的空壳。name= 可能重复，用当前布局指纹挑，挑不出再取第一个候选。
    local kbdFile = currentKbdFile
    if kbdFile and not kbdFileHasData(kbdFile) then
        local cs = findKbdCandidates(kbdFile)
        local realFile = (#cs > 0) and (pickKbdByShape(cs, kbdEnv) or cs[1]) or nil
        if realFile then
            exlog("CORRECT kbdFile " .. tostring(kbdFile) .. " -> " .. tostring(realFile))
            kbdFile = realFile
        end
    end

    -- 2a) 单键专属样式表：磁盘上若还没有这些表，必须先整表定义
    local ownDecl = {}
    for name in pairs(newStyleTables) do
        if type(styleEnv) == "table" and type(styleEnv[name]) == "table" then
            table.insert(ownDecl, luaPath(name) .. " = " .. serializeValue(styleEnv[name]))
        end
    end
    table.sort(ownDecl)

    -- 2b) 普通样式字段改动；专属表字段已含在整表定义里，跳过避免重复。
    -- 删除（UNSET）单独收集，统一排在所有赋值之后，避免被后面同路径赋值重建。
    local plain, plainNil = {}, {}
    for path, v in pairs(styleEdits) do
        local isOwn = false
        for name in pairs(newStyleTables) do
            if path == name or path:find(name .. ".", 1, true) == 1 then isOwn = true; break end
        end
        if not isOwn then
            if v == STYLE_UNSET then
                table.insert(plainNil, luaPath(path) .. " = nil")
            else
                table.insert(plain, luaPath(path) .. " = " .. serializeValue(v))
            end
        end
    end
    table.sort(plain)
    table.sort(plainNil)

    -- 【顺序】整表定义必须排在任何对它的字段赋值之前，否则会 index nil 直接报错。
    -- 所以先放 ownDecl，再放排序后的普通字段，最后才整体使用（不再统一 sort）。
    local styleLines = {}
    for _, ln in ipairs(ownDecl) do table.insert(styleLines, ln) end
    for _, ln in ipairs(plain) do table.insert(styleLines, ln) end
    for _, ln in ipairs(plainNil) do table.insert(styleLines, ln) end

    -- 3) 键盘写回语句：字段 + 结构操作 + 删除（删除放最后，避免被后续赋值重建）
    local kbdLines = {}
    for path, v in pairs(kbdEdits) do
        if v ~= "\255UNSET\255" then
            table.insert(kbdLines, luaPath(path) .. " = " .. serializeValue(v))
        end
    end
    for _, op in ipairs(kbdOps) do
        local ln = opToLua(op)
        if ln then table.insert(kbdLines, ln) end
    end
    for path, v in pairs(kbdEdits) do
        if v == "\255UNSET\255" then table.insert(kbdLines, luaPath(path) .. " = nil") end
    end
    return styleLines, kbdLines, kbdFile
end

-- 第一步（快）：校验 + 生成复制清单 + 预先算好要写回的语句
-- inPlace = true  → 覆盖原主题：不复制、不改名，直接写回当前主题文件
-- inPlace = false → 生成新主题：整目录复制到新文件夹，再写回并改名
function exportPrepare(newName, inPlace)
    local function ecnt(t)
        if type(t) ~= "table" then return 0 end
        local n = 0; for _ in pairs(t) do n = n + 1 end; return n
    end
    exlog("SAVE BEGIN name=" .. tostring(newName) .. " inPlace=" .. tostring(inPlace)
        .. "; theme=" .. tostring(currentTheme) .. " variant=" .. tostring(currentVariant)
        .. " kbd=" .. tostring(currentKbdFile) .. "; dirty=" .. tostring(dirtyCount)
        .. " style=" .. ecnt(styleEdits) .. "+" .. ecnt(newStyleTables)
        .. " kbd=" .. ecnt(kbdEdits) .. "+" .. ecnt(kbdOps))
    if not currentTheme or not themeDir then return nil, "请先选择主题" end

    local dst, files = nil, {}
    inPlace = inPlace and true or false
    if inPlace then
        dst = themeDir
        newName = currentTheme      -- 覆盖保存不改名，名字就是当前主题
    else
        newName = tostring(newName):match("^%s*(.-)%s*$") or ""
        if newName == "" then return nil, "主题名不能为空" end
        if newName:find("[/\\]") then return nil, "主题名不能含 / 或 \\" end
        local rootDir = getThemesRoot()
        if not rootDir then return nil, "无法获取主题目录" end
        dst = rootDir .. "/" .. newName
        if isDir(dst) then return nil, "已存在同名主题：" .. newName end
        -- 复制清单
        local okPlan, planErr = pcall(buildCopyPlan, themeDir, dst, files)
        if not okPlan then return nil, "扫描主题目录失败：" .. tostring(planErr) end
    end
    if not inPlace then newName = (tostring(newName):match("^%s*(.-)%s*$")) end

    local styleLines, kbdLines, kbdFile = buildWriteLines()
    exlog("prepared styleLines=" .. #styleLines .. " kbdLines=" .. #kbdLines
        .. " kbdFile=" .. tostring(kbdFile))
    if #styleLines == 0 and #kbdLines == 0 then
        return nil, "没有可写入的改动"
    end
    if #kbdLines > 0 and not kbdFile then
        return nil, "找不到当前键盘文件，无法写入键盘改动"
    end

    return {
        name = newName, dst = dst, files = files, inPlace = inPlace,
        styleLines = styleLines, kbdLines = kbdLines,
        kbdFile = kbdFile, variant = currentVariant,
        idx = 1, t0 = nowMs(),
    }
end
-- 覆盖保存前的安全网：把即将改写的文件备份成 .ts.bak（覆盖上一次备份）。
-- .ts.bak 不是 .lua，不会被输入法当作脚本加载，也不会被主题列表扫到。
function backupFileQuiet(path)
    if not fileExists(path) then return end
    pcall(function() copyFileFast(path, path .. ".ts.bak") end)
end

-- 第三步：把改动写进目标（覆盖原主题时就是原文件；生成新主题时是副本）
function exportCommit(ctx)
    local dst = ctx.dst

    -- 4) 改名只在"生成新主题"时做。覆盖原主题绝不能改名，否则设置里的主题名会变。
    -- 【只改正文，绝不碰生成块】先把正文与末尾生成块切开，只对正文改 name，
    -- （上一次保存的改动）顺手删掉，导致覆盖保存后历史改动全部丢失。
    if not ctx.inPlace then
        local mainPath = dst .. "/main.lua"
        local src = readFile(mainPath) or ""
        local bpos = src:find(BLOCK_BEGIN, 1, true)
        local head = bpos and src:sub(1, bpos - 1) or src
        local tailPart = bpos and src:sub(bpos) or ""
        -- 只在去注释后的真代码里定位 name=（注释里的示例 name 不能当真、更不能改）。
        -- stripLuaComments 保持长度与行号，故 code 中的位置就是原文 head 的同一字节位。
        local replaced = false
        local code = stripLuaComments(head)
        local ns = code:find('%f[%w]name%s*=%s*["\']')
        if ns then
            local qs = head:find('["\']', ns)
            local _, qe = qs and head:find('["\'][^\n]-["\']', qs)
            if qs and qe then
                head = head:sub(1, qs - 1) .. luaQuote(ctx.name) .. head:sub(qe + 1)
                replaced = true
            end
        end
        if not replaced then head = head .. "\nname = " .. luaQuote(ctx.name) .. "\n" end
        atomicWriteFile(mainPath, head .. tailPart)
    end

    if #ctx.styleLines > 0 then
        local target
        if ctx.variant == "（主题 main.lua 内嵌样式）" then
            target = dst .. "/main.lua"
        elseif ctx.variant then
            target = dst .. "/styles/" .. ctx.variant .. "/main.lua"
        end
        if target then
            if ctx.inPlace then backupFileQuiet(target) end
            appendBlockTo(target, ctx.styleLines)
        end
    end

    if #ctx.kbdLines > 0 and ctx.kbdFile then
        local kbdTarget = dst .. "/keyboards/" .. ctx.kbdFile
        if ctx.inPlace then backupFileQuiet(kbdTarget) end
        appendBlockTo(kbdTarget, ctx.kbdLines)
    end

    exlog("commit done style=" .. tostring(#ctx.styleLines) .. " kbd=" .. tostring(#ctx.kbdLines))
    ctx.writes = #ctx.styleLines + #ctx.kbdLines

    -- 回读验证：确认生成块确实写进了目标文件
    pcall(function()
        local function tailHas(path, marker)
            local s = readFile(path) or ""
            return tostring(s:find(marker, 1, true) ~= nil) .. " size=" .. tostring(#s)
        end
        if ctx.variant == "（主题 main.lua 内嵌样式）" then
            exlog("VERIFY main " .. tailHas(dst .. "/main.lua", BLOCK_BEGIN))
        elseif ctx.variant then
            exlog("VERIFY style " .. tailHas(dst .. "/styles/" .. ctx.variant .. "/main.lua", BLOCK_BEGIN))
        end
        if ctx.kbdFile then exlog("VERIFY kbd " .. tailHas(dst .. "/keyboards/" .. ctx.kbdFile, BLOCK_BEGIN)) end
    end)
end

-- 覆盖保存成功后：本次改动已经落盘，清空增量记录，避免下次重复写同一批语句。
-- 注意保留 styleEnv / kbdEnv（内存里的当前样式与键盘模型），界面预览不受影响。
function resetEditsAfterSave()
    styleEdits = {}
    kbdEdits = {}
    kbdOps = {}
    newStyleTables = {}
    dirtyCount = 0
    pcall(refreshDirty)
end
-- 【提示只改已有 View】不新建 Dialog、不 addView、不 toast。
-- 这样"完成提示"这条路径上不存在任何窗口操作，可把窗口类崩溃彻底排除在外。
-- 工具界面是否已销毁（退出中）：异步任务据此决定是否还能碰 View
function activityDead()
    local dead = false
    pcall(function() if activity.isFinishing() then dead = true end end)
    pcall(function() if activity.isDestroyed() then dead = true end end)
    return dead
end

local function setExportStatus(s)
    local tv = uiStatusTv
    if not tv or activityDead() then return end
    pcall(function() tv.setVisibility(0); tv.setText(s) end)
end

local function exportFinish(ok, msg, ctx)
    exporting = false
    exportCtx = nil
    exportKeep.batch = nil
    local ms = ctx and (nowMs() - (ctx.t0 or nowMs())) or 0
    local text
    if ok and ctx then
        exlog("FINISH ok ms=" .. tostring(ms) .. " files=" .. tostring(#ctx.files))
        if ctx.inPlace then
            text = "✓ 已保存到原主题：" .. tostring(ctx.name)
                .. "（" .. tostring(ctx.writes or 0) .. " 项改动 / " .. tostring(ms) .. " ms）\n"
                .. tostring(ctx.dst) .. "\n重启输入法或重新切换主题后生效。"
        else
            text = "✓ 新主题已生成：" .. tostring(ctx.name)
                .. "（" .. tostring(#ctx.files) .. " 文件 / " .. tostring(ms) .. " ms）\n"
                .. tostring(ctx.dst) .. "\n原主题未改动，请到 设置→主题 切换查看。"
        end
    else
        exlog("FINISH fail " .. tostring(msg))
        text = "✗ 保存失败：" .. tostring(msg)
    end
    -- 延后 400ms 再刷状态：让最后一批任务的处理栈先退出，再触发 setText → measure/layout。
    exportKeep.finishUi = function()
        setExportStatus(text)
    end
    local okPost = pcall(function() uiHandler.postDelayed(exportKeep.finishUi, 400) end)
    if not okPost then
        pcall(exportKeep.finishUi)
    end
end

-- 第二步：分批复制（仅"生成新主题"需要）。每批最多占用主线程 80ms，然后让出消息循环
function exportCopyBatch(ctx)
    if exportCtx ~= ctx then return end
    -- 用户中途退出工具：停止后续批次，避免继续往半成品目录写
    if activityDead() then exportCtx = nil; exporting = false; exportKeep.batch = nil; return end
    local total = #ctx.files
    local deadline = nowMs() + 80
    while ctx.idx <= total and nowMs() < deadline do
        local f = ctx.files[ctx.idx]
        local copied = false
        local okCopy = pcall(function() copied = copyFileFast(f[1], f[2]) end)
        if not okCopy or not copied then
            exportFinish(false, "复制失败：" .. tostring(f[1]), ctx)
            return
        end
        ctx.idx = ctx.idx + 1
    end
    local doneN = math.min(ctx.idx - 1, total)
    -- 进度文本节流：每 16 批刷新一次，避免频繁 setText 触发 measure/layout 拖慢复制
    ctx.report = (ctx.report or 0) + 1
    if ctx.report % 16 == 1 or doneN >= total then
        setExportStatus("正在生成：" .. doneN .. " / " .. total .. " 个文件…（界面可正常操作）")
    end
    if ctx.idx <= total then
        uiHandler.postDelayed(exportKeep.batch, 1)
    else
        local okc, cerr = pcall(exportCommit, ctx)
        if not okc then exportFinish(false, "写回失败：" .. tostring(cerr), ctx); return end
        exportFinish(true, nil, ctx)
    end
end

-- 统一入口：准备 →（覆盖：直接写回）/（新主题：异步复制 → 写回）→ 状态行提示
function exportRunAsync(newName, inPlace)
    if exporting then pcall(toast, "正在保存，请稍候…") return end
    -- pcall 包住准备阶段：这里的任何 Lua/Java 异常若逃到 Handler 的 Runnable，
    -- 会变成 Java 线程未捕获异常，直接杀死整个进程（现象就是"输入法闪退重启"）。
    local okPrep, ctx, err = pcall(exportPrepare, newName, inPlace)
    if not okPrep then
        exlog("PREPARE ERROR " .. tostring(ctx))
        setExportStatus("✗ 保存失败（准备阶段）：" .. tostring(ctx))
        return
    end
    if not ctx then
        exlog("PREPARE REJECT " .. tostring(err))
        setExportStatus("✗ " .. tostring(err))
        return
    end
    exporting = true
    exportCtx = ctx

    -- 覆盖原主题：不需要复制任何文件，写完几个文件就是几十毫秒的事。
    -- 仍然分一轮消息去执行，避免在按钮/对话框的事件栈里做写盘。
    if ctx.inPlace then
        setExportStatus("正在写入原主题：" .. tostring(ctx.name) .. "…")
        exportKeep.entry2 = function()
            local okc, cerr = pcall(exportCommit, ctx)
            if not okc then
                exlog("INPLACE ERROR " .. tostring(cerr))
                exportFinish(false, "写入失败：" .. tostring(cerr), ctx)
                return
            end
            local okr, rerr = pcall(resetEditsAfterSave)
            if not okr then exlog("RESET ERROR " .. tostring(rerr)) end
            exportFinish(true, nil, ctx)
        end
        local okPost = pcall(function() uiHandler.postDelayed(exportKeep.entry2, 150) end)
        if not okPost then
            pcall(exportKeep.entry2)
        end
        return
    end

    setExportStatus("正在生成：" .. tostring(ctx.name) .. "（共 " .. #ctx.files .. " 个文件）…")
    exportKeep.batch = function() exportCopyBatch(ctx) end
    local okPost = pcall(function() uiHandler.post(exportKeep.batch) end)
    if not okPost then
        local okRun, runErr = pcall(exportCopyBatch, ctx)
        if not okRun then exportFinish(false, "启动失败：" .. tostring(runErr), ctx) end
    end
end

-- 让一段逻辑在 dialog 完全关闭后的下一轮消息循环里执行。
-- 绝不在列表项/按钮的事件分发栈里直接 show 新对话框或写盘。
local _tickSeq = 0
function nextTick(fn)
    -- 每次用独立 key 持有：连续点击不会互相覆盖，且强引用防 GC 回收正在排队的任务
    _tickSeq = _tickSeq + 1
    local key = "tick" .. _tickSeq
    exportKeep[key] = fn
    local ok = pcall(function() uiHandler.post(function()
        local f = exportKeep[key]
        exportKeep[key] = nil
        if f then pcall(f) end
    end) end)
    if not ok then pcall(fn) end
end

-- 保存主题：覆盖原主题 / 生成新主题
function saveThemeDialog()
    if exporting then pcall(toast, "正在保存，请稍候…") return end
    if not currentTheme then pcall(toast, "请先选择主题") return end
    if dirtyCount == 0 then pcall(toast, "尚无修改，请先编辑按键或样式") return end
    listDialog("保存主题（当前：" .. tostring(currentTheme) .. "）", {
        "覆盖原主题（直接写入当前主题文件）",
        "生成新主题（另存副本）",
    }, function(choice)
        if choice and choice:find("覆盖原主题", 1, true) then
            nextTick(function()
                listDialog("确认覆盖原主题？", {
                    "确认覆盖：" .. tostring(currentTheme),
                    "取消",
                }, function(c2)
                    if c2 and c2:find("确认覆盖", 1, true) then
                        nextTick(function() exportRunAsync(currentTheme, true) end)
                    end
                end)
            end)
        elseif choice and choice:find("生成新主题", 1, true) then
            nextTick(function()
                inputDialog("生成新主题", "输入新主题文件夹名",
                    tostring(currentTheme) .. "-改", function(name)
                        nextTick(function() exportRunAsync(name, false) end)
                    end)
            end)
        end
    end)
end
-- ========== 界面骨架 ==========
activity.setTitle("主题工作室 · 主题编辑")
local root = LinearLayout(activity)
root.setOrientation(LinearLayout.VERTICAL)
root.setLayoutParams(LinearLayout.LayoutParams(-1, -1))

function mkBtn(parent, weight)
    local b = Button(activity)
    b.setAllCaps(false); b.setTextSize(12); b.setSingleLine(true)
    b.setLayoutParams(LinearLayout.LayoutParams(weight or 1, dp(40), weight or 1))
    local lp = b.getLayoutParams()
    lp.setMargins(dp(2), 0, dp(2), 0)
    b.setLayoutParams(lp)
    parent.addView(b)
    return b
end

-- ===== 五个功能按钮（最上）=====
-- 功能按钮行：样式编辑 / 键盘调整 / 视图诊断
local row2 = LinearLayout(activity)
row2.setOrientation(LinearLayout.HORIZONTAL)
row2.setPadding(dp(4), dp(6), dp(4), 0)
root.addView(row2)
local btnStyle = mkBtn(row2)
local btnSettings = mkBtn(row2)
local btnView = mkBtn(row2)
btnStyle.setText("样式编辑")
btnSettings.setText("键盘调整")
btnView.setText("视图/诊断")
btnStyle.setTextColor(0xFFE3B341)
btnSettings.setTextColor(0xFF3FB950)
btnStyle.onClick = function() styleEditorDialog() end
btnSettings.onClick = function() kbdSettingsDialog() end

-- 保存 / 放弃行：与上面三个共五个按钮，全部集中在最上方
local bottom = LinearLayout(activity)
bottom.setOrientation(LinearLayout.HORIZONTAL)
bottom.setPadding(dp(4), dp(2), dp(4), dp(4))
root.addView(bottom)
local btnExport = mkBtn(bottom)
local btnReset = mkBtn(bottom)
btnExport.setText("保存主题")
btnReset.setText("放弃修改")
btnExport.setTextColor(0xFF3FB950)

-- ===== 提示区 =====
-- 状态文字（提示区最前面）：真机当前加载的主题 / 配色 / 键盘
local stTheme, stVariant, stKbd = "主题：当前", "配色：当前", "键盘：当前"
local statusTv = TextView(activity)
statusTv.setTextSize(11)
statusTv.setTextColor(0xFF8B949E)
statusTv.setPadding(dp(8), dp(2), dp(8), dp(2))
local function refreshStatus()
    statusTv.setText(stTheme .. "   ·   " .. stVariant .. "   ·   " .. stKbd)
end
refreshStatus()
root.addView(statusTv)

local hint = TextView(activity)
hint.setTextSize(11)
hint.setTextColor(0xFF888888)
hint.setText("复刻当前键盘 · 点按键中心=点击、四边=滑动、右上角=长按，分别编辑对应事件与样式")
hint.setPadding(dp(8), 0, dp(8), dp(2))
root.addView(hint)

-- ===== 未保存改动区 =====
local dirtyTv = TextView(activity)
dirtyTv.setTextSize(11)
dirtyTv.setTextColor(0xFF8B949E)
dirtyTv.setPadding(dp(8), dp(2), dp(8), dp(2))
root.addView(dirtyTv)

-- 导出状态行：平时隐藏，导出时显示进度、完成后显示结果。
-- 只对这一个已有 View 做 setText —— 完成提示这条路上不新建任何窗口/视图。
local exportStatusTv = TextView(activity)
exportStatusTv.setTextSize(11)
exportStatusTv.setTextColor(0xFF3FB950)
exportStatusTv.setPadding(dp(8), dp(0), dp(8), dp(2))
exportStatusTv.setVisibility(8)   -- 8 = GONE
root.addView(exportStatusTv)
uiStatusTv = exportStatusTv
function refreshDirty()
    dirtyTv.setText("未保存改动：" .. dirtyCount .. " 项（点“保存主题”可覆盖原主题或另存新主题）")
end

-- ===== 键盘视图（最后，占满剩余高度）=====
previewBox = FrameLayout(activity)
local pvLp = LinearLayout.LayoutParams(-1, 0, 1)
pvLp.setMargins(0, dp(4), 0, dp(2))
previewBox.setLayoutParams(pvLp)
previewBox.setPadding(0, dp(4), 0, dp(4))
previewBox.setBackgroundColor(0xFF161B22)
root.addView(previewBox)

activity.setContentView(root)

-- ========== 加载流程 ==========
-- 复刻 ThemeManager.setTheme：Function.loadString(ctx, Config.getStyleKey(name), theme.style or "light")
-- 真机“当前样式”= 用户实际选中的配色（区分日夜模式），不是主题 main.lua 写死的默认值。
function detectCurrentStyle(name, themeStyle)
    local def = (type(themeStyle) == "string" and themeStyle ~= "") and themeStyle or "light"
    local got = nil
    -- 【安全模式】只读 Config.getStyle()——纯 Java 静态偏好读取，不触碰 native 引擎。
    -- 已移除 Function.loadString / LuaApp.getInstance / Config.getStyleKey：这些会拿
    -- 输入法实例或触发 native，工具进程调用即污染共享进程导致输入法随后闪退。
    pcall(function()
        local s = Config.getStyle()
        if type(s) == "string" and s ~= "" then got = s end
    end)
    return got or def
end

-- ========== 复刻真机 ThemeManager.getKeyboard：当前方案该用哪个键盘 ==========
-- 真机链条（见 trime2 源码 ThemeManager.getKeyboard / Config.getKeyboard / InputView）：
--   ① Config.getKeyboard() = 偏好键 "<主题>_<schema>_keyboard"，用户显式选过就用它；
--   ② 为空 → 取当前 schema_id（Rime.getCurrentRimeSchema()，回退偏好 select_schema_id）；
--   ③ 从 schemas/<group>/<schema>.schema.yaml 读 speller/alphabet；
--   ④ 调主题根 main.lua 的 get_keyboard(schema_id, alphabet) → 键盘名（qwerty36/27/…）。
-- 工作室此前只做了①，空值时回退 kbds[1]（多为 qwerty27），完全没走 main.lua 判断，
-- 所以预览键盘与真机不符。这里把②③④补齐，得到与真机一致的键盘文件。
-- 当前方案的字母表。主题的 get_keyboard(id, alphabet) 靠它区分中英/数字/符号布局，
-- 传错了主题就会选错键盘文件。来源依次为：桥接（源码 native 方法）→ 源码静态方法 → 纯字母表。
function detectAlphabet()
    if bridgeData and type(bridgeData.meta) == "table" then
        local a = bridgeData.meta.alphabet
        if type(a) == "string" and a ~= "" then return a end
    end
    for _, fn in ipairs({ "getSchemaAlphabet", "getAlphabet", "getCurrentAlphabet" }) do
        local ok, v = pcall(function() return Config[fn]() end)
        if ok and type(v) == "string" and v ~= "" then return v end
    end
    return "abcdefghijklmnopqrstuvwxyz"
end

function detectCurrentKeyboard(name, themeEnv, kbds, alphabet)
    local function inKbds(k)
        if type(k) ~= "string" or k == "" then return nil end
        -- 统一成带 .lua 的文件名：Config.getKeyboards() 不同版本返回的形式不一致
        -- （有的带后缀有的不带），后续拼接路径只认带后缀的。
        local want = k:match("%.lua$") and k or (k .. ".lua")
        for _, f in ipairs(kbds) do
            local nf = f:match("%.lua$") and f or (f .. ".lua")
            if nf == want then return want end
        end
        if themeDir and fileExists(themeDir .. "/keyboards/" .. want) then return want end
        return nil
    end
    local function pick(id, how)
        if type(id) ~= "string" or id == "" then return nil end
        local f = inKbds(id)
        if f then return f, how .. " = " .. id .. " → " .. f end
        return nil
    end

    -- 判定原则：当前键盘 = 主题 get_keyboard(id, alphabet) 的返回值。
    --   id      = 输入法设置里的键盘选择（auto / 未设置为空 → 跟随主题）
    --   alphabet= 当前方案的字母表（决定中英/数字布局的主题会用到）
    -- 下面按"可信度"排，先问正在运行的输入法，再在本地用同样入参求值主题函数。
    alphabet = (type(alphabet) == "string" and alphabet ~= "")
        and alphabet or "abcdefghijklmnopqrstuvwxyz"
    local setKbd = tostring(readPref("keyboard", "") or "")
    if setKbd == "auto" then setKbd = "" end

    -- ① 桥接同源结果：桥接在【真机那份主题 Globals】里调过 get_keyboard，
    --    函数实现、alphabet、全局变量都与输入法完全一致，没有任何推断成分。
    if bridgeData and type(bridgeData.meta) == "table" then
        local bf = bridgeData.meta.keyboard_file
        if type(bf) == "string" and bf ~= "" then
            local f = inKbds(bf)
            if f then
                return f, "桥接 get_keyboard → " .. bf .. "（" ..
                    tostring(bridgeData.meta.keyboard_file_source) .. "）"
            end
        end
    end

    -- ② 本地求值主题自己的 get_keyboard：把主题函数原样执行，入参与真机相同。
    --    这样换主题、换写法都不需要改工具，真正做到通用。
    local gk = themeEnv and themeEnv.get_keyboard
    if type(gk) == "function" then
        local ok, ret = pcall(gk, setKbd, alphabet)
        if ok and type(ret) == "string" and ret ~= "" then
            local f, why = pick(ret, "主题 get_keyboard")
            if f then return f, why .. "（id=\"" .. setKbd .. "\"）" end
        end
    end

    -- ③ 设置里显式选了键盘（get_keyboard 的 else 分支，求值失败时的等价替代）
    if setKbd ~= "" then
        local f, why = pick(setKbd, "输入法设置 keyboard")
        if f then return f, why end
    end

    -- ④ 运行时缓存：只有手动在键盘对话框里选过键盘，Config 才会写这个键
    local schemaId = readPref("select_schema_id", "")
    if schemaId ~= "" then
        for _, sk in ipairs({ schemaId, (schemaId:gsub("%.schema$", "")) }) do
            local v = readPref(tostring(name) .. "_" .. tostring(sk) .. "_keyboard", "")
            if v ~= "" then
                local f, why = pick(v, "偏好 " .. tostring(name) .. "_" .. tostring(sk) .. "_keyboard")
                if f then return f, why end
            end
        end
    end

    -- ⑤ 主题根 keyboard= 声明（get_keyboard 缺失时的等价物）
    local f5, why5 = pick(themeEnv and themeEnv.keyboard, "主题 main.lua keyboard")
    if f5 then return f5, why5 end

    -- ⑥ 主题只有一个键盘文件：没有歧义
    if #kbds == 1 then return kbds[1], "主题仅有一个键盘文件 " .. kbds[1] end
    return nil, nil
end

-- 【关键修复】桥接 meta.keyboard 来自键盘脚本的 name 字段（显示名，如"万象"），
-- 不是磁盘文件名（wanxiang.lua）。万象等主题两者不一致。若把显示名当文件名写回，
-- 导出会在 keyboards/ 下新建一个空的"万象.lua"，而真机加载的 wanxiang.lua 毫发未动，
-- 表现为"新主题和原主题一样"。
--
-- 注意：name= 会重复（多个布局变体可能都叫"万象"），所以不能"命中第一个就用"。
-- 这里只负责给出【全部候选】，由 pickKbdByShape 用输入法内存键位做指纹消歧。
function kbdFileHasData(fn)
    if not themeDir or type(fn) ~= "string" or fn == "" then return false end
    local p = themeDir .. "/keyboards/" .. fn
    if not fileExists(p) then return false end
    local body = readFile(p)
    if body == nil then return false end
    -- 空壳判定：历史导出 bug 生成的文件只有几行、没有键盘数据关键字
    return #body > 40 and (body:find("rows") ~= nil or body:find("keys") ~= nil or body:find("require") ~= nil)
end

-- 静态读取键盘脚本的 name：本体没有裸 name= 时，顺着 require 链去读被 require 的文件拿 name。
-- 全程只读文件、不执行任何脚本（零副作用，符合"零脚本执行"铁律）。
-- 带 visited 防环 + 深度(4) + 读取预算(24) 防卡死；require 模块名按真机语义（.→/，补 .lua），
-- 优先在脚本同目录、其次 <主题>/keyboards、主题根查找。
-- 返回第一个找到的 name 字符串，找不到返回 nil。
function kbdNameOfFile(path, depth, visited, budget)
    depth = depth or 0
    visited = visited or {}
    budget = budget or { n = 24 }
    if depth > 4 or budget.n <= 0 then return nil end
    path = tostring(path):gsub("\\", "/")
    if visited[path] then return nil end
    visited[path] = true
    budget.n = budget.n - 1
    local body = readFileHead(path, 32768)
    if not body then return nil end
    local code = stripLuaComments(body)
    local nm = code:match('name%s*=%s*"([^"]*)"') or code:match("name%s*=%s*'([^']*)'")
    if nm then return nm end
    -- 本体无 name：收集 require 模块名（多种写法），注释里的 require 已被 strip 掉
    local mods = {}
    for m in code:gmatch('require%s*"([%w_%.]+)"') do mods[#mods + 1] = m end
    for m in code:gmatch("require%s*'([%w_%.]+)'") do mods[#mods + 1] = m end
    for m in code:gmatch('require%s*%(%s*"([%w_%.]+)"%s*%)') do mods[#mods + 1] = m end
    for m in code:gmatch("require%s*%(%s*'([%w_%.]+)'%s*%)") do mods[#mods + 1] = m end
    if #mods == 0 then return nil end
    local dir = path:match("^(.*)/[^/]+$") or ""
    for _, mod in ipairs(mods) do
        local rel = (mod:gsub("%.", "/")) .. ".lua"
        local tries = {}
        if dir ~= "" then tries[#tries + 1] = dir .. "/" .. rel end
        if themeDir then
            tries[#tries + 1] = themeDir .. "/keyboards/" .. rel
            tries[#tries + 1] = themeDir .. "/" .. rel
        end
        for _, p in ipairs(tries) do
            if fileExists(p) then
                local got = kbdNameOfFile(p, depth + 1, visited, budget)
                if got then return got end
                break
            end
        end
        if budget.n <= 0 then break end
    end
    return nil
end

function findKbdCandidates(displayName)
    local out = {}
    if not themeDir or type(displayName) ~= "string" or displayName == "" then return out end
    local kd = themeDir .. "/keyboards"
    local bare = displayName:match("([^/]+)%.lua$") or displayName
    -- ① 脚本内 name= 与显示名相同的所有文件（可能不止一个）
    local okList, files = pcall(listDir, kd)
    if okList and type(files) == "table" then
        for _, fn in ipairs(files) do
            if type(fn) == "string" and fn:match("%.lua$") then
                -- 静态读 name（含 require 链），不执行脚本、零副作用。
                local nm = kbdNameOfFile(kd .. "/" .. fn)
                if nm and (nm == displayName or nm == bare) then out[#out + 1] = fn end
            end
        end
    end
    -- ② 文件名直接等于显示名 / 键盘 id；要求文件里确有键盘数据（防历史留下的空壳文件）
    for _, cand in ipairs({ bare .. ".lua", bare }) do
        local dup = false
        for _, f in ipairs(out) do if f == cand then dup = true end end
        if not dup and kbdFileHasData(cand) then out[#out + 1] = cand end
    end
    return out
end

-- 键盘脚本里 name= 的显示名，能否对上这个文件名（如「万象」↔ wanxiang.lua）。
-- 用途：桥接给的键盘是「输入法内存里的键盘」，本次要加载的是「主题 get_keyboard
-- 求出的文件」，两者可能不是同一个（换过键盘但输入法还没重载），必须能识别出来。
local _kbdCandCache = {}
function kbdFileMatchesDisplay(file, display)
    if type(file) ~= "string" or file == "" then return false end
    if type(display) ~= "string" or display == "" then return false end
    local bare = file:gsub("%.lua$", "")
    local disp = display:gsub("%.lua$", "")     -- 显示名也可能带 .lua（偏好里存的就是文件名）
    if bare:lower() == disp:lower() then return true end
    local list = _kbdCandCache[disp]
    if not list then
        list = findKbdCandidates(disp)
        _kbdCandCache[disp] = list
    end
    for _, c in ipairs(list) do
        if c == file or c:gsub("%.lua$", "") == bare then return true end
    end
    return false
end

-- 键位指纹：行序 + 每行键数 + 前几个键的显示文字。用于在多个同名候选里认出真机当前那个。
-- 键位指纹两级：结构（行序 + 每行键数）用于粗筛，文字（前几个键的显示值）用于细分。
-- 只比结构就能排除绝大多数变体，且不受 bridge 序列化与脚本解析之间的字段差异影响。
function kbdShape(env, withText)
    local rows = type(env) == "table" and env.rows
    if type(rows) ~= "table" then return nil end
    local idx = {}
    for k, v in pairs(rows) do
        if type(k) == "number" and type(v) == "table" and type(v.keys) == "table" then idx[#idx + 1] = k end
    end
    if #idx == 0 then return nil end
    table.sort(idx)
    local seg, SEP = {}, "\1"
    for _, i in ipairs(idx) do
        local keys = rows[i].keys
        local n = 0
        for _ in pairs(keys) do n = n + 1 end
        if withText then
            local t = {}
            for j = 1, math.min(8, #keys) do
                local kk = keys[j]
                local v
                if type(kk) == "table" then v = kk.click or kk.label or kk.text or kk.key else v = kk end
                t[#t + 1] = tostring(v or "")
            end
            seg[#seg + 1] = n .. ":" .. table.concat(t, SEP)
        else
            seg[#seg + 1] = tostring(n)
        end
    end
    return table.concat(seg, "|")
end

-- 多候选消歧：候选脚本在 clean 环境求值（不碰真机对象），与内存键位比指纹。
-- 结构一致即视为等价变体；结构一致但文字不同时再细分。都不匹配返回 nil。
function pickKbdByShape(cands, refKbd)
    if type(cands) ~= "table" or #cands == 0 or type(refKbd) ~= "table" then return nil end
    local struct = kbdShape(refKbd, false)
    if not struct then return nil end
    local envs, pass = {}, {}
    local limit = math.min(#cands, 8)   -- 安全阀：同名变体极多时别把启动拖成秒级
    for i = 1, limit do
        local f = cands[i]
        local ok, env = pcall(parseKeyboardData, themeDir .. "/keyboards/" .. f)
        if ok and keyboardRowsOK(env) then
            envs[f] = env
            if kbdShape(env, false) == struct then pass[#pass + 1] = f end
        end
    end
    if #pass == 0 then return nil end
    if #pass == 1 then return pass[1] end
    local text = kbdShape(refKbd, true)
    if text then
        for _, f in ipairs(pass) do
            if kbdShape(envs[f], true) == text then return f end
        end
    end
    return pass[1]
end

-- rows 可能是稀疏表：万象这类脚本用 rows[i+2]={...} 从下标 3 开始填（前两行是
-- toolbar/候选，由真机视图另算），Lua 的 # 对开头为 nil 的稀疏表返回 0，旧判断
-- "#rows>0" 会误判成“没有键盘”→ 回退 qwerty27。改用最大数字下标 + 是否存在含 keys 的行。
function keyboardRowsOK(env)
    return env and type(env.rows) == "table" and rowsCount(env.rows) > 0
end

-- ===== 【通用方案·核心】键盘脚本"数据部分"通用求值（不碰任何真机 Java 对象） =====
-- 背景：万象这类主题的键盘脚本是"真机调用 + 纯数据"混写：
--   import "…ThemeManager"; PreferenceManager.getDefaultSharedPreferences(this)  -- 真机调用
--   require"qwerty36"; require"keys"; rows[i+2]={keys=allk[i].keys}              -- 纯数据
-- 之前"完整执行"改用 sandboxLoad，小写名会从 parentEnv（真机 Globals）继承，
-- 真机对象泄漏进来触发 native coercion 崩溃。
-- 本方案用一个【不继承真机 Globals 的 clean 环境】：任何未定义标识符（无论大小写）
-- 一律返回纯 Lua 安全桩（makeSafeStub）——没有真机 Java 对象，物理上不可能 coercion。
-- 标准库（string/table/math）用真机的纯计算函数（无副作用、不碰进程）。
-- 提供共享 require：require"keys" → 找 keys.lua → 在同一环境执行 → 定义全局 allk，
-- 于是 qwerty36/wanxiang 里依赖 allk 动态拼出的 rows 能完整构造出来。
-- 用户确认 tool 与输入法是两套独立 Lua 实例，本环境执行绝不污染输入法。
-- kbdDir：键盘 VM 的 finder 根。真机 InputView 的 finder.findFile() 把 require 的相对
-- 路径拼到 Config.getKeyboardDir()（= <主题>/keyboards），所以 require"keys" 解析为
-- <主题>/keyboards/keys.lua。键盘 VM 与主题 VM(根=themes 目录)、style VM 是三套独立
-- Globals，require 路径互不相干，必须按各自的根解析，不能混用一套全树搜索。
-- 脚本执行时间闸。
-- LuaJ 没有可中断的 native 调用，但键盘脚本是纯 Lua（真机调用已被桩替换），
-- 用 debug.sethook 按指令数定期检查，超过时限就抛错打断死循环 / 超长计算。
-- 这是「打开就卡死」的最后一道保险：即使某主题的脚本写了死循环，也能在 3 秒内退出。
local _hookDepth = 0
local function runWithLimit(f, limitSec)
    if type(debug) ~= "table" or type(debug.sethook) ~= "function" then
        return pcall(f)
    end
    local t0 = os.clock()
    local limit = tonumber(limitSec) or 3
    _hookDepth = _hookDepth + 1
    pcall(function()
        debug.sethook(function()
            if os.clock() - t0 > limit then
                error("__KBD_TIMEOUT__", 0)
            end
        end, "", 200000)
    end)
    local ok, ret = pcall(f)
    _hookDepth = _hookDepth - 1
    if _hookDepth <= 0 then
        _hookDepth = 0
        pcall(function() debug.sethook() end)
    end
    return ok, ret
end

function buildKeyboardDataEnv(kbdDir)
    local env = {}
    env._G = env
    -- 共享 require 缓存（同一环境内，模块定义的全局 allk 等能被后续脚本看到）
    local reqCache = {}
    local stubCache = {}
    local function stub(k)
        if not stubCache[k] then stubCache[k] = makeSafeStub() end
        return stubCache[k]
    end
    -- 万能 __index：任何未定义名 → 纯 Lua 桩，绝不继承真机 Globals
    setmetatable(env, {
        __index = function(t, k)
            if type(k) ~= "string" or k == "" then return nil end
            return stub(k)
        end,
    })
    -- 基础库：仅纯计算，无进程副作用
    env.type = type
    env.pairs = pairs
    env.ipairs = ipairs
    env.next = next
    env.rawget = rawget
    env.rawset = rawset
    env.rawequal = rawequal
    env.rawlen = rawlen
    env.tostring = tostring
    env.tonumber = tonumber
    env.unpack = unpack or table.unpack
    env.select = select
    env.__nilSafe = __nilSafe  -- nil 访问兜底智能表（键盘脚本的 #nil/index nil 通用防护）
    env.print = print
    env.error = error
    env.assert = assert
    env.setmetatable = setmetatable
    env.getmetatable = getmetatable
    env.string = string
    env.table = table
    env.math = math
    env.coroutine = coroutine
    -- pcall/xpcall 保留（脚本里 pcall(require,...) 用得到）
    env.pcall = pcall
    env.xpcall = xpcall
    -- 所有真机入口 → 安全桩（no-op）
    env.this = makeSafeStub()
    env.service = makeSafeStub()
    env.activity = makeSafeStub()
    env.context = makeSafeStub()
    env.luajava = makeSafeStub()
    env.java = makeSafeStub()
    env.import = function(cls) return makeSafeStub() end
    env.inherit = function(base, over)
        local n = {}
        local src = (type(base) == "table") and base or ((type(base) == "string") and env[base] or nil)
        if type(src) == "table" then for k, v in pairs(src) do n[k] = v end end
        if type(over) == "table" then for k, v in pairs(over) do n[k] = v end end
        return n
    end
    -- 递归查找文件（主题树 + scripts 目录 + dataDir）
    -- 【防卡死】带访问预算：递归里每轮都重建 roots 并对 dataDir 全树重扫，多次 require
    -- 找不到时会累积成长时间扫描 → 加载过久被杀进程。限制单次查找的目录访问总数。
    local searchBudget = { n = 200 }
    -- dir=nil 时扫描固定 roots；递归时必须把子目录 sub 传下去，否则每层都从头重扫
    -- 同样的根目录、空转 6 层——这正是 require"keys" 找不到 keys.lua 时“加载过久”的元凶。
    local function findFile(fname, depth, dir)
        depth = depth or 0
        if depth > 6 then return nil end
        searchBudget.n = searchBudget.n - 1
        if searchBudget.n <= 0 then return nil end
        local dirs
        if dir then
            dirs = { dir }
        else
            -- 【键盘 VM finder 根】真机 require 相对路径拼到 Config.getKeyboardDir()。
            -- 不同主题把公共库（keys.lua / allk.lua / preset_keys.lua）放在
            -- keyboards/ 或主题根，两种都要搜，否则 require 失败 → rows 里的键名
            -- 解析不出来 → 布局退化成朴素键位。
            local roots = {}
            if kbdDir then roots[#roots + 1] = kbdDir end
            if themeDir then
                roots[#roots + 1] = themeDir .. "/keyboards"
                roots[#roots + 1] = themeDir
            end
            -- 次级回退：真机 getDataDir()/scripts 也是公共库所在地，但优先级低于键盘目录
            local okD, dataDir = pcall(function() return Config.getDataDir() end)
            if okD and dataDir then
                roots[#roots + 1] = tostring(dataDir) .. "/scripts"
            end
            dirs = roots
        end
        for _, root in ipairs(dirs) do
            local p = root .. "/" .. fname
            if fileExists(p) then return p end
        end
        -- 递归搜子目录（传 sub 下去，真正进入子目录）
        for _, root in ipairs(dirs) do
            local okL, names = pcall(listDir, root)
            if okL and names then
                for _, nm in ipairs(names) do
                    local sub = root .. "/" .. nm
                    local okS, isd = pcall(isDir, sub)
                    if okS and isd then
                        local r = findFile(fname, depth + 1, sub)
                        if r then return r end
                    end
                end
            end
        end
        return nil
    end
    -- 在当前环境编译并执行一个源文件（用 load 第4参绑定 env），返回 chunk 的 return 值。
    -- 只执行一次：返回表用于 require 语义，全局副作用（如 rows/allk）也在这同一次里完成。
    local function runSource(src, chunkName)
        if not src then return nil, "源码为空" end
        local f
        if load then
            local ok, g = pcall(load, src, "@" .. (chunkName or "kbd"), "t", env)
            if ok and g then f = g end
        end
        if not f and loadstring then f = loadstring(src, "@" .. (chunkName or "kbd")) end
        if not f then return nil, "编译失败" end
        -- clean 环境里未定义名都是桩，脚本不应报错；万一报错也吞掉，尽量保留已构造的 rows。
        -- 时间闸：超过 3 秒直接中止，返回错误文本供诊断定位（死循环不再拖死主线程）。
        local ok, ret = runWithLimit(f, 3)
        if ok then return ret end
        if tostring(ret):find("__KBD_TIMEOUT__", 1, true) then
            return nil, "脚本执行超时（>3s），已中止（疑似死循环）"
        end
        return nil, tostring(ret)  -- 返回错误文本供诊断定位卡在哪一行
    end
    env.require = function(mod)
        if type(mod) ~= "string" then return makeSafeStub() end
        if reqCache[mod] then return reqCache[mod] end
        local fname = mod:gsub("%.", "/") .. ".lua"
        searchBudget.n = 200  -- 每个模块查找独立预算，避免多模块累积过早耗尽
        local p = findFile(fname, 0) or findFile(mod .. ".lua", 0)
        if not p then
            reqCache[mod] = makeSafeStub()
            return reqCache[mod]
        end
        -- 【循环 require 防护】执行前先占位，打断模块互相 require 的无限递归
        reqCache[mod] = env
        local src = readFile(p)
        local ret = runSource(src, p)
        if type(ret) == "table" then reqCache[mod] = ret
        else reqCache[mod] = env  -- 共享环境，allk 等作为全局可见
        end
        return reqCache[mod]
    end
    env.dofile = function(p)
        local src = readFile(p)
        runSource(src, p)
    end
    env.loadfile = function(p)
        local src = readFile(p)
        if load then return load(src, "@" .. tostring(p), "t", env) end
    end
    env.loadstring = function(s, name)
        if load then return load(tostring(s), name or "=(loadstring)", "t", env) end
        return function() end
    end
    env.load = function(s, name, mode, e)
        if load then return load(s, name, mode or "t", e or env) end
        return function() end
    end
    return env, runSource
end

function parseKeyboardData(path)
    local src = readFile(path)
    if not src then return nil end
    local kbdDir = path:match("^(.*)/[^/]+$")  -- 键盘脚本所在目录 = 键盘 VM 的 finder 根
    local env, runSource = buildKeyboardDataEnv(kbdDir)
    -- 入口脚本：先用 runSource 执行一遍（建立 rows/require）；不依赖 return 值
    local _, runErr = runSource(src, path)
    if not keyboardRowsOK(env) then
        local short = path:match("([^/]+)$") or path
        if not kbdParseDiag[short] then
            kbdParseDiag[short] = "通用求值未拿到 rows（脚本错误：" .. tostring(runErr or "无") .. "）"
        end
        return nil
    end
    local out = {}
    out.rows = env.rows
    if type(env.name) == "string" then out.name = env.name end
    if type(env.key_width) == "number" then out.key_width = env.key_width end
    if type(env.key_height) == "number" then out.key_height = env.key_height end
    return out
end

-- （反射读取运行时键盘的方案已删除：改由 ThemeDataBridge.snapshot().keyboard 提供，见 readBridgeSnapshot。）

-- 这是真机"实际显示什么"的权威来源——图片是 ImageSpan、文字是纯文本，和屏幕一致，
-- 彻底绕开 getSpan 在工具/输入法两个进程加载图片结果不同的问题。
-- 全程只读 View 属性（getChildCount/getChildAt/getText/getLeft...），均为纯 Android View 方法，
-- 不触发任何 native 引擎方法；每层 pcall + 判空，视图未就绪时安全返回。仅用户主动点击时运行。
-- dump【工具自己渲染】的键盘 View 树：遍历 previewBox，输出每个 TextView 的文本、
-- 尺寸、是否含 ImageSpan。与真机 dump（dumpKbViewTexts→桥接 dumpRootTexts）配套，
-- 两者对照即可精确定位"工具画的 ▼ 是图还是字 / 尺寸颜色 / L-Z 上标"等差异。
function dumpToolRenderedTexts()
    local out = {}
    local ok0, _ = pcall(function()
        -- 【r18】不依赖 luajava.instanceof / 反射类名判节点类型：本环境对工具侧
        -- View（FrameLayout / 自定义 View）判定不稳定，旧版把根节点类名拿成 "?"、并把
        -- 所有子节点都判成非 ViewGroup/TextView，导致工具段只有 ROOT(TOOL): ? 一行，
        -- 一个 [TOOL] 文本都打不出来（r17 用户实测确认）。改用鸭子类型：
        --   能 getChildCount() 返回非负整数 → 视为容器，继续递归子节点；
        --   能 getText() 返回非空 → 视为文本视图，打印文本/尺寸/坐标。
        -- 纯 View 方法调用，单点 pcall 保护，不触发任何 native 引擎方法。
        -- 【r19】AndroLua 的 Java 对象方法必须用点号 .method() 调用；冒号 :method()
        -- 会把对象自身塞进第一个参数，Java 方法签名不匹配而全部失败（r18 实测：
        -- getClass/getWidth/getChildCount 全返回 -1，整棵树仍为空）。工具其余代码
        -- （et.getText()/previewBox.getWidth()）一律点号，这里统一。
        local function childCount(v)
            local ok, n = pcall(function() return v.getChildCount() end)
            if ok and type(n) == "number" and n >= 0 then return math.floor(n) end
            return nil
        end
        local function textOf(v)
            local ok, cs = pcall(function() return v.getText() end)
            if not ok or cs == nil then return nil end
            local ok2, s = pcall(function() return tostring(cs) end)
            return ok2 and s or nil
        end
        local function nameOf(v)
            local short = "View"
            pcall(function()
                local cls = v.getClass()
                if cls then
                    local n = cls.getName()
                    if n then short = tostring(n):match("([^%.]+)$") or short end
                end
            end)
            return short
        end
        local function walk(v, d)
            if v == nil or d > 18 then return end
            local txt = textOf(v)
            -- 只打印真正有文本的 TextView：容器类 getText() 在某些实现里返回空串，
            -- 空串行会淹没对照视图（真机 dump 也只列有内容的 TextView）。
            if txt and txt ~= "" then
                local l, t, w, h = -1, -1, -1, -1
                local tx, ty = 0, 0
                pcall(function() l = v.getLeft() end)
                pcall(function() t = v.getTop() end)
                pcall(function() w = v.getWidth() end)
                pcall(function() h = v.getHeight() end)
                -- 【r24】dump 的 getTop 是布局坐标、不含 translation；真机 offset 用
                -- setTranslationY 施加。把 translation 一起打出来，才能和真机视觉位置对照。
                pcall(function() tx = v.getTranslationX() end)
                pcall(function() ty = v.getTranslationY() end)
                txt = txt:gsub("\n", "\\n")
                out[#out + 1] = string.format("[TOOL] %s@%d,%d %dx%d tr=(%d,%d) [TXT] = [%s]",
                    nameOf(v), l, t, w, h, math.floor(tx or 0), math.floor(ty or 0), txt)
            end
            local n = childCount(v)
            if n then
                for i = 0, n - 1 do
                    local c = nil
                    pcall(function() c = v.getChildAt(i) end)
                    if c then walk(c, d + 1) end
                end
            end
        end
        if previewBox then
            local pw, ph, pc = -1, -1, -1
            pcall(function() pw = previewBox.getWidth() end)
            pcall(function() ph = previewBox.getHeight() end)
            pcall(function() pc = previewBox.getChildCount() end)
            out[#out + 1] = string.format("ROOT(TOOL): %s %dx%d children=%d",
                nameOf(previewBox), pw, ph, pc)
            walk(previewBox, 0)
        else
            out[#out + 1] = "ERR: previewBox 为空"
        end
    end)
    if not ok0 then out[#out + 1] = "ERR: 工具自渲染遍历异常" end
    -- 数据源摘要：真机文字源命中 + 结构化导出状态（手动诊断菜单可见）。
    local d = _G.__kbdDiag or {}
    out[#out + 1] = string.format("[DIAG] liveN=%s rendered=%s ltHit=%s cornerXY=%s",
        tostring(liveKeyTextsN or 0), tostring(d.rendered or 0),
        tostring(d.ltHit or 0), tostring(d.cornerWithXY or 0))
    if _G.__ksDiag then out[#out + 1] = "[DIAG] KS " .. tostring(_G.__ksDiag) end
    if _G.__bridgeDiag then out[#out + 1] = "[DIAG] BRIDGE " .. _G.__bridgeDiag end
    out[#out + 1] = string.format("---- TOOL DONE ---- VER=r27.49 ksLen=%d liveN=%s BRIDGE[%s]",
        #tostring(_G.__ksRaw or ""), tostring(liveKeyTextsN or 0),
        tostring(_G.__bridgeDiag or "nil"))
    return table.concat(out, "\n")
end

function dumpKbViewTexts(noRender)
    -- 【r27.41】noRender=true：只采集真机 dump 供诊断日志，不 apply 快照、不重绘。
    -- 首帧已同步采集并渲染过，诊断 dump 若再渲染就是无谓的第二次全量渲染。
    -- 真机 View 树遍历放在 Java 桥接类内部（编译期绑定）。工具进程拿不到正在渲染的
    -- Service 实例，但 TrimeService.onCreate 保存的 RootInputView 静态引用跨 Lua 虚拟机
    -- 共享——它涵盖键盘 + 工具栏 + 候选栏整棵树。
    local Bridge
    if not pcall(function() Bridge = luajava.bindClass("com.osfans.trime.theme.ThemeDataBridge") end) or not Bridge then
        return "无法绑定 ThemeDataBridge 类（APK 未打桥接补丁？）"
    end
    -- 优先 dumpRootTexts（整个 root）；旧版 APK 没有该方法时回退 dumpKeyboardTexts
    local ok, r = pcall(function() return Bridge.dumpRootTexts() end)
    if not ok or r == nil then
        local ok2, r2 = pcall(function() return Bridge.dumpKeyboardTexts() end)
        if not ok2 then return "dumpRootTexts/dumpKeyboardTexts 调用异常：" .. tostring(r2) end
        r = r2
    end
    -- 同时附上【工具自渲染】View 树，与真机 dump 对照，一次定死 ▼ / 上标差异。
    -- 【r25.2 诊断】桥接摘要必须在这里（生成工具段之前）算好：dumpToolRenderedTexts
    -- 会把摘要塞进最后 emit 的 ---- TOOL DONE ---- 行。诊断视图只留末尾若干行，
    -- 单独的 BRIDGE/[DIAG] 行在 emit 顺序前部会被工具段 150 行冲掉，只有 TOOL DONE 可见。
    do
        local rs = tostring(r)
        local errLine = rs:match("(ERR:%s*[^\r\n]+)")
        local rootLine = rs:match("(ROOT:%s*[^\r\n]+)")
        local kb, tv = 0, 0
        for _ in rs:gmatch("%[KEYBOARD%]") do kb = kb + 1 end
        for _ in rs:gmatch("[Tt]extView@") do tv = tv + 1 end
        _G.__bridgeDiag = string.format("ERR=[%s] ROOT=[%s] kb=%d tv=%d len=%d",
            tostring(errLine or ""), tostring(rootLine or ""), kb, tv, #rs)
    end
    -- 【r27】结构化导出：Java 按缓存的 KeyView 树直接导出每个键的主标签 +
    -- 各方向角标的权威 gravity/坐标/文本。工具据此 1:1 复刻，零猜测。
    -- 旧 APK 没有 dumpKeyboardStructure 方法时 pcall 失败 → ksRaw 为空 → 自动回退扁平解析。
    local ksRaw = ""
    pcall(function() ksRaw = Bridge.dumpKeyboardStructure() or "" end)
    _G.__ksRaw = ksRaw
    local ksN = tonumber(ksRaw:match("KSDONE%s+n=(%d+)")) or 0
    local ksCorners = 0
    for _ in ksRaw:gmatch("KSCORNER%s") do ksCorners = ksCorners + 1 end
    _G.__ksDiag = string.format("n=%d corners=%d", ksN, ksCorners)
    -- 【r27.7 诊断根因】旧顺序是"先 dump 工具视图、后 applyLiveFromRaw"，导致
    -- [CORNER]/[DIAG] 永远反映【应用快照之前】的上一次渲染状态：即便本次 dump 成功、
    -- 屏幕已用真机坐标正确重绘，诊断里也永远看不到 dump=(...)，根本无法判断角标有没有
    -- 用上权威坐标。改为：先 apply 快照 → 同步重绘 → 再 dump 工具视图，诊断即真实结果。
    local realStruct = "===== 真机 root =====" .. tostring(r)
        .. "\n\n===== 结构化 =====\n" .. tostring(ksRaw)
    -- 【r27.41】noRender 时只留原始 dump 文本供诊断，不再 apply 快照、不再重绘。
    if not noRender then
        pcall(applyLiveFromRaw, realStruct .. "\n\n===== 工具自渲染 =====")
        -- renderPreview 有 50ms 节流会走异步；这里直接调实现，确保本轮工具视图是最新的
        pcall(renderPreviewImpl)
    end
    -- 【r27.22】强制整棵树 measure+layout：r27.21 的 ACT 全 0 是因为 dump 时 view 还没
    -- layout（getLeft/getWidth 在 layout 前恒为 0，r21 踩过同一坑）。这里用当前 previewBox
    -- 宽高做 EXACTLY measure 再 layout，令所有角标 view 的 getLeft/getTop 立即变成真实渲染值。
    pcall(function()
        local pw = previewBox.getWidth()
        local ph = previewBox.getHeight()
        if pw > 0 and ph > 0 then
            local EXACTLY = 1073741824  -- 0x40000000
            previewBox.measure(EXACTLY + pw, EXACTLY + ph)
            previewBox.layout(0, 0, pw, ph)
        end
    end)
    local toolDump = dumpToolRenderedTexts()
    return realStruct .. "\n\n===== 工具自渲染 =====" .. toolDump
end

-- ===== 【r27 权威数据源】解析结构化键盘导出（Java dumpKeyboardStructure）=====
-- 格式见 ThemeDataBridge.dumpKeyboardStructure 注释。产出与 parseRootDumpToKeys
-- 完全同构的 {keys={[seq]={label,top,bottom,corners={{grav,txt,x,y,w,h}}}}, n}，
-- 因此 makeKeyView 里按 gravity 分通道 + 用 c.x/c.y 权威坐标定位的消费代码无需改动。
-- 关键：方向来自真机 LayoutParams.gravity（非 cx/cy 猜），坐标来自 getLeft+translation
-- （最终视觉位置，直接当 LP margins），文本来自 getText（Rime 转换后的显示文字）。
function parseKeyStructure(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local keys, maxSeq = {}, 0
    local function ensure(seq)
        local e = keys[seq]
        if not e then
            e = { label = nil, top = nil, bottom = nil, corners = {}, region = "KEYBOARD" }
            keys[seq] = e
            if seq > maxSeq then maxSeq = seq end
        end
        return e
    end
    for line in raw:gmatch("[^\r\n]+") do
        local ks = tonumber(line:match("^KSKEY%s+(%d+)"))
        if ks then
            local e = ensure(ks)
            local reg = line:match("r=(%a+)")
            if reg then e.region = reg end
            -- 【r27.7】记录键的布局宽高，用于识别"未布局的退化 dump"：
            -- 工具全屏时输入法键盘被遮挡，真机 View 未 measure，box 宽高全 0。
            local bw, bh = line:match("box=%-?%d+,%-?%d+,(%d+),(%d+)")
            if bw then e.bw, e.bh = tonumber(bw), tonumber(bh) end
        else
            local cs = tonumber(line:match("^KSCLICK%s+(%d+)"))
            local cr = tonumber(line:match("^KSCORNER%s+(%d+)"))
            if cs or cr then
                local seq = cs or cr
                local e = ensure(seq)
                local reg = line:match("r=(%a+)")
                if reg then e.region = reg end
                local x, y, w, h = line:match("xy=(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)")
                local txt = line:match("txt=%[(.*)%]")
                if txt then txt = txt:gsub("%%5B", "["):gsub("%%5D", "]") end
                if cs then
                    if txt and txt ~= "" then e.label = txt end
                    -- 【r27.18】click 主标签的桥接权威坐标（含 translation 的最终视觉位置）
                    -- 与 gravity，供主标签像角标一样绝对定位，消除各主题推导差异。
                    if x then e.clickX, e.clickY = tonumber(x), tonumber(y) end
                    local cg = line:match("g=(%-?%d+)")
                    if cg then e.clickG = tonumber(cg) end
                elseif cr then
                    local d = line:match("d=(%a+)")
                    local ch = line:match("ch=([%a_]+)")
                    if d and x then
                        e.corners[#e.corners + 1] = {
                            grav = d, chan = ch or "", txt = txt or "",
                            x = tonumber(x), y = tonumber(y),
                            w = tonumber(w) or 0, h = tonumber(h) or 0,
                        }
                        if d == "TOP" and not e.top then e.top = txt end
                        if d == "BOTTOM" and not e.bottom then e.bottom = txt end
                    end
                end
            end
        end
    end
    if maxSeq <= 0 then return nil end
    -- 【r27.5】按区域拆两组，各自按原始遍历顺序连续重编号：
    -- makeKeyView 按 seq=1..N 对齐键盘 rows；若工具栏键混进来会让 seq 错位、角标串到键盘。
    -- keys/n 仍是键盘组（消费端无需改），另附 toolbar/KEYBOARD 组供工具栏预览用。
    local kbKeys, tbKeys, all = {}, {}, {}
    for i = 1, maxSeq do
        local e = keys[i] or { label = nil, top = nil, bottom = nil, corners = {}, region = "KEYBOARD" }
        all[i] = e
        if e.region == "TOOLBAR" then
            tbKeys[#tbKeys + 1] = e
        else
            kbKeys[#kbKeys + 1] = e
        end
    end
    if #kbKeys == 0 then return nil end   -- 纯工具栏 dump 无键盘数据 → 让回退路径生效
    -- 【r27.7】退化检测：真机 View 未 measure 时 box 宽高全 0，此时 KSCORNER 的
    -- xy = getLeft(0) + translation，只有 offset、缺 gravity 布局位置；拿它当绝对
    -- margins 会把所有角标整体错位。判定"全部键都未布局"= 退化 dump，交由调用方
    -- 拒绝用其坏坐标覆盖上一份健康快照。
    local laidOut = 0
    for _, k in ipairs(kbKeys) do
        if (k.bw or 0) > 0 and (k.bh or 0) > 0 then laidOut = laidOut + 1 end
    end
    return {
        keys = kbKeys, n = #kbKeys,
        keyboard = kbKeys, keyboardN = #kbKeys,
        toolbar = tbKeys, toolbarN = #tbKeys,
        all = all, allN = maxSeq,
        degenerate = (laidOut == 0),
    }
end

-- ===== 【权威文字源】把真机 root dump 解析成每个键实际显示的文字 =====
-- 桥接 dumpRootTexts() 已经能读到真机每个 TextView 的最终文本（键盘+工具栏+候选栏），
-- 这是"真机画什么"的权威来源。此前工具仍从 kbdEnv 的 click/long_click/hint 事件推导
-- 文字，导致 L/Z 上标丢失、g 键 ▼ 反复出错。此函数把 dump 文本切成键列表，供预览优先
-- 采用真机文字（布局/尺寸/背景仍走 kbdEnv，符合用户"文字从 dump 取、布局用 kbdEnv"）。
--
-- 解析规则（已用真实 dump 验证：32 键，L=; Z=- @₂ ※ 全部正确）：
--   · 键锚点 = [KEYBOARD] 区 + 缩进恰为 15 + "@0,0" + 宽 w>0；其文本 = 该键主标签。
--   · 角标 = 上一锚点之后、本锚点(含)之前的所有行；只看缩进 17 的 TextView/TightTextView：
--       - y < 40（贴近键顶）→ 上标（long_click / 上方 swipe）
--       - y > 90（贴近键底）→ 下标（hint / 下方 swipe）
--       - 其余 y（居中，通常是主标签 mClick 本身，缩进17）→ 忽略，主标签以锚点为准。
--   · [IMG] 与 [TXT] 一视同仁取文本（如 g 键 ▼ 是 [IMG]，文本就是 "▼"）。
-- 返回 { keys = { [1..n]={label=..., top=..., bottom=...}, ... }, n=n } 或 nil。
function parseRootDumpToKeys(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local recs = {}
    for line in raw:gmatch("[^\n]+") do
        if line:find("[KEYBOARD]", 1, true) then
            -- 格式: [KEYBOARD]<缩进>(TightTextView|TextView)@x,y WxH [IMG|TXT] = [文本] [tr=(tx,ty)]
            -- 注意：Lua pattern 不支持 `|` 交替，用 [Tight]*TextView 同时匹配 TextView / TightTextView。
            -- 贪婪的 (.*)%] 会吞掉行尾，所以 tr 必须单独从整行里再匹配一次。
            local ind, cls, x, y, w, h, typ, txt =
                line:match("%[KEYBOARD%](%s*)([Tight]*TextView)@(%d+),(%d+)%s+(%d+)x(%d+)%s+%[(%a+)%]%s*=%s*%[(.*)%]")
            if ind then
                -- 【r25】解析桥接新输出的 translation：真机角标最终视觉位置 =
                -- getTop + translationY。老主题靠 offset_y 定位的角标，getTop 可能贴顶(0)，
                -- 只有叠加 ty 才是真机真实位置。捕获允许负数（offset 可为负）。
                local tx, ty = 0, 0
                local tsx, tsy = line:match("tr=%((%-?%d+),(%-?%d+)%)")
                if tsx then tx, ty = tonumber(tsx) or 0, tonumber(tsy) or 0 end
                recs[#recs + 1] = {
                    ind = #ind, cls = cls, x = tonumber(x) or 0, y = tonumber(y) or 0,
                    w = tonumber(w) or 0, h = tonumber(h) or 0, typ = typ, txt = txt or "",
                    tx = tx, ty = ty,
                    -- 最终视觉坐标（相对 keyRoot），供角标直接绝对定位。
                    vx = (tonumber(x) or 0) + tx, vy = (tonumber(y) or 0) + ty,
                }
            end
        end
    end
    if #recs == 0 then return nil end
    -- 【r26 真根因】桥接 walkView 的 pad(depth) 每级 2 个空格（偶数：0/2/4/6...），
    -- 而旧代码硬编码 ind==15 / ind==17（奇数）—— anchors 永远为空 → liveN=0。
    -- 桥接 dump 实测 kb=106/tv=119/len=8113，真机数据一直都在，全被这两行挡在门外。
    -- 改为结构识别：@0,0 即键主标签锚点（主标签 MATCH_PARENT keyRoot，左上角），与缩进无关。
    -- 注意不能加 `and r.w > 0`：占位/隐藏键锚点是 "@0,0 0x0"，同样是键盘真实格子。
    local anchors = {}
    for i, r in ipairs(recs) do
        if r.x == 0 and r.y == 0 then anchors[#anchors + 1] = i end
    end
    if #anchors == 0 then return nil end
    local keys = {}
    for ai, aiPos in ipairs(anchors) do
        local startPos = (ai > 1) and (anchors[ai - 1] + 1) or 1
        -- 主标签：优先取缩进17、y 落在主标签带(25..50)的普通 TextView，没有再回退锚点文本。
        -- 换主题后主标签 y 可能整体偏移（该主题数字键 y=30 仍在带内，这里再补相对兜底）。
        local k = { label = nil, top = nil, bottom = nil, corners = {} }
        -- corners 元素: {grav="TOP/BOTTOM/LEFT/RIGHT", txt, x, y, w, h}
        -- 键包围盒：优先锚点 w/h；锚点 0x0 时用本键缩进17子 view 的并集兜底。
        -- 方向一律用【相对键宽/高的比例】判，不再写死像素阈值：
        -- 真机一次 dump 里数字键 RIGHT 角标 left=81（键宽约116），旧阈值 x>=95 不成立 →
        -- 角标被当成主标签邻项丢弃，回退成上次键盘文字；换主题/换分辨率都会踩到。
        local kW, kH = tonumber(recs[aiPos].w) or 0, tonumber(recs[aiPos].h) or 0
        -- 【r26】锚点缩进（桥接 pad 每级 2 空格）。角标 = 比锚点更深一层的行。
        -- 不再硬编码 17——新桥接 pad(depth) 是偶数缩进，17 永远匹配不上。
        local anchorInd = recs[aiPos].ind or 0
        local cand = {}
        for p = startPos, aiPos do
            local r = recs[p]
            if p ~= aiPos and r.ind > anchorInd then
                if r.x + r.w > kW then kW = r.x + r.w end
                if r.y + r.h > kH then kH = r.y + r.h end
                if r.txt ~= "" then cand[#cand + 1] = { p = p, r = r } end
            end
        end
        local function cxOf(r) return kW > 0 and (r.x + r.w / 2) / kW or 0.5 end
        local function cyOf(r) return kH > 0 and (r.y + r.h / 2) / kH or 0.5 end
        -- 【r26】主标签 = 锚点行(@0,0)自身的文本。真机主标签是 MATCH_PARENT 铺满 keyRoot
        -- 的那个 TextView，dump 里它就在锚点@0,0 上；角标都在锚点之前(更深缩进)。
        -- 旧逻辑从更深层 TextView 里挑"最居中"的，会把左滑角标(如 ¹ @x=4)误当主标签。
        local labelPos = nil
        k.label = recs[aiPos].txt
        -- 锚点文本为空(0x0 占位键)时，才退而求其次从角标里挑一个居中的普通 TextView。
        if not k.label or k.label == "" then
            local bestD = math.huge
            for _, e in ipairs(cand) do
                local r = e.r
                if r.cls == "TextView" then
                    local d = math.abs(cxOf(r) - 0.5) + math.abs(cyOf(r) - 0.5)
                    if d < bestD then bestD = d; labelPos = e.p; k.label = r.txt end
                end
            end
        end
        for _, e in ipairs(cand) do
            local r = e.r
            if e.p ~= labelPos then
                -- TightTextView 真机只用于上/下滑角标、long_click、hint（上下方向），
                -- 普通 TextView 为左右滑角标。优先按类分流，再用相对比例定方向。
                local grav = nil
                local cx, cy = cxOf(r), cyOf(r)
                if r.cls == "TightTextView" then
                    if cy < 0.5 then grav = "TOP" else grav = "BOTTOM" end
                else
                    if cx < 0.3 then grav = "LEFT"
                    elseif cx > 0.7 then grav = "RIGHT"
                    elseif cy < 0.32 then grav = "TOP"
                    elseif cy > 0.68 then grav = "BOTTOM" end
                end
                if grav then
                    -- 【r25】角标坐标用"布局坐标 + translation"的最终视觉位置，
                    -- 与真机屏幕一致。offset_y 定位的角标靠这里补回位移。
                    k.corners[#k.corners + 1] = {
                        grav = grav, txt = r.txt,
                        x = r.vx or r.x, y = r.vy or r.y,
                        w = r.w, h = r.h,
                    }
                    -- top/bottom 保留第一个作为兼容回退（旧逻辑用）
                    if grav == "TOP" and not k.top then k.top = r.txt end
                    if grav == "BOTTOM" and not k.bottom then k.bottom = r.txt end
                end
            end
        end
        keys[#keys + 1] = k
    end
    -- 【r27.7】退化检测（同结构化路径）：所有 rec 宽高都为 0 = 真机 View 未布局，
    -- 此时锚点/@0,0 坐标全无意义，交由 applyLiveFromRaw 拒绝用其覆盖健康快照。
    local laidOut = 0
    for _, rr in ipairs(recs) do
        if (rr.w or 0) > 0 and (rr.h or 0) > 0 then laidOut = laidOut + 1 end
    end
    return { keys = keys, n = #keys, degenerate = (laidOut == 0) }
end

-- 【真机文字源】统一入口：解析任意一段真机 root dump → 写全局缓存 → 重渲染预览。
-- 真正刷新预览（此前只有延迟回调做解析，而它常常不执行，导致有 dump 无 LiveText）。
function applyLiveFromRaw(raw, noRender)
    local s = tostring(raw)
    -- 【r27】首选结构化段（Java 按 KeyView 树导出，方向/坐标/文本全是权威值）。
    local parsed = nil
    local ks = s:find("===== 结构化 =====", 1, true)
    local kt = s:find("===== 工具自渲染 =====", 1, true)
    if ks and kt and kt > ks then
        parsed = parseKeyStructure(s:sub(ks, kt - 1))
    end
    -- 结构化不可用（旧 APK / 解析失败）→ 回退旧的扁平缩进 dump 解析。
    if not parsed or parsed.n <= 0 then
        local a = s:find("===== 真机 root =====", 1, true)
        local b = s:find("===== 工具自渲染 =====", 1, true)
        local bs = s:find("===== 结构化 =====", 1, true)
        if bs and (not b or bs < b) then b = bs end   -- 排除结构化段，只留真机扁平 dump
        local dumpPart = (a and b and b > a) and s:sub(a, b - 1) or s
        parsed = parseRootDumpToKeys(dumpPart)
    end
    if not parsed or parsed.n <= 0 then
        -- 【r27.6 根因修复】空 dump 绝不能再清空已经拿到的权威快照。
        -- 真机键盘在收起动画 / 候选栏切换 / 服务重建瞬间，dumpKeyboardStructure
        -- 会返回 ERR 或 n=0（root 暂时读不到完整的 KeyView 树）。旧代码在这里把
        -- liveKeyTexts 清成 nil → 所有角标瞬间回退到 offset 推导 → 用户看到
        -- "刚打开一瞬间正常，随后全部移动到错误位置，且再也不恢复"
        -- （因为 _autoViewDiagDone 之后没有第二次成功 dump 能把数据填回来）。
        -- 现在：一旦拿到过权威数据就一直保留，直到换键盘/主题由 loadKeyboard 主动失效。
        -- 仅当从未成功过（liveKeyTexts 仍为 nil）才保持 nil，让启动重试逻辑继续。
        return liveKeyTexts
    end
    -- 【r27.7 根因修复】退化 dump（真机 View 未 measure，box 宽高全 0）不覆盖健康快照。
    -- 工具全屏时输入法键盘被遮挡，getLeft/getTop/宽高全 0，KSCORNER 只剩 translation、
    -- 丢了 gravity 布局位置；用它当绝对坐标会让所有角标整体错位 —— 这正是
    -- "刚打开正常（有布局）→ 随后全部移动（被遮挡后 dump 到 0x0）"的直接成因。
    if parsed.degenerate and liveKeyTexts and not liveKeyTexts.degenerate then
        return liveKeyTexts
    end
    -- 退化 dump 且无健康快照可用时：保留它的【文字】（比事件推导准），但清空角标坐标，
    -- 让 makeKeyView 走 gravity+offset 推导（dump 的 x=getLeft(0)+translation 缺
    -- gravity 布局位置，绝对定位必错；推导至少保留主题自己的 gravity/offset 语义）。
    if parsed.degenerate then
        for _, k in ipairs(parsed.keys or {}) do
            for _, c in ipairs(k.corners or {}) do c.x, c.y = nil, nil end
            k.clickX, k.clickY = nil, nil
        end
    end
    -- 主标签匹配在 makeKeyView 内逐键兜底，这里不再要求键数严格相等
    -- （dump 含 0x0 占位锚点，旧版 w>0 过滤出 31 键 vs 预览 44 键而整体放弃）。
    liveKeyTexts, liveKeyTextsN = parsed, parsed.n
    -- 【r27.5】把区域拆分结果写进可见诊断：kb=键盘组 tb=工具栏组。
    -- 下次 dump 看 [DIAG] KS kb=N tb=M，tb>0 即证明工具栏键已被单独分出、不再串进键盘。
    _G.__ksDiag = string.format("n=%d kb=%d tb=%d corners=%d",
        (parsed.allN or parsed.n), (parsed.keyboardN or parsed.n),
        (parsed.toolbarN or 0), (function()
            local c = 0
            for _, k in ipairs(parsed.all or parsed.keys or {}) do c = c + #(k.corners or {}) end
            return c
        end)())
    -- 【r27.41】noRender=true 时只填 liveKeyTexts、不触发重渲染。
    -- 用于"首帧前同步采集"：数据先就位，随后由 loadKeyboard 统一渲染一次，
    -- 消除旧逻辑"先静态渲染→dump 后再渲染"的二次渲染闪烁。
    if not noRender then pcall(renderPreview) end
    return parsed
end

-- 缓存：从最近一次真机 root dump 解析出的键文字（nil=不可用，回退 kbdEnv 推导）。
-- 【关键】必须是全局：唯一消费它的 makeKeyView 定义在本文件更早处（约 2437 行），
-- 若用 local 声明在此，渲染函数按 Lua 词法作用域只会看到全局 nil，永远读不到解析结果。
liveKeyTexts = nil
liveKeyTextsN = 0

-- 【r27.41 单次渲染】首帧前同步采集权威快照（只填 liveKeyTexts，不输出诊断、不渲染）。
-- 工具打开前真机键盘 View 已经渲染就绪，直接读 Java 桥接的结构化导出即可，
-- 不必像旧逻辑那样"先静态渲染一帧 → postDelayed 200ms dump → 再渲染一帧"。
-- 返回快照是否成功填入；失败保留 nil，让原逻辑的延迟兜底继续工作。
function grabLiveSnapshotSync()
    -- 只走结构化桥接：dumpKeyboardStructure 直接给每键权威文字/角标/坐标。
    local okBind, Bridge = pcall(function()
        return luajava.bindClass("com.osfans.trime.theme.ThemeDataBridge")
    end)
    if not okBind or not Bridge then return false end
    local ksRaw = ""
    if not pcall(function() ksRaw = Bridge.dumpKeyboardStructure() or "" end) then return false end
    if ksRaw == "" then return false end
    _G.__ksRaw = ksRaw
    local parsed = applyLiveFromRaw(
        "===== 结构化 =====\n" .. ksRaw .. "\n\n===== 工具自渲染 =====", true)
    return parsed ~= nil
end


-- 【已删除·错误数据源】曾用 Java 反射从 TrimeService.getInstance() 取 mRootInputView → globals。
-- 这混淆了"tool 的 this"与"输入法的 this"：tool 是 LuaActivity，拿到的 Service 实例未必是
-- 正在渲染的那个，且反射链路（getDeclaredField/混淆/未就绪）极不稳定。
-- 现统一由 Java 桥接 InputView.getCurrentKeyboardGlobals() 在编译期给出当前键盘 Globals，
-- 工具侧只读 ThemeDataBridge.snapshot().keyboard —— 见 readBridgeSnapshot / loadKeyboard。


-- ===== 键盘布局：绝不执行键盘脚本，只做纯静态解析 =====
-- 【已弃用·沙箱执行会闪退】曾尝试在安全沙箱里真正执行 qwerty36.lua 以还原动态 rows，
-- 但键盘脚本顶层就调用真机对象：import "…ThemeManager"、
-- PreferenceManager.getDefaultSharedPreferences(this)、sp.getString(...)。这些不是
-- "逃逸"，而是直接触碰真机 Java 对象，触发的 coercion error（got org.luaj.LuaTable）
-- 属于 JNI/native 层崩溃，Lua 的 pcall 挡不住 → 真机闪退。用户明确要求：针对真实键盘
-- 运行的函数不能都直接运行。因此键盘布局统一走 parseKeyboardStatic（抠 rows 字面量），
-- 解析不出来就回退 default 主题的 qwerty36 纯字面量布局（36 键），样式仍取自当前主题。

-- ===== 键盘布局静态解析（沙箱执行失败时的纯数据兜底） =====
-- 万象这类主题的键盘脚本（qwerty36.lua 等）会在顶层调用真机 Java 类：
--   import "com.osfans.trime.theme.ThemeManager"
--   PreferenceManager.getDefaultSharedPreferences(this)   -- 读真机偏好设置
-- 这些针对真实键盘的代码在预览沙箱里既无意义，又会触发 coercion error，
-- 甚至让输入法崩溃。关键结论：键盘脚本根本不该执行，只取它的纯数据布局。
-- 这里从源码文本里抠出 rows 字面量与标量元数据，在「只含基础库、未定义全局一律
-- 返回安全桩」的干净环境里求值——全程不触碰任何真机 Java 对象。
-- 静态解析的可信度检查。
-- rows 字面量里常出现 click=FUNC("q") / keys=allk[i].keys 这类调用或引用，
-- 在桩环境里它们会返回 table，于是「解析成功」但每个键的文字都是 table: 0x...
-- 渲染出来就是一片乱码 —— 这正是「键盘也不对」的来源。
-- 要求至少 70% 的键拿到字符串 click/label/text/key 才算可信，否则宁可不认。
function rowsLookReal(rows)
    if type(rows) ~= "table" then return false end
    local total, good = 0, 0
    for _, r in pairs(rows) do
        if type(r) == "table" and type(r.keys) == "table" then
            for _, kd in pairs(r.keys) do
                total = total + 1
                if type(kd) == "table" then
                    local v = kd.click or kd.label or kd.text or kd.key
                    if type(v) == "string" and v ~= "" then good = good + 1 end
                elseif type(kd) == "string" and kd ~= "" then
                    good = good + 1
                end
            end
        end
    end
    return total > 0 and (good / total) >= 0.7
end

function parseKeyboardStatic(path)
    local src = readFile(path)
    if not src then return nil end
    local out = {}
    local rowsLines = {}
    local n = 0
    for line in tostring(src):gmatch("([^\n]*)") do
        n = n + 1
        if line:find("rows", 1, true) and #rowsLines < 6 then
            rowsLines[#rowsLines + 1] = n .. ": " .. (line:gsub("^%s+", ""))
        end
    end
    -- 标量元数据（键盘名/键宽/键高/锁定），仅在字面量存在时取；先去注释，避免注释里的示例 name= 被当真值
    local metaSrc = stripLuaComments(src)
    out.name = metaSrc:match("name%s*=%s*[\"']([^\"']*)[\"']")
    out.key_width = tonumber((src:match("key_width%s*=%s*(%d+%.?%d*)")))
    out.key_height = tonumber((src:match("key_height%s*=%s*(%d+%.?%d*)")))
    local short = path:match("([^/]+)$") or path
    local function fail(reason)
        if not kbdParseDiag[short] then
            kbdParseDiag[short] = reason .. (#rowsLines > 0 and ("\n" .. table.concat(rowsLines, "\n")) or "\n（未找到含 rows 的行）")
        end
        return nil
    end
    -- rows = { ... }：花括号配对截取整个字面量块
    local s = src:find("rows%s*=%s*")
    if not s then return fail("未找到 rows = 字面量赋值") end
    local bs = src:find("{", s)
    if not bs then return fail("rows = 后不是 { 字面量（疑似动态生成）") end
    local depth, be = 0, nil
    for i = bs, #src do
        local ch = src:sub(i, i)
        if ch == "{" then depth = depth + 1
        elseif ch == "}" then
            depth = depth - 1
            if depth == 0 then be = i break end
        end
    end
    if not be then return fail("rows 字面量花括号不配对") end
    local code = "return " .. src:sub(bs, be)
    -- 干净 env：基础库 + 元表 __index 让任何未定义标识符（函数/类/变量引用）
    -- 返回安全桩，保证字面量里形如 click=FUNC("q") 的调用也落到桩上，绝不执行真机代码。
    local clean = {}
    clean._G = clean
    setmetatable(clean, {
        __index = function(t, k)
            if type(k) ~= "string" or k == "" then return nil end
            local v = makeSafeStub()
            rawset(t, k, v)
            return v
        end
    })
    clean.type = type; clean.pairs = pairs; clean.ipairs = ipairs
    clean.tostring = tostring; clean.tonumber = tonumber
    clean.math = math; clean.table = table; clean.string = string
    clean.unpack = unpack or table.unpack; clean.print = print; clean.pcall = pcall
    clean.select = select
    local f
    if load then
        local ok, g = pcall(load, code, "=rows", "t", clean)
        if ok and g then f = g end
    end
    if not f and loadstring then f = loadstring(code) end
    if not f then return fail("rows 字面量编译失败") end
    local ok, rows = pcall(f)
    if not ok or type(rows) ~= "table" or #rows == 0 then
        return fail("rows 字面量求值失败或为空（非数组型）")
    end
    if not rowsLookReal(rows) then
        return fail("rows 字面量里的键是动态生成的（调用桩/引用），静态解析不可信")
    end
    out.rows = rows
    return out
end

function fillBuiltinKeyboard(out)
    out.rows = {
        {keys = {{click="q"},{click="w"},{click="e"},{click="r"},{click="t"},{click="y"},{click="u"},{click="i"},{click="o"},{click="p"}}},
        {keys = {{click="a"},{click="s"},{click="d"},{click="f"},{click="g"},{click="h"},{click="j"},{click="k"},{click="l"}}},
        {keys = {{click="z"},{click="x"},{click="c"},{click="v"},{click="b"},{click="n"},{click="m"}}},
    }
    if out.key_width == nil then out.key_width = 10 end
    if out.key_height == nil then out.key_height = 22 end
    return out
end

-- ===== 主题根静态解析（桥接不可用时的降级，彻底不执行主题根脚本）=====
-- 主题根 main.lua 里的 name/style/keyboard/preset_keys 都是纯字面量赋值，
-- 直接抠出来即可，不必在沙箱里执行那堆依赖真机环境的函数（41 行 attempt to call nil
-- 正是这类函数）。这样即便没编译桥接 APK，装了新版工具也不会再崩这个错误。
-- 从主题根 main.lua 中取出 get_keyboard 函数本体，在干净环境里定义出来。
-- 【为什么必须这么做】"当前键盘"完全由主题自己的 get_keyboard(id, alphabet) 决定：
--   有的主题按 id 直接返回，有的按 alphabet 判中英/数字，有的读别的全局变量。
--   任何"复刻分支"的写法都会在下一个主题上失效；唯一通用的办法就是把函数原样执行、
--   用与真机相同的入参调用它。
function extractThemeGetKeyboard(src, themeEnv)
    if type(src) ~= "string" then return nil end
    -- 找函数定义（跳过注释行里的示例代码：主题里常有 "-- function get_keyboard(...)" 说明）
    local function findDef(pat)
        local p = 1
        while true do
            local h = src:find(pat, p)
            if not h then return nil end
            local ls = src:sub(1, h):match(".*()\n") or 0
            if not src:sub(ls + 1, h - 1):find("%-%-") then return h end
            p = h + 1
        end
    end
    local head = findDef("function%s+get_keyboard%s*%(")
    if not head then
        -- 兼容 get_keyboard = function(...) 写法
        head = findDef("get_keyboard%s*=%s*function%s*%(")
    end
    if not head then return nil end

    -- 从函数头开始做块计数，找到配对的 end（function/if/do 开块，end 闭块）
    local pos, depth, body = head, 0, nil
    local len = #src
    while pos <= len do
        local nl = src:find("\n", pos, true) or (len + 1)
        local line = src:sub(pos, nl - 1)
        line = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
        for w in line:gmatch("%a+") do
            if w == "function" or w == "if" or w == "do" then depth = depth + 1
            elseif w == "end" then depth = depth - 1 end
        end
        if depth <= 0 then body = src:sub(head, nl - 1) break end
        pos = nl + 1
    end
    if not body then return nil end

    -- 干净环境：标准库保留，主题声明变量注入，其余未知全局给空串（避免 nil 索引/调用崩溃）
    local clean = {}
    clean._G = clean
    clean.string, clean.table, clean.math = string, table, math
    clean.type, clean.tostring, clean.tonumber = type, tostring, tonumber
    clean.pairs, clean.ipairs, clean.select = pairs, ipairs, select
    if type(themeEnv) == "table" then
        for _, k in ipairs({ "keyboard", "name", "style" }) do
            if themeEnv[k] ~= nil then clean[k] = themeEnv[k] end
        end
    end
    setmetatable(clean, { __index = function(_, k)
        if k == "keyboard" then return (type(themeEnv) == "table" and themeEnv.keyboard) or "" end
        return ""
    end })

    local loader = load or loadstring
    if not loader then return nil end
    local ok, fn = pcall(loader, body, "=get_keyboard", "t", clean)
    if not ok or type(fn) ~= "function" then return nil end
    if not pcall(fn) then return nil end
    local gk = rawget(clean, "get_keyboard")
    return type(gk) == "function" and gk or nil
end

function parseThemeRootStatic(path, fallbackName)
    local src = readFile(path)
    local out = {}
    out.name = fallbackName
    if not src then return out end
    local metaSrc = stripLuaComments(src)
    out.name = metaSrc:match("name%s*=%s*[\"']([^\"']*)[\"']") or fallbackName
    out.style = metaSrc:match("style%s*=%s*[\"']([^\"']*)[\"']")
    out.keyboard = metaSrc:match("keyboard%s*=%s*[\"']([^\"']*)[\"']")
    -- get_keyboard(id, alphabet)：当前键盘的真正决策函数。不同主题实现不同，
    -- 唯一通用做法就是把它原样取出来、用真机同样的入参求值，而不是复刻分支。
    out.get_keyboard = extractThemeGetKeyboard(src, out)
    -- preset_keys = { ... }：花括号配对截取，在干净环境求值（函数引用落成安全桩）
    local s = src:find("preset_keys%s*=%s*")
    if s then
        local bs = src:find("{", s)
        if bs then
            local depth, be = 0, nil
            for i = bs, #src do
                local ch = src:sub(i, i)
                if ch == "{" then depth = depth + 1
                elseif ch == "}" then
                    depth = depth - 1
                    if depth == 0 then be = i break end
                end
            end
            if be then
                local clean = {}
                clean._G = clean
                setmetatable(clean, { __index = function(t, k)
                    if type(k) ~= "string" or k == "" then return nil end
                    local v = makeSafeStub(); rawset(t, k, v); return v
                end})
                clean.type = type; clean.pairs = pairs; clean.ipairs = ipairs
                clean.tostring = tostring; clean.tonumber = tonumber
                clean.string = string; clean.table = table; clean.math = math
                local fn
                if load then
                    local ok, g = pcall(load, "return " .. src:sub(bs, be), "=preset_keys", "t", clean)
                    if ok and g then fn = g end
                end
                if fn then
                    local ok, t = pcall(fn)
                    if ok and type(t) == "table" then out.preset_keys = t end
                end
            end
        end
    end
    return out
end

-- 脚本求值兜底只跑一次（桥接不可用 + 静态解析失败时才触发）
local _scriptKbdRetry = false

function loadKeyboard(kbdFile, bridgeKbd, opts)
    if not themeDir then return end
    opts = type(opts) == "table" and opts or {}
    -- 【启动路径禁止执行键盘脚本】
    -- parseKeyboardData 会在 clean 环境里跑完整份键盘脚本（require 链、循环、动态 rows）。
    -- 万象这类主题的脚本在 LuaJ 下可能要几百毫秒到数秒，遇到死循环就永远不返回 ——
    -- 主线程被占住，工具白屏 + 输入法一起 ANR，用户看到的就是「打开就卡死」。
    -- 所以默认只做纯字面量静态解析；只有用户手动点选键盘时才放开脚本求值。
    local allowScript = opts.allowScript == true and opts.noScript ~= true
    local oldFile, oldEnv = currentKbdFile, kbdEnv   -- 解析失败时沿用同一键盘的旧布局
    clearOwnStyles()         -- 换键盘：单键专属样式绑在旧键盘行列上，一并作废
    -- 【r27.6】换键盘时主动失效上一把键盘的权威快照。
    -- 空 dump 不再清空快照（见 applyLiveFromRaw），所以换键盘必须由这里负责失效，
    -- 否则新键盘的 seq 会串用旧键盘的 dumpX/dumpY/文字，角标照样错位。
    -- loadTheme 也调用本函数，换主题一并失效。
    liveKeyTexts, liveKeyTextsN = nil, 0
    -- 【r27.41 单次渲染】首帧渲染前同步采集真机权威快照：工具打开前真机键盘 View
    -- 已渲染就绪，直接读 Java 桥接结构化导出（只填数据、不渲染）。这样下面两条
    -- 路径的首帧 renderPreview 都能一次成型用上桥接文字，不再"先静态→dump→再渲染"。
    -- 采集失败保留 nil，仍由文件尾部的延迟 dump 兜底，不影响老降级路径。
    pcall(grabLiveSnapshotSync)
    liveTextsDisabled = false -- 重新加载键盘 = 全新未编辑状态，恢复真机文字快照显示
    liveTextsDisabledKeys = {} -- 清空逐键停用集合：换键盘后所有键恢复真机文字快照
    -- 换键盘后必须重新 dump 才能把权威快照填回；否则门控会让 dump 永远只跑一次，
    -- 快照被清空后再无机会恢复 → 角标永久回退 offset 推导（错位）。
    _autoViewDiagDone = false
    _fontCache = {}          -- 换主题/键盘后字体可能不同，清空缓存让首次渲染重读一次
    tfCache = {}             -- Typeface 也按路径缓存，换主题后旧路径可能已被删/替换
    _iconFont, _iconFontTried = nil, false  -- 图标字体兜底同样要重新找
    currentKbdFile = kbdFile
    local kbdPath = themeDir .. "/keyboards/" .. kbdFile
    kbdFallbackNote = nil
    kbdSourceNote = nil
    -- 【首选】Java 桥接的真实键盘数据（输入法正在用的完整布局，含动态 rows）
    if bridgeKbd and keyboardRowsOK(bridgeKbd) then
        kbdEnv = bridgeKbd
        kbdSourceNote = "[键盘配置来源] Java 桥接真实数据（同进程输入法当前键盘，动态 rows 已还原）"
        kbdFallbackNote = "键盘布局取自输入法当前键盘（Java 桥接）"
        kbdEdits, kbdOps = {}, {}
        selKeyR, selKeyK = nil, nil
        sandboxLastError = nil
        stKbd = "键盘：" .. ((kbdEnv and kbdEnv.name) or kbdFile:gsub("%.lua$", "")); refreshStatus()
        renderPreview()
        return
    end
    -- 【首选·通用方案】在"完全隔离、零真机对象"的 clean 万能桩环境里求值键盘脚本的数据部分：
    -- require"keys"/"qwerty36" 链会加载纯数据模块、拼出依赖 allk 的动态 rows；
    -- 所有 import/PreferenceManager/sp.edit/ThemeManager.setStyle 等真机调用全落到纯 Lua 桩上
    -- no-op，物理上不可能 coercion 崩溃。用户确认 tool 与输入法不同 Lua 实例，不污染输入法。
    local kbd, dataErr = nil, nil
    if allowScript then
        local okData, d = pcall(parseKeyboardData, kbdPath)
        if okData and d and keyboardRowsOK(d) then
            kbd = d
            kbdSourceNote = "[键盘配置来源] 通用求值键盘脚本数据（clean 隔离环境 + 共享 require，动态 rows 已还原）"
        else
            dataErr = (not okData) and tostring(d) or (d and "rows 未构造" or "读取失败")
        end
    else
        dataErr = "启动阶段跳过脚本求值（只做静态解析）"
    end
    -- 【兜底·纯静态解析】只抠 rows 字面量（不执行任何脚本代码）
    if not (kbd and keyboardRowsOK(kbd)) then
        kbd = parseKeyboardStatic(kbdPath)
        if kbd and keyboardRowsOK(kbd) then
            kbdSourceNote = "[键盘配置来源] 静态解析（抠 rows 字面量）"
                .. (allowScript and ("；脚本求值失败：" .. tostring(dataErr))
                             or "；启动阶段未执行脚本")
        end
    end
    -- 解析失败但内存里已有同一键盘的布局：沿用它，别掉到默认 qwerty36
    if not (kbd and keyboardRowsOK(kbd)) and oldFile == kbdFile and keyboardRowsOK(oldEnv) then
        kbd = oldEnv
        kbdSourceNote = "[键盘配置来源] 本次解析失败（" .. tostring(dataErr) .. "），沿用内存中同一键盘的布局"
    end
    if kbd and keyboardRowsOK(kbd) then
        kbdEnv = kbd
        kbdFallbackNote = "键盘布局取自 " .. kbdFile
    else
        kbdSourceNote = "[键盘配置来源] 静态解析未拿到 rows，回退内置/默认键盘"

        -- 桥接不可用 + 静态解析失败时，脚本求值是唯一能还原动态 rows 的路。
        -- 但绝不在这里同步执行：推迟到首帧之后跑一次，先让界面用内置键盘出来，
        -- 否则脚本一慢就是白屏/ANR（同进程的输入法一起被杀）。
        if not allowScript and not (bridgeKbd and keyboardRowsOK(bridgeKbd))
            and not _scriptKbdRetry then
            _scriptKbdRetry = true
            local f = kbdFile
            uiHandler.postDelayed(function()
                pcall(loadKeyboard, f, nil, { allowScript = true })
            end, 400)
        end

        -- 回退：优先 default 主题的 qwerty36（纯字面量，能给出正确的 36 键布局），
        -- 避免先撞上当前主题的 qwerty27 又变回 27 键。样式/配色仍来自当前主题。
        local root = getThemesRoot()
        local function tryStatic(path, tag)
            if not path or not fileExists(path) then return false end
            local e = parseKeyboardStatic(path)
            if e and keyboardRowsOK(e) then
                kbdEnv, kbdFallbackNote = e, "键盘回退到 " .. tag .. "（静态解析）"
                return true
            end
            return false
        end
        local got = false
        if root then got = tryStatic(root .. "/default/keyboards/qwerty36.lua", "default/qwerty36.lua") end
        if not got then
            for _, cand in ipairs({"qwerty36.lua", "qwerty26.lua", "qwerty27.lua", "qwerty.lua", "ascii.lua"}) do
                if cand ~= kbdFile and tryStatic(themeDir .. "/keyboards/" .. cand, cand) then got = true break end
            end
        end
        if not got and root then
            if not tryStatic(root .. "/default/keyboards/" .. kbdFile, "default/" .. kbdFile) then
                tryStatic(root .. "/default/keyboards/qwerty27.lua", "default/qwerty27.lua")
            end
        end
        if not keyboardRowsOK(kbdEnv) then
            kbdEnv = fillBuiltinKeyboard(kbdEnv or {})
            kbdFallbackNote = "键盘布局使用内置极简 QWERTY（主题布局无法解析）"
        end
    end
    -- 沙箱执行键盘脚本可能残留补值错误记录，键盘布局已就绪后清掉，避免误报成样式错误
    sandboxLastError = nil
    kbdEdits, kbdOps = {}, {}
    selKeyR, selKeyK = nil, nil
    stKbd = "键盘：" .. ((kbdEnv and kbdEnv.name) or kbdFile:gsub("%.lua$", "")); refreshStatus()
    renderPreview()
    -- 【r27.6】每次加载键盘都重新 dump（换键盘后快照被清空，必须重新填回）。
    -- 延迟 1.5s 等真机键盘 View 渲染就绪；空 dump（键盘动画/收起瞬间）时有限重试，
    -- 确保权威快照最终一定能填上，否则角标会永久回退 offset 推导（错位）。
    _autoViewDiagDone = true
    -- 【r27.41 单次渲染】首帧前已同步采集到权威快照 → 这段 1.5s 的 dump 完全跳过：
    -- 它内部的 dumpKbViewTexts + applyLiveFromRaw 会再触发一次全量渲染，是二次渲染的
    -- 元凶之一。只有同步采集失败（真机 View 当时还没就绪、快照仍为 nil）才保留原重试。
    if liveKeyTexts ~= nil then return end
    local dumpTry = { 0 }
    local function grabLiveSnapshot()
        dumpTry[1] = dumpTry[1] + 1
        local okr, r = pcall(dumpKbViewTexts)
        if not okr then r = "dumpKbViewTexts 异常：" .. tostring(r) end
        local okp, parsed = pcall(applyLiveFromRaw, r)
        -- applyLiveFromRaw 成功时返回 parsed 表；空 dump 返回 nil（保留旧快照）。
        -- 首次拿不到（liveKeyTexts 仍为 nil）就再试两次，间隔递减。
        if not okp or parsed == nil or liveKeyTexts == nil then
            if dumpTry[1] < 4 then
                uiHandler.postDelayed(grabLiveSnapshot, 700)
            end
        end
    end
    uiHandler.postDelayed(grabLiveSnapshot, 1500)
end

function loadVariant(variant, bridgeStyle)
    if not themeDir then return end
    clearOwnStyles()         -- 换配色：专属样式表取自旧 styleEnv，一并作废
    -- 配色目录也参与字体查找：字体名可能同名但指向不同文件的字体，索引与 Typeface 缓存一起作废
    resetFontCaches()
    currentVariant = variant
    -- 【首选】Java 桥接的真实配色数据（输入法正在用的），优先于沙箱执行
    if bridgeStyle and type(bridgeStyle) == "table" and next(bridgeStyle) ~= nil then
        styleDir = themeDir .. "/styles/" .. variant
        styleEnv = bridgeStyle
    elseif variant == "（主题 main.lua 内嵌样式）" then
        styleDir, styleEnv = themeDir, themeEnv
    else
        styleDir = themeDir .. "/styles/" .. variant
        styleEnv = sandboxLoad(styleDir .. "/main.lua", themeEnv)
    end
    -- 用于确认偏移到底定义在哪个 style、桥接是否导出、字段名是否正确。
    if not _offsetScanDone then
        _offsetScanDone = true
        pcall(function()
            local hits = {}
            local seen = {}
            local function walk(t, prefix, depth)
                if type(t) ~= "table" or depth > 8 or seen[t] then return end
                seen[t] = true
                for k, v in pairs(t) do
                    if type(k) == "string" then
                        local p = prefix == "" and k or (prefix .. "." .. k)
                        if k:lower():find("offset", 1, true) or k:lower():find("translation", 1, true) then
                            if type(v) ~= "table" then
                                hits[#hits + 1] = p .. "=" .. tostring(v)
                            end
                        end
                        if type(v) == "table" then walk(v, p, depth + 1) end
                    end
                end
            end
            if type(styleEnv) == "table" then walk(styleEnv, "", 0) end
            -- 工具实际取值路径的结果（与扫描对比：数据有值但这里 nil = 路径错）
            local probe = {}
            for _, p in ipairs({
                "key.offset_x", "key.offset_y",
                "key.hint.offset_x", "key.hint.offset_y",
                "key.long_click.offset_x", "key.long_click.offset_y",
                "key.click.offset_x", "key.click.offset_y",
            }) do
                probe[#probe + 1] = p .. "=" .. tostring(getValue(p))
            end
        end)
    end
    styleEdits = {}
    if not styleEnv then toast("配色加载失败：" .. variant) return end
    stVariant = "配色：" .. variant; refreshStatus()
    if sandboxLastError then
        logErr("样式加载", sandboxLastError)
        sandboxLastError = nil
    end
    renderPreview()
end

function loadTheme(name)
    local oldTheme, oldKbd = currentTheme, currentKbdFile  -- 重载同一主题（如"放弃修改"）时用于保持原键盘
    clearOwnStyles()         -- 换主题：专属样式一并作废（loadVariant 也会清，这里保底）
    resetFontCaches()        -- 主题目录换了，字体索引/Typeface/图标兜底全部作废
    _tbDiagDone = false      -- 工具栏字体诊断每个主题打一次，换主题后重新记录
    _kbdCandCache = {}       -- 键盘目录也换了，按显示名反查文件的缓存一并作废
    _scriptKbdRetry = false  -- 换主题后允许再做一次「延迟脚本求值」兜底
    local rootDir = getThemesRoot()
    currentTheme = name
    -- 【首选】读取 Java 桥接的真实主题数据（同进程输入法已加载好的）。
    -- 切换主题时才校验桥接主题名；同主题重载直接信任桥接（主题名与目录名可能不同名，
    -- 校验会把"放弃修改"这类重载误判成别人的数据而丢弃，键盘随即掉回默认 36 键）。
    bridgeData = readBridgeSnapshot()
    if bridgeData and type(bridgeData.meta) == "table" and oldTheme ~= name then
        local bt = bridgeData.meta.theme
        if type(bt) == "string" and bt ~= "" and bt ~= name then
            bridgeData = nil  -- 桥接数据属于别的主题，本次不用
        end
    end
    -- 桥接拿到输入法真实数据即可用：主题根/style/键盘三套脚本全部跳过，零补洞、零 native。
    local bridgeUsable = (bridgeData ~= nil)
    requiredModules = {}   -- 每次加载主题重置 require 链记录
    autoInjectedGlobals = {}
    diagSourceLines = {}   -- 每次加载主题重置出错行源码记录
    kbdParseDiag = {}      -- 每次加载主题重置键盘解析诊断
    sandboxBlockedClasses = {}  -- 每次加载主题重置 Java 类拦截记录
    -- 主题目录：源码 API Config.getThemeDir(name) 为准，失败才用根目录拼接兜底
    do
        local okTD, td = pcall(function() return Config.getThemeDir(name) end)
        themeDir = (okTD and td) or (rootDir .. "/" .. name)
    end
    -- 主题根静态解析（不执行整份脚本），只为拿到 get_keyboard 与 keyboard= 声明。
    -- 这两项是"当前键盘"的决策依据，两种模式下都要有。
    local themeRootStatic = parseThemeRootStatic(themeDir .. "/main.lua", name)
    if bridgeUsable then
        -- ===== 桥接模式：主题根脚本不执行（真机环境残缺，跑了会 attempt to call nil）=====
        -- 但 get_keyboard 函数本体要取出来：键盘由它决定，桥接没给出文件名时靠它求值。
        themeEnv = {}
        local bm = type(bridgeData.meta) == "table" and bridgeData.meta or {}
        themeEnv.name = bm.theme or name
        themeEnv.style = bm.style
        themeEnv.keyboard = themeRootStatic.keyboard
        themeEnv.get_keyboard = themeRootStatic.get_keyboard
        -- 桥接 style 是输入法 style VM 的完整快照，并入影子 env 供 preset_keys 等顶层字段读取
        if type(bridgeData.style) == "table" then
            for k, v in pairs(bridgeData.style) do
                if themeEnv[k] == nil then themeEnv[k] = v end
            end
        end
        sandboxLastError = nil
    else
        -- ===== 桥接不可用降级：只用静态解析结果，绝不执行主题脚本 =====
        themeEnv = themeRootStatic
        sandboxLastError = nil
    end
    buildPresetKeys()
    buildLabelImgIndex()
    fontIndex = nil          -- 换了主题：字体索引作废，等真正用到字体时再建（懒加载）
    styleEdits, kbdEdits, kbdOps = {}, {}, {}
    dirtyCount = 0
    refreshDirty()
    if not themeEnv then toast("主题加载失败：" .. name) return end
    stTheme = "主题：" .. (themeEnv.name or name); refreshStatus()

    local variants = listVariants(name)
    -- 真机当前配色（用户实际选中的，含日夜模式）优先；找不到才退回主题默认值 / 第一个
    local defV = detectCurrentStyle(name, themeEnv.style)
    local chosen = nil
    for _, v0 in ipairs(variants) do if v0 == defV then chosen = v0 end end
    chosen = chosen or (variants[1] or "（主题 main.lua 内嵌样式）")
    -- 桥接配色 = 输入法当前真实配色，无条件优先（不再被 chosen 判断架空退回沙箱脚本）
    local bStyle = nil
    if bridgeUsable and type(bridgeData.style) == "table" and next(bridgeData.style) ~= nil then
        bStyle = bridgeData.style
        local bs = bridgeData.meta and bridgeData.meta.style
        if type(bs) == "string" and bs ~= "" then chosen = bs end
    end
    loadVariant(chosen, bStyle)

    local kbds = listKeyboards(name)
    -- 同主题重载：沿用用户当下正在看的键盘文件（"放弃修改"不该把键盘换掉）
    local prevKbd = nil
    if oldTheme == name and type(oldKbd) == "string" and oldKbd ~= ""
        and fileExists(themeDir .. "/keyboards/" .. oldKbd) then
        prevKbd = oldKbd
    end
    -- 当前键盘 = 主题 get_keyboard(设置里的键盘 id, 当前方案 alphabet) 的返回值。
    -- alphabet 必须是真的，否则按字母表选中英/数字布局的主题会判错。
    local activeFile, kbdReason = detectCurrentKeyboard(name, themeEnv, kbds, detectAlphabet())
    kbdSelectReason = kbdReason
    -- 桥接键盘 = 输入法当前真实键盘（36 键等），无条件优先，不再被 activeFile 判断架空。
    -- 旧逻辑里 activeFile 一旦判成 qwerty27，就把桥接的 36 键丢掉 → 数字键行列错位。
    local bKbd = nil
    if bridgeUsable and type(bridgeData.keyboard) == "table" and keyboardRowsOK(bridgeData.keyboard) then
        bKbd = bridgeData.keyboard
    elseif bridgeUsable then
        -- 桥接可用却没拿到键位：以前是静默退回解析脚本文件，然后键盘悄悄换了样子。
        -- 现在把原因写进判定依据，并在诊断里能看到（rows 为空 = 序列化被截断/键盘未加载）。
        local bk = bridgeData.keyboard
        local rn = (type(bk) == "table" and type(bk.rows) == "table") and rowsCount(bk.rows) or 0
        kbdSelectReason = (kbdSelectReason and (kbdSelectReason .. "；") or "")
            .. "桥接键位不可用（type=" .. type(bk) .. "，rows=" .. rn
            .. "，来源 " .. tostring(bridgeData.meta and bridgeData.meta.keyboard_source) .. "）"
    end
    -- 文件名在 detectCurrentKeyboard 里已由"主题 get_keyboard 同源求值"定好，
    -- 不再做同名反查、偏好猜测、键位指纹校正——那些都是在弥补"猜文件名"的缺陷。
    -- 只有主题函数完全判定不出来时，才退回内存键盘显示名对应的候选文件。
    if not activeFile and #kbds > 0 then
        local bname = bridgeUsable and type(bridgeData.meta) == "table"
            and bridgeData.meta.keyboard or nil
        local cands = (type(bname) == "string" and bname ~= "")
            and findKbdCandidates(bname) or {}
        activeFile = cands[1] or kbds[1]
        kbdSelectReason = (kbdSelectReason or "主题 get_keyboard 未能判定")
            .. "；退回候选 " .. tostring(activeFile)
    end
    -- 同一主题重载（如"放弃修改"）保持用户当前正在看的键盘，不重新猜
    local kbdFileToLoad = prevKbd or activeFile or (kbds[1])
    -- 桥接键盘与目标文件可能不同（输入法还没重载 / 键盘刚在工具里换过）。
    -- 【绝不要在这里丢弃桥接去跑脚本】——上一版就是这么写的：名字一对不上就改走
    -- parseKeyboardData（执行整份键盘脚本），启动路径上跑脚本会占住主线程数秒，
    -- 遇到循环就直接不返回，表现为「打开就卡死、键盘还不对」。
    -- 现在只做「只读校验 + 静态解析」：对不上就先用纯字面量解析目标文件，
    -- 解析成功才切换；失败则继续用桥接键位（标注内存滞后），全程不执行脚本。
    local kbdNoScript = false
    if bKbd then
        local bname = (type(bKbd.name) == "string" and bKbd.name ~= "") and bKbd.name
            or tostring((bridgeData and type(bridgeData.meta) == "table" and bridgeData.meta.keyboard) or "")
        if bname ~= "" and kbdFileToLoad and not kbdFileMatchesDisplay(kbdFileToLoad, bname) then
            local okSt, st = false, nil
            if themeDir then
                okSt, st = pcall(parseKeyboardStatic, themeDir .. "/keyboards/" .. kbdFileToLoad)
            end
            if okSt and keyboardRowsOK(st) then
                kbdSelectReason = (kbdSelectReason and (kbdSelectReason .. "；") or "")
                    .. "内存键盘（" .. bname .. "）滞后于 " .. tostring(kbdFileToLoad)
                    .. "，改用该文件静态解析"
                bKbd = nil
                kbdNoScript = true     -- 已经静态解析过，loadKeyboard 不要再跑脚本
            else
                kbdSelectReason = (kbdSelectReason and (kbdSelectReason .. "；") or "")
                    .. "内存键盘（" .. bname .. "）与 " .. tostring(kbdFileToLoad)
                    .. " 不一致，但静态解析失败，暂用内存键位（不执行脚本）"
            end
        end
    end
    if #kbds > 0 then loadKeyboard(kbdFileToLoad, bKbd, { noScript = kbdNoScript })
    else kbdEnv = nil; stKbd = "键盘：当前"; refreshStatus(); renderPreview() end
end

-- ========== 按钮绑定 ==========
btnReset.onClick = function()
    if currentTheme then loadTheme(currentTheme) toast("已放弃修改，重新载入") end
end
btnExport.onClick = function()
    local ok, e = pcall(saveThemeDialog)
    if not ok then logErr("保存", e); toast("保存出错：" .. tostring(e)) end
end

-- 读取当前输入法默认偏好的所有项，返回 { {key=..., val=...}, ... }（按 key 排序）
function listInputPrefs()
    local out = {}
    local ok, err = pcall(function()
        local PM = luajava.bindClass("android.preference.PreferenceManager")
        local sp = PM.getDefaultSharedPreferences(activity)
        local all = sp.getAll()
        local keys = all.keySet().toArray()
        for i = 0, #keys - 1 do
            local k = tostring(keys[i])
            local v = all.get(k)
            local sv
            if v == nil then sv = "nil"
            else
                local okS, str = pcall(tostring, v)
                sv = okS and str or ("<" .. tostring(type(v)) .. ">")
            end
            out[#out + 1] = { key = k, val = sv }
        end
    end)
    if not ok then return nil, tostring(err) end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

-- 删除单项偏好（重启输入法后生效）
function deleteInputPref(key)
    local ok, err = pcall(function()
        local PM = luajava.bindClass("android.preference.PreferenceManager")
        local sp = PM.getDefaultSharedPreferences(activity)
        sp.edit().remove(key).apply()
    end)
    if not ok then return false, tostring(err) end
    return true
end

-- 弹出偏好列表，选择单项删除；删除或返回后重新弹出以刷新
function deletePrefDialog()
    local items, err = listInputPrefs()
    if not items then toast("读取偏好失败：" .. tostring(err)); return end
    if #items == 0 then toast("当前无偏好项"); return end
    listDialog("删除单项偏好（共 " .. #items .. " 项）", items, function(sel)
        local dlg = LuaDialog(activity)
        dlg.setTitle("删除偏好项")
        local tv = TextView(activity)
        local sv = sel.val or ""
        if #sv > 240 then sv = sv:sub(1, 240) .. "…" end
        tv.setText("键：" .. sel.key .. "\n值：" .. sv .. "\n\n删除后重启输入法生效。确定删除这一项吗？")
        tv.setTextSize(12); tv.setPadding(dp(14), dp(12), dp(14), dp(12))
        dlg.setView(tv)
        dlg.setButton("确认删除", function()
            dlg.dismiss()
            local ok, e = deleteInputPref(sel.key)
            if not ok then toast("删除失败：" .. tostring(e)) else toast("已删除：" .. sel.key) end
            deletePrefDialog()
        end)
        dlg.setButton2("返回列表", function() dlg.dismiss(); deletePrefDialog() end)
        dlg.setButton3("退出", function() dlg.dismiss() end)
        dlg.show()
    end, {
        label = function(it)
            local sv = it.val or ""
            if #sv > 56 then sv = sv:sub(1, 56) .. "…" end
            return it.key .. " = " .. sv
        end,
    })
end

btnView.onClick = function()
    listDialog("视图/诊断", {
        "删除单项偏好（当前偏好）",
        "显示/隐藏 候选栏",
        "查看报错（" .. #errLog .. "）",
        "复制报错",
    }, function(c)
        if c:find("删除单项偏好") then
            local okd, e = pcall(deletePrefDialog)
            if not okd then toast("打开列表失败：" .. tostring(e)) end
        elseif c:find("候选栏") then
            showCandidateFlag = not showCandidateFlag
            renderPreview()
            toast(showCandidateFlag and "已显示候选栏" or "已隐藏候选栏")
        elseif c:find("查看报错") then
            local dlg = LuaDialog(activity)
            dlg.setTitle("报错记录")
            local sv = ScrollView(activity); sv.setLayoutParams(LinearLayout.LayoutParams(-1, dp(320)))
            local tv = TextView(activity)
            local lines = {}
            if sandboxRealObjectsIsolated then
                table.insert(lines, "[安全隔离] 主题脚本的真实 this/service/activity/context/luajava 已全部换成安全桩；\n" ..
                    "针对真实键盘运行的函数（service:xxx / luajava.bindClass 等）在预览时为 no-op，不会操作输入法进程。")
            end
            local blocked = {}
            for g, n in pairs(sandboxBlockedClasses) do table.insert(blocked, g .. "×" .. n) end
            if #blocked > 0 then
                table.sort(blocked)
                table.insert(lines, "[Java类隔离] 未 import 的真机类已在访问源头换成安全桩：" ..
                    table.concat(blocked, "、") .. "\n（避免真机类 + 安全桩参数触发 coercion error / 输入法崩溃）")
            end
            if kbdSelectReason then
                table.insert(lines, "[键盘选择] " .. kbdSelectReason ..
                    "\n（复刻真机 ThemeManager.getKeyboard：主题根 main.lua 的 get_keyboard 判断；若未命中才回退首键盘）")
            end
            if kbdSourceNote then
                table.insert(lines, kbdSourceNote)
            end
            if kbdFallbackNote then
                table.insert(lines, "[键盘布局] " .. kbdFallbackNote .. "\n" ..
                    "（键盘脚本数据以 clean 隔离环境求值；样式与配色仍来自当前主题。）")
            end
            local kd = {}
            for f, info in pairs(kbdParseDiag) do kd[#kd + 1] = "· " .. f .. "：" .. info end
            if #kd > 0 then
                table.sort(kd)
                table.insert(lines, "[键盘解析诊断] 以下键盘脚本没能静态解析出 rows（含 rows 源码行，供定位动态写法）：\n" ..
                    table.concat(kd, "\n"))
            end
            if #errLog > 0 then table.insert(lines, table.concat(errLog, "\n\n")) end
            local inj = {}
            for g, n in pairs(autoInjectedGlobals) do table.insert(inj, g .. "×" .. n) end
            if #inj > 0 then
                table.sort(inj)
                table.insert(lines, "[沙箱兼容] 已为真机独有全局补默认值：" .. table.concat(inj, "、") ..
                    "\n（这些变量在主题脚本中参与运算，真机有定义；沙箱补 0/空表/空函数以保证样式完整加载）")
            end
            if #requiredModules > 0 then
                local seen, mods = {}, {}
                for _, m in ipairs(requiredModules) do
                    if not seen[m] then seen[m] = true mods[#mods + 1] = m end
                end
                table.insert(lines, "[require 加载链] 共 " .. #mods .. " 项：\n" .. table.concat(mods, "\n"))
            end
            local srcKeys = {}
            for k in pairs(diagSourceLines) do srcKeys[#srcKeys + 1] = k end
            if #srcKeys > 0 then
                table.sort(srcKeys)
                local sl = {}
                for _, k in ipairs(srcKeys) do
                    sl[#sl + 1] = k .. "  >>>  " .. tostring(diagSourceLines[k])
                end
                table.insert(lines, "[出错行源码] 崩溃时正在执行的源码行：\n" .. table.concat(sl, "\n"))
            end
            tv.setText(#lines > 0 and table.concat(lines, "\n\n") or "（暂无报错）")
            tv.setTextSize(11); tv.setTextIsSelectable(true); tv.setPadding(dp(10), dp(10), dp(10), dp(10))
            sv.addView(tv); dlg.setView(sv)
            dlg.setButton("关闭", function() dlg.dismiss() end)
            dlg.show()
        elseif c:find("复制报错") then
            copyText(#errLog > 0 and table.concat(errLog, "\n") or "（暂无报错）")
        end
    end)
end

-- 让 dirtyCount 变化时刷新提示：包装 markDirty
local _markDirty = markDirty
markDirty = function(n)
    _markDirty(n)
    if refreshDirty then pcall(refreshDirty) end
end

-- ========== 启动：默认加载当前主题 ==========
-- 整体 pcall 包裹：任何 Lua 层异常都只记日志、不让工具崩溃（native 崩溃则靠上面切断
-- native 调用来根治）。即使自动加载失败，工具界面仍可用，用户可手动选主题。
function safeBoot()
    local okCur, cur = pcall(function() return Config.getTheme() end)
    local themes = listThemes()
    local started = false
    if okCur and cur then
        for _, t in ipairs(themes) do
            if t == tostring(cur) then
                local ok, e = pcall(loadTheme, t)
                if ok then started = true else logErr("启动加载", e) end
                break
            end
        end
    end
    if not started and #themes > 0 then
        local ok, e = pcall(loadTheme, themes[1])
        if not ok then logErr("启动加载兜底", e) end
    end
end
local okBoot, bootErr = pcall(safeBoot)
if not okBoot then logErr("启动", bootErr) end

-- ========== 启动自检：轻量状态日志（零 JNI，不阻塞主线程） ==========
-- 【r27.44 提速】旧逻辑在首帧后 200ms 无条件跑一次 dumpKbViewTexts：它会经 JNI
-- 遍历真机整棵 View 树（最多 600 节点 × 多次 getXxx）、强制 measure/layout、
-- 再打印 200+ 行诊断日志。首帧已同步采集到权威快照，这次 dump 对功能零贡献，
-- 却每次打开工具都占住主线程几百毫秒（卡顿/ANR 风险）。现改为：正常路径只从
-- 内存打一行状态日志；完整 View 树 dump 保留在「视图/诊断」菜单里按需触发。
local function emitBootStatus()
    local sd = _G.__kbdDiag or {}
    logErr("View文本", "[STRUCT] VER=r27.49 数据源=桥接同步快照(单次渲染) 显图=后缀判断 背景=贴合内容块 编辑面板=分类按钮")
    logErr("View文本", string.format(
        "[STRUCT] [SRC] 内容=全桥接(ltHit=%d/rendered=%d 角标XY=%d 工具栏tb=%d) 脚本内部名仅越界兜底=%d 皮肤=主题(桥接无样式字段)",
        sd.ltHit or 0, sd.rendered or 0, sd.cornerWithXY or 0,
        (liveKeyTexts and liveKeyTexts.toolbarN) or 0, sd.scriptMasked or 0))
end
pcall(emitBootStatus)
-- 仅当同步采集失败（真机 View 首帧未就绪）才延迟兜底一次，确保角标不回退推导。
if liveKeyTexts == nil then
    pcall(function()
        uiHandler.postDelayed(function()
            if liveKeyTexts ~= nil then return end
            local ok, r = pcall(dumpKbViewTexts)
            if ok then pcall(applyLiveFromRaw, r) end
        end, 600)
    end)
end

