-- ==========================================
-- 样式名称：樱落粉 (Cherry Blossom)
-- 适配版本：Trime 2015 - 2026
-- 作者：nirenr & Gemini
-- ==========================================

name = "樱落粉"
author = "nirenr & Gemini"

-- 1. 基础全局设置
background = 0xFFFCE4EC

-- 2. 键盘面板 (Keyboard)
keyboard = {
    height = 240,
    background = 0xFFFCE4EC -- 浅粉色背景
}

-- 3. 默认按键样式 (Key)
key = {
    text_color = 0xFF880E4F,     -- 深玫瑰色文字
    text_size = 22,
    background = 0xFFFFFFFF,     -- 纯白按键
    elevation = 2,
    corner_radius = 10,
    shadow_color = 0x33AD1457,   -- 淡淡的玫瑰色阴影
    long_click_time = 1000,
    repeat_click_time = 200
}

-- 按键间距
key.margins = {
    left = 3, top = 3, right = 3, bottom = 5
}

-- 按键辅助信息 (Hint & Long Click)
key.hint = {
    text_color = 0xFFF06292,
    text_size = 12
}
key.long_click = {
    text_color = 0xFFC2185B,
    text_size = 12
}

-- 4. 按键交互状态 (Pressed & Preview)
key.pressed = {
    scale_x = 0.95,
    scale_y = 0.95,
    translation_z = 4,
    shadow_color = 0xFFF48FB1,
    background = 0xFFF8BBD0,     -- 按下变为浅粉
    text_color = 0xFFFFFFFF,
    hint = { text_color = 0xFFFFFFFF },
    long_click = { text_color = 0xFFFFFFFF }
}

key.preview = {
    text_color = 0xFF880E4F,
    text_size = 28,
    background = 0xFFFFFFFF,
    elevation = 12,
    corner_radius = 12,
    stroke_color = 0x44F06292,
    stroke_width = 1,
    shadow_color = 0x44000000
}

-- 5. 特殊键位 (Space / Enter / Functional)
space = table.clone(key)
space.text_size = 18
space.background = 0xFFFFF1F1

enter = table.clone(key)
enter.text_size = 18
enter.background = 0xFFFF80AB -- 亮粉色背景
enter.text_color = 0xFFFFFFFF
enter.pressed.background = 0xFFF50057
enter.pressed.text_color = 0xFFFFFFFF
enter.preview = nil

enter2 = table.clone(enter)
enter2.corner_radius = 32

functional = table.clone(key)
functional.text_size = 18
functional.background = 0xFFF8BBD0
functional.text_color = 0xFFAD1457
functional.pressed.background = 0xFFF48FB1
functional.preview = nil

-- 6. 候选栏样式 (Candidate)
-- 对应 CandidateAdapter.java 中的 mCandidateStyle
candidate = {
    height = 50,
    background = 0xFFFCE4EC,
    text_size = 22,
    text_color = 0xFF880E4F,
    elevation = 0,
    shadow_color = 0x00000000
}

-- 对应 Java 代码中的 mCandidatePressedStyle
candidate.pressed = {
    background = 0x33F06292,    -- 选中高亮色
    text_color = 0xFFC2185B,
    corner_radius = 6,
}

-- 对应 Java 代码中的 mCommentStyle
candidate.comment = {
    text_size = 12,
    text_color = 0xFFF06292
}
candidate.comment.pressed = {
    text_size = 12,
    text_color = 0xFFAD1457
}

-- 7. 符号面板 (Symbol)
symbol = {
    background = 0xFFFCE4EC,
    text_size = 22,
    text_color = 0xFF880E4F,
    indicator_color = 0xFFFF4081
}
symbol.text = table.clone(key)
symbol.key = {
    text_color = 0xFFAD1457,
    text_size = 18,
    background = 0xFFFDF2F4,
    elevation = 1,
    corner_radius = 8,
    shadow_color = 0x22000000
}
symbol.key.pressed = table.clone(key.pressed)

-- 8. 扩展候选面板 (Expanded Candidate)
candidate.expanded = table.clone(candidate)
candidate.expanded.background = 0xFFFCE4EC
candidate.expanded.text_color = 0xFF880E4F
candidate.expanded.pressed = {
    background = 0xFFFFFFFF,
    ripple_color = 0x40F06292,
}

candidate.expanded.key = table.clone(symbol.key)
candidate.expanded.key.background = 0xFFFFFFFF

-- 9. 剪贴板样式 (Clipboard)
clipboard = table.clone(candidate.expanded)
clipboard.item = table.clone(key)
clipboard.item.text_size = 14
clipboard.item.padding = { left = 6, top = 6, right = 6, bottom = 6 }

-- 10. 工具栏样式 (Toolbar)
toolbar = table.clone(candidate)
toolbar.schema_switches = false
toolbar.keys = { { label = "菜单", send = "F4" }, "Mode_switch", "Keyboard_clipboard" }
toolbar.background = 0xFFF8BBD0 -- 稍微加深的粉色区分工具栏
toolbar.key = table.clone(candidate.key or key)
toolbar.key.text_size = 20
toolbar.key.background = 0x00000000 -- 背景透明
toolbar.key.padding = { left = 8, top = 0, right = 8, bottom = 0 }

-- 11. 预编辑区样式 (Preedit)
preedit = {
    text_size = 18,
    text_color = 0xFFC2185B,
    background = 0x00000000 -- 透明背景
}

-- 12. 总高度
height = keyboard.height + candidate.height
