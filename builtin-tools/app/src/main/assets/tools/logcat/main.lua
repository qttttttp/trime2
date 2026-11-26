--[[
=====================================================================
 日志搜索（工具版）— Trime 日志查看器
 r27.70：在键盘脚本基础上加工具环境适配层，可作为独立工具运行
 Kimi-K3 整理加注释
=====================================================================
【功能列表】
• 日志来源:
    - logcat 系统日志（含 Java crash 崩溃日志），按分类过滤
    - LuaActivity 内部日志（print / Lua 错误信息）
• 排序: 顺序 / 倒序切换
• 搜索过滤: 输入关键字实时过滤（分类 + 关键字叠加），命中处高亮
• 列表交互:
    点击: 上屏（键盘脚本=提交到输入框；工具版=复制到剪贴板）
    长按: 弹出选项菜单（整行原文，条目间换行）
      - 有搜索筛选: 复制 / 清除筛选并跳转到当前条目
      - 无筛选、未标记: 复制 / 标记(起点)
      - 无筛选、已标记: 清除标记 / 上屏标记到此条目 / 复制(起点→当前范围)
• 分类气泡弹窗（仿微信气泡，尖角自动对齐锚点）
    r27.60: 气泡与长按菜单均非 focusable，切分类不再收起输入法键盘
• 实时显示内存占用（进程 PSS / Lua VM）
• 配色自动跟随系统深色 / 浅色模式

【注意事项】
• 当前脚本仅支持 trime2 0.7.3+ 版
• r27.70 工具版：同时兼容键盘脚本与独立工具两种环境（自动探测）

【使用方法（工具版）】
1. 把本目录放到 rime/tools/日志搜索/（含 main.lua + init.lua）
2. 输入法设置 → 工具 → 日志搜索；也可在「常用工具」里固定显示(init.lua show=true)
3. 返回按钮关闭工具（工具模式），键盘脚本模式仍切回默认键盘

【关于脚本】
    Copyright © 2026 zums
=====================================================================
]]

import "android.view.*"
import "android.widget.*"
import "android.content.ClipData"
import "android.content.Context"
import "com.osfans.trime.Config"

import "android.graphics.Color"
import "android.graphics.drawable.GradientDrawable"
import "android.graphics.drawable.InsetDrawable"
import "android.content.res.ColorStateList"
import "android.graphics.drawable.RippleDrawable"
import "android.graphics.drawable.StateListDrawable"
import "android.util.TypedValue"
import "android.view.View"
import "android.view.WindowManager"
import "android.view.Display"
import "android.os.Build"
import "android.view.inputmethod.InputMethodManager"
import "com.androlua.LuaDialog"

import "com.androlua.LuaActivity"
import "com.androlua.LuaAdapter"

import "android.graphics.Paint"
import "android.graphics.Path"
import "android.graphics.RectF"
import "android.graphics.drawable.ShapeDrawable"
import "android.graphics.PixelFormat"
import "android.graphics.drawable.Drawable"
import "java.lang.Runnable"
import "android.view.ViewTreeObserver$OnGlobalLayoutListener"

import "android.os.Process"
import "java.lang.reflect.Array"

--=====================================================================
-- r27.70 工具环境适配层
-- 原脚本是输入法键盘脚本(this=输入法服务，用 showCustomView/commitText/getInputView)。
-- 作为独立工具运行时 this 是 LuaActivity：没有这些 API，改用 setContentView / 剪贴板 / finish。
-- 这里只做环境桥接，下面 1800 行业务逻辑保持不动。
--=====================================================================
local 工具模式 = false
pcall(function() 工具模式 = (this.getInputView == nil) end)
local JHandler
pcall(function() JHandler = import "android.os.Handler" end)

-- 兼容：显示内容视图（键盘=挂自定义面板，工具=设 Activity 内容视图）
local function 挂载视图(view)
    if 工具模式 then
        activity.setContentView(view)
    else
        this.showCustomView(view)
    end
end

-- 兼容：卸载/切回（键盘=恢复输入法键盘，工具=无操作）
local function 卸载视图()
    if 工具模式 then
        -- 工具里不做任何事，交由返回/finish 处理
    else
        this.showCustomView(nil)
    end
end

-- 兼容：上屏（键盘=commitText 到输入框，工具=复制到剪贴板）
local function 上屏或复制(text)
    text = tostring(text or "")
    if 工具模式 then
        local cb = activity.getSystemService(Context.CLIPBOARD_SERVICE)
        cb.setPrimaryClip(ClipData.newPlainText("log", text))
        print("已复制到剪贴板（工具模式无输入目标）")
    else
        this.commitText(text)
    end
end

-- 兼容：延迟执行（键盘=输入法 Handler，工具=android.os.Handler）
local function 延迟执行(fn, ms)
    local ok = false
    if 工具模式 and JHandler then
        ok = pcall(function()
            JHandler().postDelayed(Runnable(function() fn() end), ms)
        end)
    end
    if not ok then
        -- 键盘脚本 / Handler 不可用兜底
        this.getHandler().postDelayed(Runnable(function() fn() end), ms)
    end
end

local function dp(v)
    return math.floor(TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v,
        this.getResources().getDisplayMetrics()) + 0.5)
end
--====================================================
-- 配色方案（自动跟随系统深色/浅色）
--====================================================
local PALETTES = {
    light = {
        pageBg = 0xFFF4F6FA,
        cardBg = 0xFFFFFFFF,
        bubbleBg = "#FF4D8930", -- 气泡背景色仅支持RGB字符串
        titleColor = 0xFF1F2D3D,
        tipColor = 0xFF8A94A6,
        textColor = 0xFF333A45,
        errorColor = 0xFFE0584E,
        divider = 0x00000000,
        accent = 0xFF4A90E2,
        accentPress = 0xFF3A78C4,
        btnText = 0xFFFFFFFF,
        stroke = 0xFFE1E6EE,
        ripple = 0x334A90E2,

        -- ▼▼ 日志等级颜色 ▼▼
        level = {
            V = 0xFF9E9E9E, -- Verbose 灰
            D = 0xFF4A90E2, -- Debug   蓝
            I = 0xFF4CAF50, -- Info    绿
            W = 0xFFFFA000, -- Warn    橙
            E = 0xFFE0584E, -- Error   红
            F = 0xFFB71C1C, -- Fatal   深红
        },
    },
    night = {
        pageBg = 0xFF16181D,
        cardBg = 0xFF22252C,
        bubbleBg = "#FF8A94A6", -- 气泡背景色仅支持RGB字符串
        titleColor = 0xFFE8EAF0,
        tipColor = 0xFF8A94A6,
        textColor = 0xFFC9CDD6,
        errorColor = 0xFFFF7A70,
        divider = 0x00000000,
        accent = 0xFF5B9BF0,
        accentPress = 0xFF255AA1,
        btnText = 0xFFFFFFFF,
        stroke = 0xFF34383F,
        ripple = 0x335B9BF0,

        -- ▼▼ 日志等级颜色（深色主题稍亮）▼▼
        level = {
            V = 0xFF8A94A6,
            D = 0xFF5B9BF0,
            I = 0xFF66BB6A,
            W = 0xFFFFB74D,
            E = 0xFFFF7A70,
            F = 0xFFFF5252,
        },
    },
}
-- 取当前主题配色，取不到时回退浅色
local C = PALETTES[Config.getStyle()] or PALETTES.light

--====================================================
-- 工具函数
--====================================================

-- dp 转 px
local function dp2px(v)
    return math.floor(TypedValue.applyDimension(
    TypedValue.COMPLEX_UNIT_DIP, v,
    this.getResources().getDisplayMetrics()) + 0.5)
end

-- 颜色值兼容：字符串("#AARRGGBB") 转 Color int
local function toColor(c)
    if type(c) == "string" then return Color.parseColor(c) end
    return c
end

-- 圆角背景（可带描边；inset 为四边内缩，用于制造间距感）
local function roundRect(color, radius, strokeColor, inset)
    local d = GradientDrawable()
    d.setShape(GradientDrawable.RECTANGLE)
    d.setCornerRadius(radius or dp2px(10))
    if type(color) == "table" then
        local cs = {}
        for i, v in ipairs(color) do cs[i] = toColor(v) end
        d.setColors(cs)
    else
        d.setColor(toColor(color))
    end
    if strokeColor then d.setStroke(dp2px(1), toColor(strokeColor)) end
    local i = inset or 5
    return InsetDrawable(d, i, i, i, i)
end

