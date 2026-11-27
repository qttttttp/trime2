name = "莫奈花园"
author = "Gemini"
background = 0xffe8f1f2 -- 睡莲浅蓝

--键盘
keyboard = {
    height = 240,
    background = 0xffe8f1f2
}

--默认按键样式
key = {
    text_color = 0xff4a5568,
    text_size = 22,
    background = 0xfffef9e7, -- 日光黄
    elevation = 3,
    corner_radius = 12,
    shadow_color = 0x30a3b18a, -- 松叶绿阴影
    long_click_time = 1000,
    repeat_click_time = 200
}
key.margins = { left = 3, top = 3, right = 3, bottom = 5 }
key.hint = {
    show = true,
    text_color = 0xffa3b18a,
    text_size = 11
}
key.hint.up = { show=true, text_color = 0xffa3b18a, text_size = 11 }

key.long_click = {
    show = true,
    text_color = 0xff5e548e, -- 丁香紫
    text_size = 12,
    vibration_enabled = true,
}
key.pressed = {
    scale_x = 0.9,
    scale_y = 0.9,
    translation_z = 2,
    background = 0xfffcf3cf,
    text_color = 0xff5e548e,
}
key.preview = {
    text_color = 0xff4a5568,
    text_size = 28,
    background = 0xfffef9e7,
    elevation = 16,
    corner_radius = 20,
    stroke_color = 0xffdcd3ff,
    stroke_width = 2,
    shadow_color = 0x40a3b18a
}

space = table.clone(key)
space.text_size = 18

--回车键（松叶绿）
enter = table.clone(key)
enter.text_size = 18
enter.background = 0xffa3b18a
enter.text_color = 0xffffffff
enter.pressed.background = 0xff84a59d
enter.preview = nil

--功能键（丁香紫）
functional = table.clone(key)
functional.text_size = 18
functional.background = 0xffdcd3ff
functional.text_color = 0xff5e548e
functional.pressed.background = 0xffc9bbff
functional.preview = nil

--符号面板
symbol = {
    background = 0xffe8f1f2,
    text_size = 22,
    text_color = 0xff4a5568,
    indicator_color = 0xffdcd3ff
}
symbol.key = {
    text_color = 0xff4a5568,
    text_size = 18,
    background = 0xfff4f9f9,
    elevation = 2,
    corner_radius = 10,
    shadow_color = 0x20a3b18a
}

--候选栏
candidate = {
    height = 50,
    background = 0xfff8f9fa,
    text_size = 22,
    text_color = 0xff2f3e46,
    elevation = 2,
}
candidate.pressed = {
    background = 0xffdcd3ff,
    text_color = 0xff5e548e,
    corner_radius = 8,
}
candidate.comment = { text_size = 12, text_color = 0xffa3b18a }

--工具栏
toolbar = table.clone(candidate)
toolbar.keys = { { label = "菜单", send = "Control+grave" }, "Mode_switch", "Keyboard_clipboard" }
toolbar.key = table.clone(key)
toolbar.key.background = 0x00000000
toolbar.key.elevation = 0

preedit = {
    text_size = 18,
    text_color = 0xff2f3e46,
    background = 0x44dcd3ff
}

height = keyboard.height + candidate.height
