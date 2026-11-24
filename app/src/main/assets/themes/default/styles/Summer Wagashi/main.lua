name = "初夏和菓子"
author = "Gemini"
background = 0xfff0f9f4 -- 薄荷淡绿背景

--键盘
keyboard = {
    height = 240,
    background = 0xfff0f9f4
}

--默认按键样式
key = {
    text_color = 0xff6b8e8e, -- 灰绿色文字
    text_size = 22,
    background = 0xffffffff, -- 白瓷色
    elevation = 2,
    corner_radius = 16, -- 极圆润的按键
    shadow_color = 0x15000000,
    long_click_time = 1000,
    repeat_click_time = 200
}
key.margins = { left = 4, top = 4, right = 4, bottom = 4 }
key.hint = {
    show = true,
    text_color = 0xffb2d8d8,
    text_size = 11
}
key.hint.up = { show=true, text_color = 0xffb2d8d8, text_size = 11 }

key.long_click = {
    show = true,
    text_color = 0xffffb7c5, -- 樱花粉
    text_size = 12,
    vibration_enabled = true,
}
key.pressed = {
    scale_x = 0.85, -- 按下缩放更明显，显得Q弹
    scale_y = 0.85,
    background = 0xfffdf2f4, -- 浅粉按下态
    text_color = 0xffffb7c5,
}
key.preview = {
    text_color = 0xff6b8e8e,
    text_size = 28,
    background = 0xffffffff,
    elevation = 10,
    corner_radius = 30,
    stroke_color = 0xffb2d8d8,
    stroke_width = 3,
    shadow_color = 0x20000000
}

space = table.clone(key)
space.background = 0xfffff9e6 -- 柠檬黄空格

--回车键（樱花粉）
enter = table.clone(key)
enter.text_size = 18
enter.background = 0xffffb7c5
enter.text_color = 0xffffffff
enter.pressed.background = 0xffffa1b3
enter.preview = nil

--功能键（淡薄荷）
functional = table.clone(key)
functional.text_size = 18
functional.background = 0xffd1ede1
functional.text_color = 0xff6b8e8e
functional.pressed.background = 0xffbde3d2
functional.preview = nil

--符号面板
symbol = {
    background = 0xfff0f9f4,
    text_size = 22,
    text_color = 0xff6b8e8e,
    indicator_color = 0xffffb7c5
}
symbol.key = {
    text_color = 0xff6b8e8e,
    text_size = 18,
    background = 0xffffffff,
    elevation = 1,
    corner_radius = 12,
    shadow_color = 0x10000000
}

--候选栏
candidate = {
    height = 50,
    background = 0xffffffff,
    text_size = 22,
    text_color = 0xff4f6f6f,
    elevation = 1,
}
candidate.pressed = {
    background = 0xfffdf2f4,
    text_color = 0xffffb7c5,
    corner_radius = 25,
}
candidate.comment = { text_size = 12, text_color = 0xffb2d8d8 }

--工具栏
toolbar = table.clone(candidate)
toolbar.keys = { { label = "菜单", send = "Control+grave" }, "Mode_switch", "Keyboard_clipboard" }
toolbar.key = table.clone(key)
toolbar.key.background = 0x00000000
toolbar.key.elevation = 0

preedit = {
    text_size = 18,
    text_color = 0xff6b8e8e,
    background = 0x22ffb7c5
}

height = keyboard.height + candidate.height