-- 按压水波纹按钮背景
local function ripple(normalColor, pressedColor, radius, strokeColor)
    normalColor = normalColor or C.accent
    pressedColor = pressedColor or C.accentPress
    local content = roundRect(normalColor, radius or dp2px(10), strokeColor)
    local pressed = roundRect(pressedColor, radius or dp2px(10), strokeColor)
    local sl = StateListDrawable()
    sl.addState({ android.R.attr.state_pressed }, pressed)
    sl.addState({ android.R.attr.state_selected }, pressed)
    sl.addState({}, content)
    return RippleDrawable(ColorStateList.valueOf(toColor(C.ripple)), sl, nil)
end

-- 列表项卡片背景（带按压效果）
local function itemBg()
    local normal = roundRect(C.cardBg, dp2px(10), C.stroke, 0)
    local pressed = roundRect(C.accentPress, dp2px(10), nil, 0)
    local sl = StateListDrawable()
    sl.addState({ android.R.attr.state_pressed }, pressed)
    sl.addState({}, normal)
    return RippleDrawable(ColorStateList.valueOf(toColor(C.ripple)), sl, nil)
end

--====================================================
-- 界面布局（手机竖屏优化）
-- 顶部工具栏 + 全宽日志列表
--====================================================
local ids = {}

-- 生成一个工具栏按钮配置（loadlayout 表）
local function toolBtn(text)
    return {
        Button;
        text = text;
        textSize = "13sp";
        textColor = C.btnText;
        layout_width = "0dp";      -- 改为 0dp，由 weight 分配
        layout_weight = "1";       -- 平分剩余空间
        layout_height = "wrap";
        singleLine = true;         -- 防止换行
        ellipsize = "end";         -- 文字过长省略
        minHeight = "0dp";
        minimumHeight = "0dp";
        -- minWidth = "0dp";
        -- minimumWidth = "0dp";
        paddingTop = "8dp";
        paddingBottom = "8dp";
        -- paddingRight = "8dp";
        -- paddingLeft = "8dp";
        -- layout_margin = "0dp";
        background = ripple();
        AllCaps = false;
    }
end

local layout = {
    LinearLayout;
    id = "root";
    orientation = "vertical";
    layout_width = "fill";
    layout_height = "fill";
    backgroundColor = C.pageBg;
    -- padding = "5dp";
    -- 顶部工具栏：标题 + 提示信息 + 操作按钮组
    {
        LinearLayout;
        layout_width = "fill";
        layout_height = "wrap";
        orientation = "horizontal";
        gravity = "center_vertical";
        padding = "2dp";
        backgroundColor = C.cardBg;
        clipChildren = false,
            clipToPadding = false,
            elevation = dp(8);
            translationZ = dp(2);
        {
            TextView;
            id = "title";
            text = "日志";
            textSize = "16sp";
            textStyle = "bold";
            textColor = C.titleColor;
            layout_width = "wrap";
        };
        -- 提示区：第一行 分类·条数，第二行 内存占用
        {
            LinearLayout;
            orientation = "vertical";
            layout_width = "wrap";
            layout_height = "fill";
            layout_marginLeft = "8dp";
            gravity = "center_vertical";
            layout_weight = "0"; 
            {
                TextView;
                id = "tips";
                text = "";
                textSize = "10sp";
                textColor = C.tipColor;
                layout_width = "wrap";
                gravity = "center_vertical";
            };
            {
                TextView;
                id = "pss";
                text = "";
                textSize = "10sp";
                textColor = C.tipColor;
                gravity = "center_vertical";
            };
        };
        -- 右侧操作按钮：分类 / 排序 / 清除 / 返回
        {
            LinearLayout;
            id="barBtns",
            layout_width = "0dp";
            layout_weight = "1";
            layout_height = "wrap";
            orientation = "horizontal";
            gravity = "end|center";
            (function()
                local b = toolBtn("Lua"); b.id = "cat"; return b
            end)();
            (function()
                local b = toolBtn("顺序"); b.id = "order"; return b
            end)();
            (function()
                local b = toolBtn("清除"); b.id = "clear"; return b
            end)();
            (function()
                local b = toolBtn("返回"); b.id = "back"; return b
            end)();
        };
    };

    -- 搜索栏:输入即过滤(分类 + 关键字叠加),右侧显示命中条数
    {
        LinearLayout;
        layout_width = "fill";
        layout_height = "wrap";
        orientation = "horizontal";
        gravity = "center_vertical";
        padding = "4dp";
        backgroundColor = C.cardBg;
        {
            -- 用 TextView 而不是 EditText:面板里 EditText 第一次点击只会拿到焦点
            -- (弹光标),第二次才触发 onClick;TextView 没有焦点竞争,一次点击即触发。
            -- 关键字输入交给 overlay 弹窗里的 EditText(见 打开搜索弹窗)。
            TextView;
            id = "search";
            layout_width = "0dp";
            layout_weight = "1";
            layout_height = "wrap";
            text = "";
            hint = "搜索日志…";
            textSize = "13sp";
            textColor = C.textColor;
            hintTextColor = C.tipColor;
            singleLine = true;
            ellipsize = "end";
            clickable = true;
            focusable = false;
            focusableInTouchMode = false;
            paddingLeft = "10dp";
            paddingRight = "10dp";
            paddingTop = "6dp";
            paddingBottom = "6dp";
            gravity = "center_vertical";
            background = roundRect(C.pageBg, dp2px(8), C.stroke, 0);
        };
        {
            TextView;
            id = "searchInfo";
            text = "";
            textSize = "11sp";
            textColor = C.tipColor;
            layout_width = "wrap";
            paddingLeft = "6dp";
            paddingRight = "4dp";
            gravity = "center_vertical";
        };
        (function()
            local b = toolBtn("清空"); b.id = "clearSearch"; return b
        end)();
    };

    -- 日志列表
    {
        ListView;
        id = "list";
        layout_width = "fill";
        layout_height = "fill";
        layout_marginTop = "5dp";
        divider = roundRect(0,0,0,0);
        dividerHeight = "6dp";
        padding = "2dp";
        cacheColorHint = 0x00000000;
        scrollbars = "vertical";
        fadingEdge = "vertical";
        fadingEdgeLength = "12dp";
        fastScrollEnabled = true;
    };

    -- 底部错误提示（隐藏，visibility=8 即 GONE）
    {
        TextView;
        id = "log";
        textSize = "12sp";
        textColor = C.errorColor;
        visibility = 8;
    };
}

layout = loadlayout(layout, ids)

--====================================================
-- 视图切换 —— 与「自定义剪切板」完全一致,走 模块.常用
--
-- RootInputView 的真实层级:
--   mRoot (LinearLayout)                       ← 父容器
--     ├ mCenterLayout (FrameLayout)            ← 输入界面(候选栏+键盘)
--     │    └ mInputViewRoot
--     │         ├ mCandidateView
--     │         └ mInputView                  ← getInputView()
--     └ 小屏模式还有 mLeftLayout / mRightLayout
--
-- 进入:隐藏 mRoot 下所有可见子 view(即 mCenterLayout),再把面板 addView
--       到 mRoot —— 面板和输入界面是兄弟,后加的在上层。
-- 切键盘:removeView(面板) + 把刚才隐藏的 view 恢复 VISIBLE。
--
-- 为什么窗口隐藏再恢复不会被顶掉:onWindowShown 复位的是 mCenterLayout
-- **内部**的 mInputViewRoot,而 mCenterLayout 自身是 GONE,改内部的
-- 可见性不会让它重新出现,面板始终留在最上层。
--====================================================
local 输入界面, 父容器 = nil, nil
local 有常用, cy = false, nil
if not 工具模式 then
    -- 仅输入法键盘环境才有这些视图层级 API
    输入界面 = this.getInputView()
    父容器 = 输入界面.getParent()
    local 保留工具栏 = false
    if not 保留工具栏 then
        父容器   = this.getRootView().getRoot()                 -- mRoot (LinearLayout)
        输入界面 = this.getInputView().getParent().getParent()  -- mCenterLayout
    end
    local ok, m = pcall(require, "模块.常用")
    if ok then 有常用, cy = true, m end
end
-- 工具模式不加载 模块.常用（那是输入法键盘专用模块），强制走桥接分支

local 脚本视图 = false
local 隐藏记录 = nil   -- 第一次 显示面板 时记录的隐藏列表;关面板时清空

-- 显示面板(隐藏输入界面):隐藏 mRoot 下的输入界面,把面板挂到 mRoot 上
-- 每次调用都会隐藏当前可见的同级 view,但记录只在第一次保存——
-- 之后因搜索挂起再恢复,关面板时仍按第一次的记录还原。
-- 模块.常用 是无状态的(所有脚本共用一个虚拟机),记录由本脚本自己保存。
local function 显示面板()
    if 脚本视图 then return true end
    if cy then
        local t = cy.显示脚本view(父容器, layout)
        if 隐藏记录 == nil then 隐藏记录 = t end
    else
        挂载视图(layout)      -- 兜底:没有 模块.常用 / 工具模式
    end
    脚本视图 = true
    return true
