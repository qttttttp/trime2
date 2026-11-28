name = "复古打字机"
author = "Gemini"
background = 0xff2c2c2c -- 深炭黑背景

--键盘
keyboard = {
    height = 240,
    background = 0xff2c2c2c
}

--默认按键样式
key = {
    text_color = 0xffe8e8e8, -- 近白色文字
    text_size = 22,
    background = 0xff3d3d3d, -- 深灰按键
    elevation = 6,
    corner_radius = 4, -- 较硬朗的圆角
    shadow_color = 0xff000000,
    long_click_time = 1000,
    repeat_click_time = 200
}
key.margins = { left = 4, top = 4, right = 4, bottom = 6 }
key.hint = {
    show = true,
    text_color = 0xff888888,
    text_size = 12
}
key.hint.up = { show=true, text_color = 0xff888888, text_size = 12 }

key.long_click = {
    show = true,
    text_color = 0xffd4af37, -- 古铜金
    text_size = 12,
    vibration_enabled = true,
}
key.pressed = {
    scale_x = 0.92,
    scale_y = 0.92,
    translation_z = 1,
    background = 0xff1a1a1a,
    text_color = 0xffd4af37,
}
key.preview = {
    text_color = 0xffffffff,
    text_size = 28,
    background = 0xff3d3d3d,
    elevation = 20,
    corner_radius = 4,
    stroke_color = 0xffd4af37,
    stroke_width = 2,
    shadow_color = 0xff000000
}

space = table.clone(key)
space.text_size = 18

--回车键（工业红）
enter = table.clone(key)
enter.text_size = 18
enter.background = 0xffa91b0d
enter.text_color = 0xffffffff
enter.pressed.background = 0xff7f140a
enter.preview = nil

--功能键（深灰褐）
functional = table.clone(key)
functional.text_size = 18
functional.background = 0xff1f1f1f
functional.text_color = 0xff888888
functional.pressed.background = 0xff000000
functional.preview = nil

--符号面板
symbol = {
    background = 0xff2c2c2c,
    text_size = 22,
    text_color = 0xffe8e8e8,
    indicator_color = 0xffd4af37
}
symbol.key = {
    text_color = 0xffe8e8e8,
    text_size = 18,
    background = 0xff333333,
    elevation = 2,
    corner_radius = 4,
    shadow_color = 0xff000000
}

--候选栏
candidate = {
    height = 48,
    background = 0xff1a1a1a,
    text_size = 22,
    text_color = 0xffd4af37, -- 选人用金色高亮
    elevation = 4,
}
candidate.pressed = {
    background = 0xff3d3d3d,
    text_color = 0xffffffff,
    corner_radius = 4,
}
candidate.comment = { text_size = 12, text_color = 0xff666666 }

--工具栏
toolbar = table.clone(candidate)
toolbar.keys = { { label = "菜单", send = "Control+grave" }, "Mode_switch", "Keyboard_clipboard" }
toolbar.key = table.clone(key)
toolbar.key.background = 0x00000000
toolbar.key.elevation = 0

preedit = {
    text_size = 18,
    text_color = 0xffe8e8e8,
    background = 0x66000000
}

height = keyboard.height + candidate.height
