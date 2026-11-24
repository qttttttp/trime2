name = "莫兰迪"
author = "Gemini"
background = 0xffe2e2e2 -- 燕麦色背景

--键盘
keyboard = {
    height = 240,
    background = 0xffe2e2e2
}

--默认按键样式
key = {
    text_color = 0xff5b5b5b,
    text_size = 22,
    background = 0xfff5f5f5, -- 浅燕麦色
    elevation = 2,
    corner_radius = 8,
    shadow_color = 0x20000000,
    long_click_time = 1000,
    repeat_click_time = 200
}
key.margins = { left = 3, top = 3, right = 3, bottom = 4 }
key.hint = {
    show = true,
    text_color = 0xff999999,
    text_size = 12
}
key.hint.up = { show=true, text_color = 0xff999999, text_size = 12 }
key.hint.down = { show=true, text_color = 0xff999999, text_size = 12 }
key.hint.left = { show=true, text_color = 0xff999999, text_size = 12 }
key.hint.right = { show=true, text_color = 0xff999999, text_size = 12 }

key.long_click = {
    show = true,
    text_color = 0xff8ca6b8, -- 雾霾蓝提示
    text_size = 12,
    vibration_enabled = true,
}
key.pressed = {
    scale_x = 0.95,
    scale_y = 0.95,
    translation_z = 4,
    background = 0xffdcdcdc,
    text_color = 0xff5b5b5b,
}
key.preview = {
    text_color = 0xff5b5b5b,
    text_size = 26,
    background = 0xfff5f5f5,
    elevation = 12,
    corner_radius = 12,
    stroke_color = 0xff8ca6b8,
    stroke_width = 1,
    shadow_color = 0x40000000
}

space = table.clone(key)
space.text_size = 18

--回车键（灰绿）
enter = table.clone(key)
enter.text_size = 18
enter.background = 0xff94a684
enter.text_color = 0xffffffff
enter.pressed.background = 0xff849674
enter.preview = nil

enter2 = table.clone(enter)
enter2.corner_radius = 32

--功能键（烟粉）
functional = table.clone(key)
functional.text_size = 18
functional.background = 0xffd4a5a5
functional.text_color = 0xffffffff
functional.pressed.background = 0xffc49595
functional.preview = nil

--符号面板
symbol = {
    background = 0xffe2e2e2,
    text_size = 22,
    text_color = 0xff5b5b5b,
    indicator_color = 0xff8ca6b8
}
symbol.key = {
    text_color = 0xff5b5b5b,
    text_size = 18,
    background = 0xffeeeeee,
    elevation = 1,
    corner_radius = 6,
    shadow_color = 0x20000000
}

--候选栏
candidate = {
    height = 48,
    background = 0xffe2e2e2,
    text_size = 22,
    text_color = 0xff4a4a4a,
    elevation = 0,
}
candidate.pressed = {
    background = 0xffd4a5a5, -- 选中变为烟粉色
    text_color = 0xffffffff,
    corner_radius = 4,
}
candidate.comment = { text_size = 12, text_color = 0xff888888 }

--工具栏
toolbar = table.clone(candidate)
toolbar.keys = { { label = "菜单", send = "Control+grave" }, "Mode_switch", "Keyboard_clipboard" }
toolbar.key = table.clone(key)
toolbar.key.background = 0x00000000
toolbar.key.elevation = 0

preedit = {
    text_size = 18,
    text_color = 0xff5b5b5b,
    background = 0x338ca6b8
}

height = keyboard.height + candidate.height