end

-- 显示键盘(隐藏面板):移除面板
--   无参  : 按第一次的隐藏记录还原(关面板/销毁用)
--   true  : tag 判断 —— 带脚本标记的隐藏,没 tag 的显示。
--           用于打开搜索弹窗:输入界面没 tag 必然被点亮,弹窗能打字。
-- 注意:关键字输入框必须放在 overlay 弹窗里(见下方 打开搜索弹窗),
-- 面板把键盘整块藏掉了,面板内的 EditText 拿不到 focus。
local function 显示键盘(输入界面)
    if not 脚本视图 then return true end
    if cy then
        if 输入界面 then
            -- 搜索:只点亮键盘,记录保留(第二次显示面板不许重新记录)
            cy.返回(隐藏记录, layout, 父容器, "输入")
        else
            -- 关面板:按第一次的记录还原,用完清空
            cy.返回(隐藏记录, layout, 父容器)
            隐藏记录 = nil
        end
    else
        卸载视图()
    end
    脚本视图 = false
    return true
end

-- 初始化:挂面板
显示面板()


--====================================================
-- 关于输入焦点(重要):
-- RootInputView.showCustomView(view) 把本面板加进 mCenterLayout 时,
-- 会把 trime 键盘(mInputViewRoot)设为 GONE,IME 的输入连接也随之断开,
-- 面板里的 EditText 拿不到输入焦点,系统软键盘也弹不出来。
-- 因此搜索输入不走面板内的 EditText,而是弹一个 overlay 弹窗
-- (FLAG_ALT_FOCUSABLE_IM),做法与自定义剪切板的"添加短语"弹窗完全一致。
--====================================================

--====================================================
-- 分类定义
-- 注意：下标与 MATCHERS 一一对应；最后一项固定为
--       LuaActivity 内部日志（makeAdapter 中特判处理）
--====================================================
local CATEGORIES = { "全部", "Rime", "语音", "媒体", "UI", "Lua", "性能", "错误", "崩溃", "脚本", "日志" }
--====================================================
-- 分类匹配规则（按日志来源/TAG）
--====================================================
local MATCHERS = {
    -- 全部：不过滤
    [1] = function(line) return true end,

    -- Rime 输入法核心
    [2] = function(line)
        return line:find("rime") ~= nil
        or line:find("rime%.trime") ~= nil
        or line:find("handleRimeMessage") ~= nil
        or line:find("RimeMessage") ~= nil
    end,

    -- 语音识别
    [3] = function(line)
        return line:find("_V_Speech") ~= nil
        or line:find("ASREngine") ~= nil
        or line:find("Recognizer") ~= nil
        or line:find("SpeechSdk") ~= nil
        or line:find("OkHttpDns") ~= nil
        or line:find("ParamCheck") ~= nil
        or line:find("SoundPool") ~= nil
    end,

    -- 媒体/音频解码
    [4] = function(line)
        return line:find("MediaCodec") ~= nil
        or line:find("CCodec") ~= nil
        or line:find("OplusCCodec") ~= nil
        or line:find("BufferPoolAccessor") ~= nil
        or line:find("PipelineWatcher") ~= nil
        or line:find("OplusFeedbackInfo") ~= nil
        or line:find("OplusMediaCodecUtils") ~= nil
        or line:find("ReflectedParamUpdater") ~= nil
        or line:find("Codec2Client") ~= nil
        or line:find("MediaCodecList") ~= nil
    end,

    -- UI / 绘制 / 窗口
    [5] = function(line)
        return line:find("VRI%[InputMethod%]") ~= nil
        or line:find("ViewRootImpl") ~= nil
        or line:find("BLASTBufferQueue") ~= nil
        or line:find("OpenGLRenderer") ~= nil
        or line:find("ScrollIdentify") ~= nil
        or line:find("ThemeUtils") ~= nil
        or line:find("BufferQueueConsumer") ~= nil
    end,

    -- Lua / 脚本层
    [6] = function(line)
        return line:find("System%.err") ~= nil
        or line:find("luaj") ~= nil
        or line:find("LuaMethodInterceptor") ~= nil
        or line:find("com%.androlua") ~= nil
        or line:find("LuaActivity") ~= nil
        or line:find("LuaClosure") ~= nil
        or line:find("ziparchive") ~= nil
        or line:find("Generated_") ~= nil
        or line:find("Function") ~= nil
        or line:find("LuaAdapter") ~= nil
    end,

    -- 性能 / 卡顿
    [7] = function(line)
        return line:find("Quality") ~= nil
        or line:find("JankCountInfo") ~= nil
    end,

    -- 错误（logcat E 级 / 异常关键字）
    [8] = function(line)
        return line:find(" E/") ~= nil
        or line:find(" E ") ~= nil
        or line:find("Exception") ~= nil
        or line:find("Caused by:") ~= nil
        or line:find("error") ~= nil
        or line:find("Error") ~= nil
    end,

    -- r27.62 崩溃：输入法的所有崩溃 = Java 致命异常 + native tombstone
    [9] = function(line)
        -- ① Java 层崩溃：AndroidRuntime 这个 TAG 会出现在崩溃栈的每一行
        if line:find("AndroidRuntime") ~= nil
            or line:find("FATAL EXCEPTION") ~= nil
            or line:find("FATAL SIGNAL") ~= nil then
            return true
        end
        -- ② native 层崩溃：debuggerd/tombstoned 以 F 级 DEBUG tag 输出整个 tombstone
        --    -v time  → "F/DEBUG   ( 1234):"  -v threadtime → "F DEBUG   :"
        if line:find("F/DEBUG") ~= nil
            or line:find("F DEBUG") ~= nil
            or line:find("F/tombstoned") ~= nil
            or line:find("F tombstoned") ~= nil
            or line:find("tombstone") ~= nil
            or line:find("Tombstone") ~= nil then
            return true
        end
        -- ③ tombstone 关键内容行（防止 -v raw 等格式下没有 TAG 前缀时漏掉）
        if line:find("signal %d+ %(SIG") ~= nil
            or line:find("Cmdline:") ~= nil
            or line:find("backtrace:") ~= nil
            or line:find("Build fingerprint:") ~= nil
            or line:find("%*%*%* %*%*%*") ~= nil then
            return true
        end
        return false
    end,

    -- Trime 主服务脚本
    [10] = function(line)
        return line:find("TrimeService") ~= nil
    end,

    -- LuaActivity 内部日志：不读 logcat，走 makeAdapter 特判分支
    [11] = function()
        return nil
    end
}
-- 当前分类（下标从1开始，默认显示 LuaActivity 内部日志）
local currentCat = #CATEGORIES
-- 当前是否倒序（默认倒序，最新日志在上）
local isReverse = true

-- r27.60: 长按菜单状态
local 显示行 = {}      -- makeAdapter 时填充，1-based，对应 ListView position+1（整行原文）
local 标记起点 = nil   -- 无筛选时长按标记的起点（整行原文）
local 菜单popup = nil  -- 长按选项菜单，关闭面板时一并清理

local am = this.getSystemService(Context.ACTIVITY_SERVICE)
local pids = { Process.myPid() }

-- 刷新顶部提示：分类·条数 + 内存占用
function setTip(n)
    local memInfo = am.getProcessMemoryInfo(pids)
    local pssMB = Array.get(memInfo, 0).getTotalPss() / 1024
    local luaMB = collectgarbage("count") / 1024
    ids.tips.setText(string.format("%s · %d 条", CATEGORIES[currentCat], n))
    ids.pss.setText(string.format("内存 · %.1f MB (Lua %.1f MB)", pssMB, luaMB))
end

-- 延迟 100ms 在底部显示错误提示（避免与布局初始化抢主线程）
function log(s)
    延迟执行(function()
        ids.log.setText(tostring(s))
        ids.log.setVisibility(0)
    end, 100)
end

--====================================================
-- 日志列表项布局
--====================================================
local convertView = {
    LinearLayout;
    id = "item";
    layout_width = "fill";
    layout_height = "wrap";
    orientation = "vertical";
    padding = "10dp";
    {
        TextView;
        id = "log_time";
        layout_width = "fill";
        textSize = "11sp"; -- 时间小一点
        paddingLeft = "5dp";
        typeface = "monospace";
        textColor = C.tipColor; -- 时间用提示色，弱化
        lineSpacingMultiplier = 1.1;
    };
    {
        TextView;
        id = "log_content";
        layout_width = "fill";
        textSize = "13sp";
        paddingLeft = "5dp";
        typeface = "monospace";
        textColor = C.textColor;
        lineSpacingMultiplier = 1.15;
    };
}

