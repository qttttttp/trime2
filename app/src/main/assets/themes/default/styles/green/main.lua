-- ==========================================
-- 样式名称：薄荷森林 (Mint Forest)
-- 适配版本：Trime 2015 - 2026
-- 作者：nirenr & Gemini
-- ==========================================

name = "薄荷森林"
author = "nirenr & Gemini"

-- 1. 基础全局设置
-- 主背景色：极浅薄荷绿
background = 0xFFE8F5E9

-- 2. 键盘面板 (Keyboard)
keyboard = {
    -- 键盘高度
    height = 240,
    -- 键盘背景
    background = 0xFFE8F5E9
}

-- 3. 默认按键样式 (Key)
key = {
    -- 按键文字颜色：深森林绿
    text_color = 0xFF1B5E20,
    -- 按键文字大小
    text_size = 22,
    -- 按键背景：纯白
    background = 0xFFFFFFFF,
    -- 按键阴影高度
    elevation = 2,
    -- 按键圆角半径
    corner_radius = 10,
    -- 阴影颜色
    shadow_color = 0x332E7D32,
    -- 长按超时
    long_click_time = 1000,
    -- 重复执行间隔
    repeat_click_time = 200
}

-- 按键四周留白
key.margins = {
    left = 3, top = 3, right = 3, bottom = 5
}

-- 按键辅助信息 (Hint & Long Click)
key.hint = {
    -- 助记文字颜色
    text_color = 0xFF4CAF50,
    -- 助记文字大小
    text_size = 12
}
key.long_click = {
    -- 长按文字颜色
    text_color = 0xFF2E7D32,
    -- 长按文字大小
    text_size = 12
}

-- 4. 按键交互状态 (Pressed & Preview)
key.pressed = {
    -- 缩放与位移
    scale_x = 0.95,
    scale_y = 0.95,
    translation_z = 4,
    -- 按下时的视觉反馈
    shadow_color = 0xFF81C784,
    background = 0xFFC8E6C9, -- 按下变为淡绿色
    text_color = 0xFFFFFFFF,
    hint = { text_color = 0xFFFFFFFF },
    long_click = { text_color = 0xFFFFFFFF }
}

-- 按键预览（气泡）
key.preview = {
    text_color = 0xFF1B5E20,
    text_size = 28,
    background = 0xFFFFFFFF,
    elevation = 12,
    corner_radius = 12,
    stroke_color = 0x444CAF50,
    stroke_width = 1,
    shadow_color = 0x44000000
}

-- 5. 特殊键位 (Space / Enter / Functional)
space = table.clone(key)
space.text_size = 18
space.background = 0xFFF1F8E9 -- 空格使用青柠色微调

-- 回车键：充满生机的鲜绿色
enter = table.clone(key)
enter.text_size = 18
enter.background = 0xFF66BB6A
enter.text_color = 0xFFFFFFFF
enter.pressed.background = 0xFF43A047
enter.pressed.text_color = 0xFFFFFFFF
enter.preview = nil

enter2 = table.clone(enter)
enter2.corner_radius = 32

-- 功能键（退格、分词、切换等）
functional = table.clone(key)
functional.text_size = 18
functional.background = 0xFFC8E6C9 -- 灰绿色调
functional.text_color = 0xFF2E7D32
functional.pressed.background = 0xFFA5D6A7
functional.preview = nil

-- 6. 候选栏样式 (Candidate)
-- 对应 CandidateAdapter.java 中的 mCandidateStyle
candidate = {
    height = 50,
    background = 0xFFE8F5E9,
    text_size = 22,
    text_color = 0xFF1B5E20, -- 候选词颜色
    elevation = 0,
    shadow_color = 0x00000000
}

-- 对应 Java 中的 mCandidatePressedStyle (高亮状态)
candidate.pressed = {
    background = 0x334CAF50, -- 选中时的绿色半透明背景
    text_color = 0xFF2E7D32,
    corner_radius = 6,
}

-- 对应 Java 中的 mCommentStyle (候选词注释/拼音)
candidate.comment = {
    text_size = 12,
    text_color = 0xFF66BB6A
}
candidate.comment.pressed = {
    text_size = 12,
    text_color = 0xFF1B5E20
}

-- 7. 符号面板 (Symbol)
symbol = {
    background = 0xFFE8F5E9,
    text_size = 22,
    text_color = 0xFF1B5E20,
    indicator_color = 0xFF43A047
}
symbol.text = table.clone(key)
symbol.key = {
    text_color = 0xFF2E7D32,
    text_size = 18,
    background = 0xFFF1F8E9,
    elevation = 1,
    corner_radius = 8,
    shadow_color = 0x22000000
}
symbol.key.pressed = table.clone(key.pressed)

-- 8. 扩展候选面板 (Expanded Candidate)
candidate.expanded = table.clone(candidate)
candidate.expanded.background = 0xFFE8F5E9
candidate.expanded.text_color = 0xFF1B5E20
candidate.expanded.pressed = {
    background = 0xFFFFFFFF,
    ripple_color = 0x404CAF50,
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
-- 是否显示 Rime 开关
toolbar.schema_switches = false
-- 工具栏按键
toolbar.keys = { { label = "菜单", send = "F4" }, "Mode_switch", "Keyboard_clipboard" }
-- 背景稍深以区分
toolbar.background = 0xFFC8E6C9
toolbar.key = table.clone(candidate.key or key)
toolbar.key.text_size = 20
toolbar.key.background = 0x00000000 -- 背景透明，点击时才有反馈
toolbar.key.padding = { left = 8, top = 0, right = 8, bottom = 0 }

-- 11. 预编辑区样式 (Preedit/编码区)
preedit = {
    text_size = 18,
    text_color = 0xFF2E7D32,
    background = 0x00000000 -- 保持背景透明以融合候选栏
}

-- 12. 总高度计算
height = keyboard.height + candidate.height
