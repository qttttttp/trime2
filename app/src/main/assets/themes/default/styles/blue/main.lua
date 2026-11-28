name = "深蓝"
author = "nirenr"
--输入主颜色或图片
background = 0xff333333

--键盘
keyboard = {
    --键盘高度
    height = 240,
    --键盘背景颜色或图片
    background = 0xff333333
}

--默认按键样式
key = {
    --按键文字颜色
    text_color = 0xaa00a1e4,
    --按键文字大小
    text_size = 22,
    --按键背景颜色或图片
    background = 0xff2d2d2d,
    --按键阴影高度
    elevation = 4,
    --按键圆角半径
    corner_radius = 8,
    --按键阴影颜色
    shadow_color = 0xdd00a1e4,
    vibration_enabled = true,--震动开关
    vibration_effect = {
        {0, 12, 10, 20},--时长
        {0, 80, 0, 160} --强度
    },
    sound_enabled = true,--震动开关
    sound_effect="click.ogg"
}
--按键四周留白
key.margins={
    left=2,
    top=2,
    right=2,
    bottom=3
}
--按键助记
key.hint = {
    --助记文字颜色
    text_color = 0xff444444,
    --助记文字大小
    text_size = 12
}
--按键长按
key.long_click = {
    --长按文字颜色
    text_color = 0xff444444,
    --长按文字大小
    text_size = 10,
    vibration_enabled = true,--震动开关
    vibration_effect = {
        {0, 12, 10, 20},--时长
        {0, 80, 0, 160} --强度
    },
    sound_enabled = true,--震动开关
    sound_effect="click.ogg"
}
--按键按下状态
key.pressed = {
    --宽度缩放
    scale_x = 0.9,
    --高度缩放
    scale_y = 0.9,
    --高度改变
    translation_z = 8,
    --水平移动
    translation_x = 0,
    --垂直移动
    translation_y = 0,
    --阴影颜色
    shadow_color = 0xff00a1e4,
    --背景按键颜色或图片
    background = 0xff004e6e,
    text_color = 0xff00a1e4,
    --助记文字颜色
    hint = {
        text_color = 0xff444444,
    },
    --长按文字颜色
    long_click = {
        text_color = 0xff444444,
    }
}

--回车键样式，需要在回车键定义style="enter"
enter=table.clone(key)
enter.sound_effect="enter.ogg"
enter.text_size=18
enter.background = 0xff004e6e
enter.pressed.background = 0xff006174
enter.pressed.text_color = 0xff00a1e4

enter2=table.clone(enter)
enter2.corner_radius = 32
enter2.sound_effect="enter.ogg"

--功能键样式，需要在功能按键定义style="functional"
functional=table.clone(key)
functional.text_size=18
functional.background = 0xff1a1a1a
functional.pressed.background = 0xff222222
functional.pressed.text_color = 0xff00a1e4
space=table.clone(key)
space.sound_effect="space.ogg"
space.text_size=18

--根据key的click自动引用样式
BackSpace=table.clone(key)
BackSpace.sound_effect="del.ogg"

--符号面板
symbol={
    background = 0xff333333,
    text_size = 22,
    text_color = 0xFFA9B2BC,
    indicator_color = 0xff00a1e4
}
symbol.key = {
    text_color = 0xff00a1e4,
    text_size = 18,
    background = 0xff444444,
    elevation = 2,
    corner_radius = 8,
    shadow_color = 0x800000ff
}
symbol.key.pressed = {
    scale_x = 0.9,
    scale_y = 0.9,
    translation_z = -1,
    translation_x = 0,
    translation_y = 0,
    shadow_color = 0xff00a1e4,
    background = 0xff555555,
}


--候选栏样式
candidate = {
    height = 48,
    background = 0xff333333,
    text_size = 20,
    text_color = 0xFFA9B2BC,
    elevation = 2,
    shadow_color = 0xff00a1e4
}

candidate.pressed = {
    background = 0x4488888888,
    text_color = 0xFFA9B2BC,
}
candidate.comment = {
    text_size = 12,
    text_color = 0xff888888
}
candidate.comment.pressed = {
    text_size = 12,
    text_color = 0xff888888
}

candidate.key = {
    text_color = 0xFFA9B2BC,
    text_size = 22,
    background = 0xff333333,
    elevation = 0,
    corner_radius = 8,
    shadow_color = 0xff333333
}
candidate.key.pressed = {
    scale_x = 0.9,
    scale_y = 0.9,
    translation_z = 2,
    translation_x = 0,
    translation_y = 0,
    shadow_color = 0xff333333,
    background = 0xff444444,
}
--候选面板样式
candidate.expanded = {
    background = 0xff333333,
    text_size = 22,
    text_color = 0xFFA9B2BC,
}
candidate.expanded.pressed = {
    background = 0xffffffff,
    ripple_color = 0x40000000,
}
candidate.expanded.comment = {
    text_size = 12,
    text_color = 0xff444444
}

candidate.expanded.key = {
    text_color = 0xFFA9B2BC,
    text_size = 18,
    background = 0xff444444,
    elevation = 2,
    corner_radius = 8,
    shadow_color = 0xff00a1e4
}
candidate.expanded.key.pressed = {
    scale_x = 0.9,
    scale_y = 0.9,
    translation_z = -1,
    translation_x = 0,
    translation_y = 0,
    shadow_color = 0xff00ffff,
    background = 0xffaaaaaa,
}

--剪贴板样式
clipboard=table.clone(candidate.expanded)
clipboard.item=table.clone(key)
clipboard.item.text_size=14
clipboard.item.padding={
    left=4,
    top=4,
    right=4,
    bottom=4
}

--工具栏样式
toolbar=table.clone(candidate)
toolbar.keys={"F4","Mode_switch","Keyboard_clipboard"}
toolbar.key.text_size=20
toolbar.key.padding={
    left=8,
    top=0,
    right=8,
    bottom=0
}

--提示区样式
preedit = {
    text_size = 18,
    text_color = 0xaaaaaaaa,
    background = 0xff222222
}

--总高度
height = keyboard.height + candidate.height