--====================================================
-- 根据日志行取等级颜色
-- 支持格式:
--   10-11 19:06:03.103 W/TrimeService(22803): msg
--   2026-10-11 19:06:03.103 E/TAG(123): msg
-- 找不到等级时返回默认正文色
--====================================================

local function levelColor(line)
    if not line then return C.textColor end

    local lv
    -- 2) 10-12 19:44:14.159 19601 19601 W TrimeService: ...
    lv = line:match("%d%d:%d%d:%d%d%.%d+%s+%d+%s+%d+%s+([VDIWEF])%s+")
    if lv then return (C.level and C.level[lv]) or C.textColor end

    -- 3) 10-12 19:43:38.000 W/TrimeService(19601): ...
    lv = line:match("%d%d:%d%d:%d%d%.%d+%s+([VDIWEF])/")
    if lv then return (C.level and C.level[lv]) or C.textColor end

    return C.textColor
end

--====================================================
-- 读取 logcat（-d 立即返回，-v time 带日期时间）
--====================================================
-- 输出格式:
local logcatFormats = {
    "brief",       -- 优先级/标签 + PID + 消息
    "process",     -- 优先级/标签 + PID
    "tag",         -- 优先级/标签
    "thread",      -- 优先级/标签 + PID + TID
    "raw",         -- 仅原始消息
    "time",        -- 日期 + 时间 + 优先级/标签 + PID
    "threadtime",  -- 日期 + 时间 + 优先级/标签 + PID + TID
    "long",        -- 所有元数据字段，空行分隔
}
-- r27.62 缓存：logcat -d 只在重建数据源时执行一次；翻页/滚动复用同一份结果，
-- 避免每次都 exec 进程 + 读全部行阻塞输入法主线程。
local 日志缓存 = nil
local function javaLogs()
    if 日志缓存 ~= nil then return 日志缓存 end
    local Runtime = luajava.bindClass("java.lang.Runtime")
    local BufferedReader = luajava.bindClass("java.io.BufferedReader")
    local InputStreamReader = luajava.bindClass("java.io.InputStreamReader")

    -- -v time 输出格式: 10-11 14:23:45.123 I/TAG( PID): msg
    local proc = Runtime.getRuntime().exec("logcat -d -v time")
    local reader = BufferedReader(InputStreamReader(proc.getInputStream()))
    local lines = {}
    local line
    while true do
        line = reader.readLine()
        if line == nil then break end
        lines[#lines + 1] = line
    end
    reader.close()
    日志缓存 = lines
    return lines
end

-- 清空 logcat 缓冲区（同时清缓存，下次重建重新读取）
function clearJavaLogs()
    local Runtime = luajava.bindClass("java.lang.Runtime")
    Runtime.getRuntime().exec("logcat -c")
    日志缓存 = nil
end

--====================================================
-- 解析日志行：拆出「时间+等级」和「正文」
-- 输入: 10-11 19:01:25.085 W/rime.trime(10669): updated option: soft_cursor
-- 返回: time="10-11 19:01:25.085 W", body="rime.trime(10669): updated option: soft_cursor"
--====================================================
local function splitLogLine(line)
    if not line then return "", "" end

    -- 2) 10-12 19:44:14.159 19601 19601 W TrimeService: onStartInput: vang
    local date2, time2, ms2, pid2, tid2, level2, rest2 =
        line:match("^(%d%d%-%d%d)%s+(%d%d:%d%d:%d%d)%.(%d+)%s+(%d+)%s+(%d+)%s+([VDIWEF])%s+(.*)$")
    if date2 then
        local timeStr = string.format("%s %s.%s %s %s %s", date2, time2, ms2, pid2, tid2, level2)
        return timeStr, rest2
    end

    -- 3) 10-12 19:43:38.000 W/TrimeService(19601): onStartInput: ...
    local date3, time3, ms3, level3, rest3 =
        line:match("^(%d%d%-%d%d)%s+(%d%d:%d%d:%d%d)%.(%d+)%s+([VDIWEF])/(.*)$")
    if date3 then
        local timeStr = string.format("%s %s.%s %s", date3, time3, ms3, level3)
        return timeStr, rest3
    end

    -- 不匹配（堆栈续行、空行等）整行作为正文
    return "", line
end
local PATTERN_TIME_2 =
    "^(%d%d%-%d%d)%s+(%d%d:%d%d:%d%d)%.(%d+)%s+(%d+)%s+(%d+)%s+([VDIWEF])%s+"

local PATTERN_TIME_3 =
    "^(%d%d%-%d%d)%s+(%d%d:%d%d:%d%d)%.(%d+)%s+([VDIWEF])/"

import "android.text.SpannableString"
import "android.text.Spanned"
import "android.text.style.ReplacementSpan"

------------------------------------------------------------
-- 2. TabSpan（按原样，仅去掉对旧全局变量的依赖）
------------------------------------------------------------
local function newTabSpan3()
    return luajava.override(ReplacementSpan, {

        getSize = function(super, paint, text, start, finish, fm)
            if fm ~= nil then
                local fmi = paint.getFontMetricsInt()
                fm.top = fmi.top
                fm.ascent = fmi.ascent
                fm.descent = fmi.descent
                fm.bottom = fmi.bottom
            end
            return math.ceil(paint.measureText(text))
        end,

        draw = function(super, canvas, text, start, finish, x, top, y, bottom, paint)
            local oldColor = paint.getColor()
            local oldFakeBold = paint.isFakeBoldText()

            -- 设置 tab 样式
            paint.setColor(toColor("#FF54A02F"))
            paint.setFakeBoldText(true)
            canvas.drawText(text, x, y, paint)

            -- tab 背景色
            -- paint.setColor(toColor(C.tab_bg))
            -- local w = paint.measureText(" ") * TAB_SPACES
            -- paint.setStyle(Paint.Style.FILL)
            -- local rect = RectF(x, top, x + w, bottom)
            -- local radius = (bottom - top)/2
            -- canvas.drawRoundRect(rect, 6, 6, paint) -- 4px 圆角

            -- 恢复
            paint.setColor(oldColor)
            paint.setFakeBoldText(oldFakeBold)
        end,
    })()
end

local function newTabSpan()
    return luajava.override(ReplacementSpan, {
        getSize = function(super, paint, text, start, finish, fm)
            if fm ~= nil then
                local fmi = paint.getFontMetricsInt()
                fm.top = fmi.top
                fm.ascent = fmi.ascent
                fm.descent = fmi.descent
                fm.bottom = fmi.bottom
            end
            return math.ceil(paint.measureText(tostring(text)))
        end,
        draw = function(super, canvas, text, start, finish, x, top, y, bottom, paint)
            local oldColor = paint.getColor()
            local oldFakeBold = paint.isFakeBoldText()
                        -- tab 背景色
            paint.setColor(toColor("#939493"))
            local w = paint.measureText(tostring(text))
            local lv = paint.measureText("W")
            paint.setStyle(Paint.Style.FILL)
            local rect = RectF(w - lv - 10, top, x + w + 10, bottom)
            local radius = (bottom - top)/2
            canvas.drawRoundRect(rect, 6, 6, paint) -- 4px 圆角
            
            paint.setColor(toColor("#F5F5F5"))
            paint.setFakeBoldText(true)
            canvas.drawText(tostring(text), x, y, paint)
            
            paint.setColor(oldColor)
            paint.setFakeBoldText(oldFakeBold)
        end,
    })()
end

import "java.util.regex.Pattern"

