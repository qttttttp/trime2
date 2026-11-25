name = "雅白·中国红"
author = "Gemini"

-- 全局背景：雅白色（宣纸感）
background = 0xfff5f5f5

-- 1. 键盘基础配置
keyboard = {
    height = 240,
    background = 0xfff5f5f5
}

-- 2. 默认按键样式
key = {
    -- 文字颜色：深炭灰（比纯黑更高级）
    text_color = 0xff333333,
    text_size = 22,
    -- 按键背景：极浅灰（区分于大背景）
    background = 0xffffffff,
    elevation = 2,
    corner_radius = 8,
    -- 阴影颜色：浅灰色阴影
    shadow_color = 0x22000000
}

key.margins = {
    left=2, top=2, right=2, bottom=3
}

key.hint = {
    text_color = 0xff999999,
    text_size = 11
}

key.long_click = {
    text_color = 0xff999999,
    text_size = 11
}

-- 按键按下状态：激发出鲜艳的朱砂红
key.pressed = {
    scale_x = 0.96,
    scale_y = 0.96,
    translation_z = 2,
    -- 按下变为朱红色
    background = 0xffd32f2f,
    text_color = 0xffffffff,
    shadow_color = 0x44d32f2f,
    hint = { text_color = 0xffeeeeee },
    long_click = { text_color = 0xffeeeeee }
}

-- 3. 特殊按键派生
space = table.clone(key)
space.text_size = 18
-- 空格键略深一点点
space.background = 0xfffafafa

-- 回车键：核心红色点缀
enter = table.clone(key)
enter.text_size = 18
enter.background = 0xffd32f2f
enter.text_color = 0xffffffff
enter.pressed.background = 0xffb71c1c

enter2 = table.clone(enter)
enter2.corner_radius = 32

-- 功能键：使用浅灰色区分
functional = table.clone(key)
functional.text_size = 18
functional.background = 0xffeeeeee
functional.pressed.background = 0xffd32f2f

-- 4. 符号面板
symbol = {
    background = 0xfff5f5f5,
    text_size = 22,
    text_color = 0xff333333,
    indicator_color = 0xffd32f2f
}
symbol.key = table.clone(key)
symbol.key.background = 0xffeeeeee
symbol.key.pressed = table.clone(key.pressed)

-- 5. 候选栏与候选面板
candidate = {
    height = 48,
    background = 0xfff5f5f5,
    text_size = 22,
    text_color = 0xff333333,
    elevation = 0,
}

candidate.pressed = {
    background = 0x22d32f2f, -- 浅红色的选中反馈
    text_color = 0xffd32f2f, -- 文字变红
    corner_radius = 4,
}

candidate.comment = {
    text_size = 12,
    text_color = 0xff999999
}

-- 候选按键（数字键或展开按键）
candidate.key = table.clone(key)
candidate.key.background = 0xfff5f5f5
candidate.key.elevation = 0
candidate.key.pressed = table.clone(key.pressed)

-- 展开面板
candidate.expanded = table.clone(candidate)
candidate.expanded.background = 0xffffffff
candidate.expanded.key = table.clone(candidate.key)
candidate.expanded.key.background = 0xfff0f0f0
candidate.expanded.key.elevation = 1

-- 6. 扩展组件
clipboard = table.clone(candidate.expanded)
clipboard.item = table.clone(key)
clipboard.item.text_size = 14
clipboard.item.padding = { left=4, top=4, right=4, bottom=4 }

toolbar = table.clone(candidate)
toolbar.keys = {"F4", "Mode_switch", "Keyboard_clipboard"}
toolbar.key = table.clone(candidate.key)
toolbar.key.text_color = 0xffd32f2f -- 工具栏图标为朱砂红
toolbar.key.text_size = 22

-- 7. 预编辑区 (拼音串样式)
preedit = {
    text_size = 18,
    text_color = 0xffd32f2f, -- 拼音显示红色
    background = 0x00000000
}

-- 8. 布局计算
height = keyboard.height + candidate.height
