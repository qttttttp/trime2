name = "编辑键盘"
author = "星乂尘"
flex_box = {
    direction = "row",
    --第一列
    {
        grow = 1,
        direction = "column",
        keys = {
            { click = "Page_Up" },
            { click = "undo" },
            { click = "redo" },
            { click = "Page_Down" },
        }
    },
    --第二列
    {
        grow = 3,
        direction = "column",
        {
            direction = "row",
            keys = {
                { click = "copy" },
                { click = "Up" },
                { click = "paste" },
            }
        },
        {
            direction = "row",
            keys = {
                { click = "Left", swipe_up = "Home", swipe_left = "Home", swipe_right = "End" },
                { click = "Shift_R", swipe_left = "Home", swipe_right = "End" },
                { click = "Right", swipe_up = "End", swipe_left = "Home", swipe_right = "End" },
            }
        },
        {
            direction = "row",
            keys = {
                { click = "select_all" },
                { click = "Down" },
                { click = "cut" },
            }
        }
    },
    --第三列
    {
        grow = 1,
        direction = "column",
        keys = {
            { click = "BackSpace" },
            { click = "space" },
            { click = "Return" },
            { click = "Keyboard_default" }
        }
    }
}