------------------------------------------------------------
-- mSpanned：返回 SpannableString
------------------------------------------------------------
function mSpanned(text)
    if not text or text == "" then return text end

    -- 创建可变的 SpannableString
    local sp = SpannableString(text)

    local matcher = Pattern.compile(text).matcher(text)
    while matcher.find() do
        sp.setSpan(newTabSpan(),
            matcher.start(), matcher.end(),
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    end

    return sp
end

--====================================================
-- 构建 Adapter（数据源 → 列表）
--====================================================
local actLogs = nil
local adp = LuaAdapter(this.getApplicationContext(), convertView)

---------------------------------------------------------------- 搜索过滤
local 搜索词 = ""        -- 小写后的关键字,空表示不过滤
local 搜索原始 = ""      -- 原始输入(用于高亮大小写不敏感替换)
local 总条数 = 0         -- 当前分类下的总条数(过滤前)
local 已过滤 = false

-- 关键字是否命中(大小写不敏感;多个空格分隔的关键字需全部命中)
local function 命中(line, kw)
    if kw == "" then return true end
    local lower = line:lower()
    for w in kw:gmatch("%S+") do
        if lower:find(w, 1, true) == nil then return false end
    end
    return true
end

-- 把命中片段包成高亮(转成 SpannableString,不破坏原文本)
local function 高亮(body)
    if 搜索原始 == "" or body == nil or body == "" then return body end
    local ok, sp = pcall(function()
        local SpannableString = luajava.bindClass("android.text.SpannableString")
        local BackgroundColorSpan = luajava.bindClass("android.text.style.BackgroundColorSpan")
        local s = SpannableString(body)
        local lower, markLen = body:lower(), 0
        -- 逐字查找(用 plain find 避免关键字里的 % 等被当模式字符)
        local startPos = 1
        for w in 搜索原始:gmatch("%S+") do
            local wl = w:lower()
            local from = 1
            while true do
                local a, b = lower:find(wl, from, true)
                if a == nil then break end
                s.setSpan(BackgroundColorSpan(0x664A90E2), a - 1, b, 33) -- SPAN_EXCLUSIVE_EXCLUSIVE
                markLen = markLen + 1
                from = b + 1
                if markLen > 200 then break end -- 单条过多高亮会拖慢渲染
            end
        end
        return s
    end)
    if ok and sp ~= nil then return sp end
    return body
end

--====================================================
-- r27.62 分段加载：过滤结果先存进 当前候选，列表只先渲染前 每页条数 条，
-- 滚动到底再追加。避免"全部"分类一次 adp.add 上万条卡住输入法主线程。
--====================================================
local 每页条数 = 150
local 当前候选 = {}   -- 过滤+排序后的完整原文（1-based，对应最终 position）
local 已渲染 = 0      -- 已 addLine 的条数

-- 渲染单行（时间行用等级色，正文命中处高亮；同步写入 显示行 供长按用）
local function addLine(line)
    local t, body = splitLogLine(line)
    local lvColor = levelColor(line)
    local n = 已渲染 + 1
    显示行[n] = line
    adp.add({
        item = { background = itemBg() },
        log_time = { text = t, textColor = lvColor },
        log_content = { text = 高亮(body), textColor = C.textColor },
    })
    已渲染 = n
end

local function 刷新提示()
    setTip(已渲染)
    if 已过滤 or 已渲染 < #当前候选 then
        ids.searchInfo.setText(string.format("%d/%d", 已渲染, 总条数))
    else
        ids.searchInfo.setText("")
    end
end

-- 追加下一批；first=true 表示首屏（随后 makeAdapter 会 setAdapter，无需 notify）
local function 渲染下一批(first)
    local from = 已渲染 + 1
    local to = math.min(已渲染 + 每页条数, #当前候选)
    if from > to then return false end
    for i = from, to do addLine(当前候选[i]) end
    已渲染 = to
    刷新提示()
    if not first then pcall(function() adp.notifyDataSetChanged() end) end
    return 已渲染 < #当前候选
end

-- 渲染到覆盖 idx（供"清除筛选并跳转"定位未首屏渲染的行）
local function 渲染到(idx)
    local guard = 0
    while 已渲染 < idx and guard < 1000 do
        if not 渲染下一批(false) then break end
        guard = guard + 1
    end
end

function makeAdapter()
    adp.clear()
    显示行 = {}
    当前候选 = {}
    已渲染 = 0

    local total = 0
    local function accept(line)
        total = total + 1
        return 命中(line, 搜索词)
    end

    -- ▼▼ 数据源分支：只做过滤，收集完整候选，不立即 addLine ▼▼
    if currentCat == #CATEGORIES then
        -- LuaActivity 内部日志（print / Lua 错误）
        actLogs = LuaActivity.logs
        if isReverse then
            for i = actLogs.size() - 1, 0, -1 do
                local line = actLogs.get(i)
                if accept(line or "") then 当前候选[#当前候选 + 1] = line end
            end
        else
            local it = actLogs.iterator()
            while it.hasNext() do
                local line = it.next()
                if accept(line or "") then 当前候选[#当前候选 + 1] = line end
            end
        end
    else
        -- logcat 日志：缓存一次，按分类+关键字过滤，最后按顺序/倒序收集
        local logs = javaLogs()
        local matcher = MATCHERS[currentCat] or MATCHERS[1]
        local filtered = {}
        for _, line in ipairs(logs) do
            if matcher(line) and accept(line) then
                filtered[#filtered + 1] = line
            end
        end
        if isReverse then
            for i = #filtered, 1, -1 do 当前候选[#当前候选 + 1] = filtered[i] end
        else
            for i = 1, #filtered do 当前候选[#当前候选 + 1] = filtered[i] end
        end
    end

    总条数 = total
    已过滤 = 搜索词 ~= ""
    渲染下一批(true)   -- 首屏只渲染 150 条
    ids.list.setAdapter(adp)
end

--====================================================
-- 分类气泡弹窗（GridView + 仿微信气泡背景）
--====================================================

-- 气泡格子背景：选中高亮，未选中卡片色
local function bubbleBg(selected)
    if selected then
        return roundRect(C.accent, dp2px(8), nil, 5)
    end
    return roundRect(C.cardBg, dp2px(8), nil, 5)
end

-- 生成单个分类气泡视图
local function makeBubble(text, selected)
    local btn = (function()
        local b = toolBtn(text);
        b.id = "btn";
        b.layout_width = "wrap";
        b.layout_weight = "1"; 
        b.textColor = selected and Color.WHITE or toColor(C.textColor);
        b.background = bubbleBg(selected);
        b.clickable = false;   -- 点击事件交给 GridView.onItemClick
        b.focusable = false;
        return b
    end)();

    return loadlayout(btn)
end

local Long = luajava.bindClass("java.lang.Long")
local selectedPos = currentCat - 1 -- GridView 下标从 0 开始
local gridAdapter = BaseAdapter.override({
    getCount = function(_)
        return #CATEGORIES
    end,
    getItem = function(_, pos)
        return CATEGORIES[pos + 1]
    end,
    getItemId = function(_, pos)
        return Long(pos)
    end,
    getView = function(_, position, convertView, parent)
        return makeBubble(
        CATEGORIES[position + 1],
        position == selectedPos
        )
    end
})()

local grid = GridView(this)
grid.setNumColumns(4) -- 每行 4 列
grid.setVerticalSpacing(dp2px(5))
grid.setGravity(Gravity.CENTER)
grid.setPadding(dp2px(6), dp2px(18), dp2px(6), dp2px(6))
grid.setAdapter(gridAdapter)

local popup = PopupWindow(
grid,
ViewGroup.LayoutParams.WRAP_CONTENT,
ViewGroup.LayoutParams.WRAP_CONTENT,
-- r27.60: focusable 必须为 false。
-- 设为 true 时气泡弹出会抢走输入法窗口焦点，触发 trime 的 onWindowHidden
-- 把键盘收起；点选分类后就必须重新点输入框才能弹出。
-- 非 focusable 气泡仍能点击选项（GridView 消费 touch），但不再抢焦点。
false
)
popup.setOutsideTouchable(true)  -- 点气泡外部可关闭
popup.setFocusable(false)

--====================================================
-- BubbleDrawable：仿微信对话气泡
-- 尖角支持四个方向，自动根据锚点位置对齐并限制在安全边距内
--====================================================
function BubbleDrawable(backgroundColor)
    local self = {}
    local tipPos = 0.5        -- 尖角在所在边上的位置（0~1）
    local tipHeight = 32      -- 尖角高度（凸起长度） 内容区域需要对应偏移
    local tipWidth = 43       -- 尖角底部宽度
    local tipRadius = 18      -- 尖角圆润半径（越大越圆）
    local cornerRadius = 16
    local bubble

    local Direction = { UP = 1, DOWN = 2, LEFT = 3, RIGHT = 4 }
    local direction = Direction.UP

    local targetView = nil
    local anchorCenterX = 0
    local anchorCenterY = 0
    local listener = nil

    -- 绘制向上的气泡（尖角在顶边），cx 为尖角中心 x，top 为主体顶边 y
    local function tipOnTop(path, w, h, pos)
        local th, tw, tr, r = tipHeight, tipWidth / 2, tipRadius, cornerRadius
        local cx = w * pos
        local rootCurve = tw * 0.5

        path.moveTo(r, th)
        path.quadTo(0, th, 0, th + r)
        path.lineTo(0, h - r)
        path.quadTo(0, h, r, h)
        path.lineTo(w - r, h)
        path.quadTo(w, h, w, h - r)
        path.lineTo(w, th + r)
        path.quadTo(w, th, w - r, th)
        path.lineTo(cx + tw + rootCurve, th)
        path.quadTo(cx + tw, th, cx + tw * 0.45, tr * 0.6)
        path.quadTo(cx + tw * 0.18, 0, cx, 0)
        path.quadTo(cx - tw * 0.18, 0, cx - tw * 0.45, tr * 0.6)
        path.quadTo(cx - tw, th, cx - tw - rootCurve, th)
        path.lineTo(r, th)
        path.close()
    end

    -- 尖角在底边（朝下），主体占据 0 ~ h-th
    local function tipOnBottom(path, w, h, pos)
        local th, tw, tr, r = tipHeight, tipWidth / 2, tipRadius, cornerRadius
        local by = h - th          -- 主体底边 y
        local cx = w * pos
        local rootCurve = tw * 0.5

        path.moveTo(r, 0)
        path.quadTo(0, 0, 0, r)
        path.lineTo(0, by - r)
        path.quadTo(0, by, r, by)
        -- 底边左侧 → 尖角左根部
        path.lineTo(cx - tw - rootCurve, by)
        path.quadTo(cx - tw, by, cx - tw * 0.45, h - tr * 0.6)
        path.quadTo(cx - tw * 0.18, h, cx, h)
        path.quadTo(cx + tw * 0.18, h, cx + tw * 0.45, h - tr * 0.6)
        path.quadTo(cx + tw, by, cx + tw + rootCurve, by)
        -- 底边右侧 + 右下圆角 + 右边 + 右上圆角
        path.lineTo(w - r, by)
        path.quadTo(w, by, w, by - r)
        path.lineTo(w, r)
        path.quadTo(w, 0, w - r, 0)
        path.lineTo(r, 0)
        path.close()
    end

    -- 尖角在左边（朝左），主体占据 th ~ w；尖角沿垂直方向定位
    local function tipOnLeft(path, w, h, pos)
        local th, tw, tr, r = tipHeight, tipWidth / 2, tipRadius, cornerRadius
        local cy = h * pos         -- 尖角中心 y
        local rootCurve = tw * 0.5

        path.moveTo(th, r)
        path.quadTo(th, 0, th + r, 0)
        path.lineTo(w - r, 0)
        path.quadTo(w, 0, w, r)
        path.lineTo(w, h - r)
        path.quadTo(w, h, w - r, h)
        path.lineTo(th + r, h)
        path.quadTo(th, h, th, h - r)
        -- 左边下段 → 尖角下根部
        path.lineTo(th, cy + tw + rootCurve)
        path.quadTo(th, cy + tw, tr * 0.6, cy + tw * 0.45)
        path.quadTo(0, cy + tw * 0.18, 0, cy)
        path.quadTo(0, cy - tw * 0.18, tr * 0.6, cy - tw * 0.45)
        path.quadTo(th, cy - tw, th, cy - tw - rootCurve)
        -- 左边上段收尾
        path.lineTo(th, r)
        path.close()
    end

    -- 尖角在右边（朝右），主体占据 0 ~ w-th
    local function tipOnRight(path, w, h, pos)
        local th, tw, tr, r = tipHeight, tipWidth / 2, tipRadius, cornerRadius
        local bx = w - th          -- 主体右边 x
        local cy = h * pos
        local rootCurve = tw * 0.5

        path.moveTo(r, 0)
        path.quadTo(0, 0, 0, r)
        path.lineTo(0, h - r)
        path.quadTo(0, h, r, h)
        path.lineTo(bx - r, h)
        path.quadTo(bx, h, bx, h - r)
        -- 右边下段 → 尖角下根部
        path.lineTo(bx, cy + tw + rootCurve)
        path.quadTo(bx, cy + tw, w - tr * 0.6, cy + tw * 0.45)
        path.quadTo(w, cy + tw * 0.18, w, cy)
        path.quadTo(w, cy - tw * 0.18, w - tr * 0.6, cy - tw * 0.45)
        path.quadTo(bx, cy - tw, bx, cy - tw - rootCurve)
        -- 右边上段 + 右上圆角收尾
        path.lineTo(bx, r)
        path.quadTo(bx, 0, bx - r, 0)
        path.lineTo(r, 0)
        path.close()
    end

    local BubbleDrawableClass = luajava.override(Drawable, {
        draw = function(super, canvas)
            local w = canvas.getWidth()
            local h = canvas.getHeight()
            local path = Path()
            local paint = Paint()
            paint.setColor(Color.parseColor(backgroundColor or "#FF54A02F"))
            paint.setStyle(Paint.Style.FILL)
            paint.setAntiAlias(true)

            if direction == Direction.DOWN then
                tipOnBottom(path, w, h, tipPos)
            elseif direction == Direction.LEFT then
                tipOnLeft(path, w, h, tipPos)
            elseif direction == Direction.RIGHT then
                tipOnRight(path, w, h, tipPos)
            else
                tipOnTop(path, w, h, tipPos)
            end

            canvas.drawPath(path, paint)
        end,

        getOpacity = function(super)
            return PixelFormat.TRANSLUCENT
        end,

        setAlpha = function(super, alpha) end,
        setColorFilter = function(super, cf) end,
    })

    -- 内部：按方向选择正确的轴重新计算 tip 位置
    -- 水平方向气泡用 X 轴，垂直方向气泡用 Y 轴
    local function updateTip()
        if not targetView then return end
        local ploc = int[2]
        targetView.getLocationOnScreen(ploc)

        local size, anchor, pos
        if direction == Direction.LEFT or direction == Direction.RIGHT then
            -- 尖角沿垂直边：用高度和锚点 Y
            size = targetView.getHeight()
            anchor = anchorCenterY
            pos = ploc[1]      -- 顶部 y
        else
            -- 尖角沿水平边：用宽度和锚点 X
            size = targetView.getWidth()
            anchor = anchorCenterX
            pos = ploc[0]      -- 左边缘 x
        end
        if size == 0 then return end

        local tp = (anchor - pos) / size
        -- 限制尖角不越过圆角安全区
        local margin = (tipWidth / 2 + cornerRadius + 8) / size
        if tp < margin then tp = margin end
        if tp > 1 - margin then tp = 1 - margin end

        tipPos = tp
        if bubble then bubble.invalidateSelf() end
    end

    local function new()
        bubble = BubbleDrawableClass()
        return {
            drawable = bubble,
            Direction = Direction,   -- 暴露枚举给外部
            -- 尖角在所在边上的位置（0~1）
            setTipPosition = function(pos)
                tipPos = pos
                if bubble then bubble.invalidateSelf() end
            end,
            -- 尖角底部宽度
            getTipWidth = function() return tipWidth end,
            setTipWidth = function(tw)
                tipWidth = tw
                if bubble then bubble.invalidateSelf() end
            end,
            -- 尖角高度（凸起长度）
            getTipHeight = function() return tipHeight end,
            setTipHeight = function(th)
                tipHeight = th
                if bubble then bubble.invalidateSelf() end
            end,
            -- 整体圆角
            getCornerRadius = function() return cornerRadius end,
            setCornerRadius = function(radius)
                cornerRadius = radius
                if bubble then bubble.invalidateSelf() end
            end,
            -- 绑定到 内容视图，自动监听布局
            attach = function(view)
                targetView = view
                listener = OnGlobalLayoutListener({
                    onGlobalLayout = function() updateTip() end
                })
                view.getViewTreeObserver().addOnGlobalLayoutListener(listener)
            end,
            -- 设置锚点（点击按钮的屏幕中心坐标）
            setAnchorCenterX = function(x) anchorCenterX = x end,
            setAnchorCenterY = function(y) anchorCenterY = y end,
            setDirection = function(d)
                direction = d
                if bubble then bubble.invalidateSelf() end  -- 先保证重绘
                updateTip()                                  -- 再按新轴重算位置
            end,
            -- 刷新位置
            refresh = function()
                if targetView then
                    targetView.post(Runnable({
                        run = function() updateTip() end
                    }))
                end
            end,
            -- 解绑（关键，防止 ViewTreeObserver 持有引用造成内存泄漏）
            detach = function()
                if targetView and listener then
                    targetView.getViewTreeObserver()
                        .removeOnGlobalLayoutListener(listener)
                end
                targetView = nil
                listener = nil
            end,
        }
    end

    return new()
end

local bubble = BubbleDrawable(C.bubbleBg) -- 背景色仅支持RGB字符串
bubble.setCornerRadius(21)
popup.setBackgroundDrawable(bubble.drawable)

-- 绑定到 popup 内容视图，自动监听布局
bubble.attach(grid)

-- 预先 measure 出 popup 内容宽度（WRAP_CONTENT 时显示前 width 为 0）
grid.measure(
View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
)

-- 点击「分类」按钮：弹出气泡选择框，尖角指向按钮中心
ids.cat.onClick = function(v)
    local loc = int[2]
    v.getLocationOnScreen(loc)
    -- 设置锚点x,y（左右方向必须记录 Y）
    bubble.setAnchorCenterX(loc[0] + v.getWidth() / 2)
    bubble.setAnchorCenterY(loc[1] + v.getHeight() / 2)
    -- 尖角方向：UP / DOWN / LEFT / RIGHT 或 1 2 3 4
    bubble.setDirection(bubble.Direction.UP)
    popup.showAsDropDown(v, 0, dp2px(5), Gravity.START)
    -- 刷新
    bubble.refresh()
end

ids.cat.setText(CATEGORIES[currentCat])

-- 点击某个分类气泡：切换数据源并刷新列表
grid.onItemClick = function(parent, view, position, id)
    selectedPos = position
    currentCat = position + 1
    标记起点 = nil   -- r27.60: 分类切换后 position 语义变化，清标记

    -- setSelected(view.Text ~= "崩溃") 
    
    gridAdapter.notifyDataSetChanged()
    ids.list.post(Runnable({
            run = function() makeAdapter() end
        }))
                    
    ids.cat.setText(view.Text)
    popup.dismiss()
    
    -- 注意：这里不能 bubble.detach()，否则下次打开弹窗时
    -- OnGlobalLayoutListener 已被移除，尖角不会跟随锚点更新。
    -- detach 统一放到 mDestroy 中执行。
end

--====================================================
-- r27.62 滚动到底自动加载下一批（分段渲染）
-- 只在还有未渲染行时加载；用 post 投递，避免在 onScroll 回调里直接改 adapter
--====================================================
local 正在加载下一批 = false
ids.list.setOnScrollListener(luajava.createProxy(
    "android.widget.AbsListView$OnScrollListener", {
        onScroll = function(view, first, visible, total)
            if 正在加载下一批 then return end
            if first + visible >= total - 4 and 已渲染 < #当前候选 then
                正在加载下一批 = true
                ids.list.post(function()
                    pcall(function() 渲染下一批(false) end)
                    正在加载下一批 = false
                end)
            end
        end,
        onScrollStateChanged = function(view, state) end,
    }))

--====================================================
-- 列表交互：点击上屏，长按复制
--====================================================
ids.list.post(function() makeAdapter() end)

--====================================================
-- 搜索输入:完整照抄自定义剪切板 "添加短语" 的流程
--   1) 准备添加短语 → 返回("输入")      切换到键盘视图
--   2) dialog.show()                   在键盘上方弹出带 EditText 的 overlay
--   3) 保存/取消 → dialog.dismiss() + 返回("脚本")  切回脚本视图
-- 三者缺一不可:只切视图不开弹窗没有输入框;只开弹窗不切视图则面板盖住/焦点不通。
--====================================================
local function 应用搜索()
    搜索词 = 搜索原始:lower()
    makeAdapter()
    if ids.list.getAdapter() ~= nil and ids.list.getAdapter().getCount() > 0 then
        ids.list.setSelection(0)
    end
end

-- 搜索框是 TextView(非 EditText),用 setText 显示关键字,空则显示灰色提示
local function 同步搜索框文本(t)
    if t == nil or t == "" then
        ids.search.setText("")
        pcall(function() ids.search.setHint("搜索日志…") end)
    else
        ids.search.setText(t)
    end
end

local 搜索弹窗 = nil
local 已销毁 = false

-- 第3步:关闭弹窗并切回脚本视图
local function 关闭弹窗并回面板()
    if 搜索弹窗 ~= nil then
        pcall(function() 搜索弹窗.dismiss() end)
        搜索弹窗 = nil
    end
    显示面板()
end

-- 应用输入框里的内容(确定/回车共用)
local function 确认搜索(edit, 关闭)
    local t = ""
    pcall(function() t = tostring(edit.getText() or "") end)
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    搜索原始 = t
    搜索词 = t:lower()
    标记起点 = nil   -- r27.60: 搜索词变化，清标记
    同步搜索框文本(t)
    if 关闭 then 关闭弹窗并回面板() end
    ids.search.post(function() 应用搜索() end)
end

-- 第1、2步:切到键盘 + 弹出输入框
local function 打开搜索弹窗()
    if 已销毁 then return end
    if 搜索弹窗 ~= nil then return end   -- 防重复

    -- ① 先点亮输入界面给弹窗打字用("输入"模式会收起启动器等脚本面板)
    显示键盘(true)

    local ok, err = pcall(function()
        local d2 = {}
        local lay = {
            LinearLayout,
            orientation = "vertical",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = C.cardBg,
            padding = "10dp",
            {
                EditText,
                id = "edit",
                layout_width = "fill",
                layout_height = "wrap",
                text = 搜索原始 or "",
                textSize = "15sp",
                textColor = C.textColor,
                hint = "输入关键字,回车确认",
                textColorHint = C.tipColor,
                singleLine = true,
                imeOptions = "actionSearch",
                paddingLeft = "10dp",
                paddingRight = "10dp",
                paddingTop = "8dp",
                paddingBottom = "8dp",
                background = roundRect(C.pageBg, dp2px(8), C.stroke, 0),
            },
            {
                LinearLayout,
                orientation = "horizontal",
                layout_width = "fill",
                layout_height = "wrap",
                layout_marginTop = "8dp",
                {
                    Button, id = "ok",
                    layout_width = "0dp", layout_weight = "1",
                    layout_height = "wrap", text = "确定",
                    textSize = "14sp", textColor = C.btnText,
                    background = ripple(), AllCaps = false,
                },
                {
                    Button, id = "cancel",
                    layout_width = "0dp", layout_weight = "1",
                    layout_height = "wrap", text = "取消",
                    textSize = "14sp", textColor = C.btnText,
                    background = ripple(C.tipColor, C.accentPress), AllCaps = false,
                },
            },
        }
        local view = loadlayout(lay, d2)

        -- 与剪贴板完全一致的窗口设置；工具模式用普通对话框（独立 Activity，无需 SYSTEM_ALERT_WINDOW 权限）
        local dlg
        if 工具模式 then
            dlg = LuaDialog(activity)
        else
            local displayManager = this.getSystemService(Context.DISPLAY_SERVICE)
            local defaultDisplay = displayManager.getDisplay(Display.DEFAULT_DISPLAY)
            local displayContext = this.createDisplayContext(defaultDisplay)
            dlg = LuaDialog(displayContext)
        end
        dlg.view = view
        local window = dlg.getWindow()
        window.clearFlags(WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        if not 工具模式 then
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) then
                window.setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY)
            else
                window.setType(WindowManager.LayoutParams.TYPE_SYSTEM_ALERT)
            end
        end

        d2.ok.onClick = function() 确认搜索(d2.edit, true) end
        d2.cancel.onClick = function() 关闭弹窗并回面板() end
        d2.edit.setOnEditorActionListener(luajava.createProxy("android.widget.TextView$OnEditorActionListener", {
            onEditorAction = function(v, actionId, event)
                确认搜索(d2.edit, true)
                return true
            end,
        }))
        -- 点弹窗外部/返回键:视为取消,但也要切回面板
        dlg.setOnDismissListener(luajava.createProxy("android.content.DialogInterface$OnDismissListener", {
            onDismiss = function(d)
                if 搜索弹窗 ~= nil then
                    搜索弹窗 = nil
                    显示面板()
                end
            end,
        }))

        搜索弹窗 = dlg
        dlg.show()
        d2.edit.requestFocus()
        pcall(function() d2.edit.setSelection(d2.edit.getText().length()) end)
        pcall(function()
            local imm = this.getSystemService(Context.INPUT_METHOD_SERVICE)
            imm.showSoftInput(d2.edit, InputMethodManager.SHOW_IMPLICIT)
        end)
    end)
    if not ok then
        搜索弹窗 = nil
        显示面板()
        print("搜索弹窗出错:" .. tostring(err))
    end
end

-- 点击搜索框
ids.search.onClick = function(v)
    打开搜索弹窗()
end

-- 清空搜索
ids.clearSearch.onClick = function(v)
    搜索原始 = ""
    搜索词 = ""
    标记起点 = nil   -- r27.60: 列表变化，清标记
    同步搜索框文本("")
    makeAdapter()
    if ids.list.getAdapter() ~= nil and ids.list.getAdapter().getCount() > 0 then
        ids.list.setSelection(0)
    end
end

ids.list.onItemClick = function(l, v, p, i)
    上屏或复制(v.Tag.log_content.Text.."\n")
end

--====================================================
-- r27.60 长按菜单：用非 focusable 的气泡式 PopupWindow，避免抢焦点收起键盘
-- 选项表：{ {文字, 回调}, ... }
--====================================================
local function 关闭长按菜单()
    if 菜单popup ~= nil then
        pcall(function() 菜单popup.dismiss() end)
        菜单popup = nil
    end
end

local function 显示长按菜单(anchor, 选项)
    关闭长按菜单()
    local box = LinearLayout(this)
    box.setOrientation(LinearLayout.VERTICAL)
    box.setBackgroundDrawable(roundRect(C.cardBg, dp2px(8), C.stroke, 0))
    for _, item in ipairs(选项) do
        local tv = TextView(this)
        tv.setText(item[1])
        tv.setTextColor(toColor(C.textColor))
        tv.setTextSize(14)
        tv.setPadding(dp2px(16), dp2px(11), dp2px(16), dp2px(11))
        tv.setClickable(true)
        -- 原生 TextView 用 setOnClickListener + createProxy 绑定点击（最可靠）
        local cb = item[2]
        tv.setOnClickListener(luajava.createProxy(
            "android.view.View$OnClickListener", {
                onClick = function()
                    关闭长按菜单()
                    pcall(cb)
                end,
            }))
        box.addView(tv)
    end
    菜单popup = PopupWindow(box, ViewGroup.LayoutParams.WRAP_CONTENT,
        ViewGroup.LayoutParams.WRAP_CONTENT, false)
    菜单popup.setOutsideTouchable(true)
    菜单popup.setFocusable(false)
    -- r27.61: 改为「向上 + 相对锚点水平居中」弹出，并夹在屏幕内，避免超出屏幕
    -- WRAP_CONTENT 时 show 前 getWidth/getHeight 为 0，先手动 measure 得到真实尺寸
    local spec = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
    box.measure(spec, spec)
    local pw, ph = box.getMeasuredWidth(), box.getMeasuredHeight()
    -- 锚点屏幕坐标（与 showAtLocation 的 x/y 同一坐标系）
    local loc = int[2]
    pcall(function() anchor.getLocationOnScreen(loc) end)
    local dm = this.getResources().getDisplayMetrics()
    local sw, sh = dm.widthPixels, dm.heightPixels
    local margin = dp2px(8)
    -- 水平：以锚点中心居中，再夹进屏幕左右边界
    local x = loc[0] + anchor.getWidth() / 2 - pw / 2
    if x < margin then x = margin end
    if x + pw > sw - margin then x = sw - pw - margin end
    -- 垂直：优先贴在锚点上方；上方空间不够则翻到下方
    local y = loc[1] - ph
    if y < margin then
        y = loc[1] + anchor.getHeight()
        if y + ph > sh - margin then y = sh - ph - margin end
    end
    if y < margin then y = margin end
    pcall(function()
        菜单popup.showAtLocation(anchor, Gravity.NO_GRAVITY,
            math.floor(x), math.floor(y))
    end)
end

-- 取从起点到当前（position）之间的整行原文，条目之间用换行连接
-- 支持倒序：起点 position 可能大于当前 position，按显示顺序取区间
local function 取范围文本(起点pos, 当前pos)
    local lo, hi = math.min(起点pos, 当前pos), math.max(起点pos, 当前pos)
    local parts = {}
    for k = lo, hi do
        local line = 显示行[k + 1]
        if line ~= nil then parts[#parts + 1] = line end
    end
    return table.concat(parts, "\n"), #parts
end

ids.list.onItemLongClick = function(l, v, p, i)
    local 当前原文 = 显示行[p + 1]
    if 当前原文 == nil then return true end
    local 选项 = {}
    if 搜索词 ~= "" then
        -- 有筛选：复制当前条目 + 清除筛选并定位到当前条目
        选项 = {
            { "复制", function()
                copy(当前原文)
            end },
            { "清除筛选并跳转到当前位置", function()
                -- 记住当前条目的整行原文，清除筛选后在完整列表里定位它
                local 目标 = 当前原文
                搜索原始 = ""
                搜索词 = ""
                同步搜索框文本("")
                makeAdapter()
                -- r27.62: 先在新候选里定位原文（首屏可能未渲染到该行），
                -- 用 渲染到 加载到覆盖它后再 setSelection。
                local 目标行 = nil
                for k = 1, #当前候选 do
                    if 当前候选[k] == 目标 then 目标行 = k; break end
                end
                if 目标行 ~= nil then
                    渲染到(目标行)
                    local 目标pos = 目标行 - 1
                    if ids.list.getAdapter() ~= nil
                        and ids.list.getAdapter().getCount() > 目标pos then
                        ids.list.setSelection(目标pos)
                    end
                end
            end },
        }
    else
        -- 无筛选
        if 标记起点 == nil then
            -- 未标记：复制 + 标记（设起点）
            选项 = {
                { "复制", function() copy(当前原文) end },
                { "标记", function()
                    标记起点 = p
                end },
            }
        else
            -- 已标记：清除标记 + 上屏到当前 + 复制（范围）
            选项 = {
                { "清除标记", function() 标记起点 = nil end },
                { "上屏标记到此条目", function()
                    local text = 取范围文本(标记起点, p)
                    if text ~= "" then 上屏或复制(text .. "\n") end
                end },
                { "复制", function()
                    local text = 取范围文本(标记起点, p)
                    copy(text)
                end },
            }
        end
    end
    显示长按菜单(v, 选项)
    return true   -- 消费长按，避免触发 onItemClick 上屏
end

--====================================================
-- 顺序 / 倒序切换
--====================================================
function setSelected(a)
    if a then
        ids.order.setText("序↑")
        ids.order.setSelected(false)
    else
        ids.order.setText("序↓")
        ids.order.setSelected(true)
    end
end

setSelected(isReverse)

ids.order.onClick = function(v)

    setSelected(v.isSelected())
    isReverse = not v.isSelected()
    标记起点 = nil   -- r27.60: 倒序改变行顺序，清标记
    makeAdapter()
end

--====================================================
-- 清除：同时清空 LuaActivity 内部日志和 logcat 缓冲区
--====================================================
ids.clear.onClick = function()
    if actLogs ~= nil and actLogs.size() > 0 then actLogs.clear() end
    
    clearJavaLogs()
    标记起点 = nil   -- r27.60: 清空日志，清标记
    makeAdapter()
end

-- 返回：先销毁释放资源，再切回默认键盘
ids.back.onClick = function()
    mDestroy()
    if 工具模式 then
        activity.finish()
    end
   -- local Keyboard_default = {send = "Eisu_toggle", select = "default" }
   -- this.sendEvent(Keyboard_default)
end

--====================================================
-- 复制到剪贴板
--====================================================
function copy(text)
    local clipboard = this.getSystemService(Context.CLIPBOARD_SERVICE)
    clipboard.setPrimaryClip(ClipData.newPlainText("code", text))
    print("[ LuaActivityLogs.lua ] 已复制到剪贴板")
end

--====================================================
-- 资源销毁（防内存泄漏，幂等）
--====================================================
local destroyed = false

function mDestroy()
    if destroyed then return end
    destroyed = true

    -- 0. 清理:关搜索弹窗、面板移出容器、恢复输入界面
    pcall(function()
        已销毁 = true
        if 搜索弹窗 ~= nil then
            搜索弹窗.dismiss()
            搜索弹窗 = nil
        end
        显示键盘()
    end)

    -- 1. popup 收起（分类气泡 + r27.60 长按菜单）
    if popup ~= nil then
        if popup.isShowing() then popup.dismiss() end
        popup = nil
    end
    关闭长按菜单()
    标记起点 = nil
    显示行 = {}
    -- r27.62: 释放分段加载持有的候选/缓存，避免面板关闭后继续占内存
    当前候选 = {}
    日志缓存 = nil

    -- 2. bubble 解绑监听器（关键，防泄漏）
    if bubble ~= nil and bubble.detach ~= nil then
        bubble.detach()
    end
    bubble = nil

    -- 3. 移除布局
    if layout ~= nil then
        local parent = layout.getParent()
        if parent ~= nil and parent.indexOfChild(layout) ~= -1 then
            parent.removeView(layout)
        end
        layout = nil
    end

    -- 4. 断开真正占内存的引用
    convertView = nil
    adp = nil
    gridAdapter = nil
    actLogs = nil

    -- 5. 触发 GC（按需开启）
    -- collectgarbage("collect")
end

return nil
