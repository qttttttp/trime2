# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.kts.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# disable obfuscation
-dontobfuscate

# Keep JNI interface
-keep class com.osfans.trime.** { *; }
-keep class android.widget.**
-keepclassmembers class android.widget.** {
    public protected <fields>;
    public protected <methods>;
}
-keepclasseswithmembernames class * {
    native <methods>;
}
# 1. 仅保护类名不被混淆（不进入大括号指定成员）
-keep class com.androlua.**

# 2. 显式保护公开（public）和受保护（protected）的成员
# 这样私有（private）的方法和字段就会因为没有被匹配到而被混淆
-keepclassmembers class com.androlua.** {
    public protected <fields>;
    public protected <methods>;
}
# 1. 仅保护类名不被混淆（不进入大括号指定成员）
-keep class org.luaj.**
-keep class com.vivo.speechsdk.**{*;}

# 2. 显式保护公开（public）和受保护（protected）的成员
# 这样私有（private）的方法和字段就会因为没有被匹配到而被混淆
-keepclassmembers class org.luaj.** {
    public protected <fields>;
    public protected <methods>;
}
# remove kotlin null checks
-assumenosideeffects class kotlin.jvm.internal.Intrinsics {
    static void checkNotNull(...);
    static void checkExpressionValueIsNotNull(...);
    static void checkNotNullExpressionValue(...);
    static void checkReturnedValueIsNotNull(...);
    static void checkFieldIsNotNull(...);
    static void checkParameterIsNotNull(...);
    static void checkNotNullParameter(...);
}

# Uncomment this to preserve the line number information for
# debugging stack traces.
-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile
# OkHttp 相关的可选依赖忽略
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.bouncycastle.jsse.provider.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-keep class com.android.cglib.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# =================================================================
# 🛡️ 精准保护 androidx 包下的视图 (Views) 和适配器 (Adapters)
# =================================================================

# 1. 保护所有继承自 androidx.viewpager2.widget.ViewPager2 或 androidx.constraintlayout.widget.ConstraintLayout 等
# 以及所有在 androidx 包下可能用到的自定义 View 类名
-keep class androidx.** extends android.view.View {
    public protected <fields>;
    public protected <methods>;
}

# 2. 保护 androidx 下的所有 RecyclerView 适配器类名
-keep class * extends androidx.recyclerview.widget.RecyclerView$Adapter

# 3. 显式保护这些适配器内部的公开（public）和受保护（protected）方法/字段
# 确保布局管理器、数据绑定机制能正常反射调用它们
-keepclassmembers class * extends androidx.recyclerview.widget.RecyclerView$Adapter {
    public protected <fields>;
    public protected <methods>;
}

# 4. 保护所有的 RecyclerView$ViewHolder，防止视图持有者由于混淆导致内部的 View 绑定失效
-keep class * extends androidx.recyclerview.widget.RecyclerView$ViewHolder {
    public protected <fields>;
    public protected <methods>;
}
# 1. 保护所有继承自 RecyclerView$LayoutManager 的类名不被混淆
# 确保在 XML 中通过 app:layoutManager="xxx" 引用时，反射机制能找到该类
-keep class * extends androidx.recyclerview.widget.RecyclerView$LayoutManager

# 2. 保护所有布局管理器内部的公开构造方法
# 因为 Android 系统在解析 XML 的 layoutManager 属性时，必须反射调用它们的构造方法
-keepclassmembers class * extends androidx.recyclerview.widget.RecyclerView$LayoutManager {
    public <init>(...);
}
# 如果你还没有 OkHttp 的基础混淆规则，建议一并加上
-keepattributes Signature, InnerClasses, AnnotationDefault

# ---- ML Kit 数字墨水 ----
# 这类 API 通过 Lua 的 luajava.bindClass 反射调用，R8 静态分析看不到引用，
# 不 keep 会被整包裁掉，运行时抛 ClassNotFoundException。
-keep class com.google.mlkit.vision.digitalink.** { *; }
-keep class com.google.mlkit.common.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
# 这些内部实现类必须原样保留（不混淆、不裁剪），否则 ML Kit 运行时会崩。
# 注意：它们内部有一条 https 校验分支，会让 http 地址抛 INSECURE_URL_ERROR。
# 定版之所以能下载 http，是因为它那条分支在字节码里变成了无条件跳转。
# 这个差异无法用 proguard 规则复现（试过 allowoptimization / 完全不 keep 都不行），
# 统一由 tools/patch-dex-https.py 在编译后按字节修正。
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_digital_ink** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_**

# ---- 随包模型解压 ----
# 只被 TrimeService 直接引用，正常保留；这里显式 keep 是为了防止将来把调用挪进 Lua 后被裁。
-keep class com.osfans.trime.mlkit.** { *; }
