import "android.icu.util.Calendar";
import "android.icu.util.ChineseCalendar";
import "java.util.Date";

function getLunarDate()
    -- 1. 初始化一个 ChineseCalendar 实例
    local chineseCalendar = ChineseCalendar(Date());
    -- 2. 获取农历年份（注意：ICU 返回的是循环年份计数，需结合其他字段或简单转换）
    -- 获取农历月（注意：0表示正月，11表示腊月）
    local month = chineseCalendar.get(ChineseCalendar.MONTH) + 1;
    -- 获取农历日
    local day = chineseCalendar.get(ChineseCalendar.DAY_OF_MONTH);

    -- 3. 判断是否是闰月
    local isLeapMonth = chineseCalendar.get(ChineseCalendar.IS_LEAP_MONTH) == 1;

    return {(isLeapMonth and "闰" or "") .. getMonthName(month) .. getDayName(day)};
end

function getMonthName(month)
    local months = { "正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月" };
    return months[month];
end

function getDayName(day)
    local days = { "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                   "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                   "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十" };
    return days[day];
end

return getLunarDate()
