local About = [[

【功能列表】
• 获取 GitHub 下载链接
• 跳转浏览器下载
• 代理下载支持
• 代理使用建议：
    · 按稳定性排序
    · 未全部测试
• 内部下载（仅支持直连）
• 内部下载代码来源：
    · 代码手册 - Adam·Eva (ID:1360)

【关于本工具】
HTML 界面由 DeepSeek 生成

【注意事项】
⚠️ 不一定能正常打开，请根据网络环境尝试

【使用方法】
1. 路径：rime/tools/一键更新/main.lua
2. 入口：输入法设置界面 → 工具 → 一键更新

    Copyright © 2026 zums
]]


import "android.webkit.WebView"
import "android.webkit.WebViewClient"
import "android.webkit.WebSettings"
import "android.webkit.CookieManager"
import "android.webkit.WebChromeClient"
import "android.widget.*"
import "android.view.Gravity"
import "android.view.View"

import "com.androlua.LuaDialog"
import "android.app.AlertDialog"
import "android.app.DownloadManager"
import "android.app.ProgressDialog"
import "android.content.Context"
import "android.net.Uri"
import "android.content.Intent"

import "com.androlua.Ticker"
import "java.io.File"

activity.setTitle("中文输入法2 • 一键更新")

--==================== 当前仓库（可在菜单“切换仓库”里改，适配任意公开 GitHub 仓库） ====================
local REPO_PREFS = "gh_download_repo"
local defaultOwner, defaultRepo = "qttttttp", "trime2"
local currentOwner, currentRepo = defaultOwner, defaultRepo

local function loadSavedRepo()
    local ok, o, r = pcall(function()
        local p = activity.getSharedPreferences(REPO_PREFS, Context.MODE_PRIVATE)
        return p.getString("owner", ""), p.getString("repo", "")
    end)
    if ok and o and o ~= "" and r and r ~= "" then
        currentOwner, currentRepo = o, r
    end
end

local function saveCurrentRepo(o, r)
    pcall(function()
        activity.getSharedPreferences(REPO_PREFS, Context.MODE_PRIVATE)
            .edit().putString("owner", o).putString("repo", r).commit()
    end)
end

-- 曾用仓库历史：同一个 prefs 里 "history" 存多行 owner/repo，最新的在最前
local REPO_HISTORY_MAX = 8
local function loadRepoHistory()
    local list = {}
    pcall(function()
        local p = activity.getSharedPreferences(REPO_PREFS, Context.MODE_PRIVATE)
        local s = p.getString("history", "") or ""
        for line in s:gmatch("[^\r\n]+") do
            line = line:match("^%s*(.-)%s*$") or ""
            if line:find("^[^/]+/[^/]+$") and #list < REPO_HISTORY_MAX then
                list[#list + 1] = line
            end
        end
    end)
    return list
end

-- alsoOld：刚被替换下来的那个仓库也一起记进去，
-- 这样第一次切换之后，历史里立刻能看到"上一个仓库"，不用等第二次。
local function pushRepoHistory(o, r, alsoOld)
    local key = o .. "/" .. r
    local list = { key }
    if alsoOld and alsoOld ~= "" and alsoOld ~= key and alsoOld:find("^[^/]+/[^/]+$") then
        list[#list + 1] = alsoOld
    end
    for _, v in ipairs(loadRepoHistory()) do
        if v ~= key and v ~= alsoOld and #list < REPO_HISTORY_MAX then
            list[#list + 1] = v
        end
    end
    pcall(function()
        activity.getSharedPreferences(REPO_PREFS, Context.MODE_PRIVATE)
            .edit().putString("history", table.concat(list, "\n")).commit()
    end)
end

local function removeRepoHistory(key)
    local list = {}
    for _, v in ipairs(loadRepoHistory()) do
        if v ~= key then list[#list + 1] = v end
    end
    pcall(function()
        activity.getSharedPreferences(REPO_PREFS, Context.MODE_PRIVATE)
            .edit().putString("history", table.concat(list, "\n")).commit()
    end)
end

-- 把 HTML 里的占位符替换为当前仓库
local function renderHtml()
    local out = htmlContent
    local owner, repo = currentOwner, currentRepo
    out = out:gsub("__OWNER__", function() return owner end)
    out = out:gsub("__REPO__",  function() return repo  end)
    return out
end

local web

local ids, layout = {}, {
    LinearLayout;
    orientation="vertical";
    layout_width="fill";
    layout_height="fill";
    background="#FFE9E6E6";
    {
        LinearLayout;
        id="loadingLayout";
        orientation="vertical";
        -- gravity="center";
        layout_width="fill";
        layout_height="fill";
        background="#FF2D2D2D";
        {
            ProgressBar;
            id="pro";
            layout_width="fill";
            layout_height="80dp";
            layout_marginTop="80dp";
            indeterminateTintList=activity.getResources().getColorStateList(android.R.color.holo_blue_light); -- 使用系统蓝色
        };
        {
            TextView;
            layout_width="fill";
            layout_height="fill";
            gravity="center";
            textSize="16sp";
            textColor="#FFB0BEC5";
            id="fxtext";
        };
    };
    {
        LinearLayout;
        id="resultLayout";
        layout_width="fill";
        gravity="top|center";
        orientation="vertical";
        layout_height="fill";
        visibility="gone";
        {
            WebView;
            layout_width="fill";
            layout_height="wrap";
            id="webView";
        }
    }
}


htmlContent = [[
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes, viewport-fit=cover">
    <title>中文输入法2 · 一键更新</title>
    <!-- Font Awesome 6 (免费图标库，GitHub风格) -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            -webkit-tap-highlight-color: transparent;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica Neue', 'Noto Sans', sans-serif;
            background-color: #0d1117;  /* GitHub深色背景风格 */
            color: #c9d1d9;
            padding: calc(env(safe-area-inset-top) + 20px) 16px calc(env(safe-area-inset-bottom) + 30px) 16px;
            min-height: 100vh;
        }

        .container {
            max-width: 960px;
            width: 100%;
            margin: 0 auto;
        }

        /* GitHub顶部导航区卡片风格 */
        .gh-header {
            margin-bottom: 24px;
        }

        .repo-header {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 12px;
            margin-bottom: 12px;
        }

        .repo-icon {
            font-size: 32px;
            color: #e6edf3;
        }

        .repo-name {
            font-size: 24px;
            font-weight: 600;
            letter-spacing: -0.3px;
            color: #f0f6fc;
        }

        .repo-name span {
            font-weight: 400;
            color: #8b949e;
        }

        .repo-badge {
            background: #238636;
            color: white;
            font-size: 12px;
            font-weight: 500;
            padding: 4px 12px;
            border-radius: 24px;
            margin-left: 6px;
        }

        .repo-desc {
            color: #8b949e;
            font-size: 14px;
            margin-top: 4px;
            margin-bottom: 18px;
            border-left: 3px solid #3fb950;
            padding-left: 12px;
        }

        /* GitHub 风格统计卡片 (Stars, Forks, Watchers) — 置顶精华 */
        .stats-container {
            background: #161b22;
            border-radius: 12px;
            border: 1px solid #30363d;
            padding: 12px 20px;
            margin-bottom: 24px;
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            justify-content: flex-start;
            gap: 28px;
            backdrop-filter: none;
            box-shadow: 0 1px 2px rgba(0,0,0,0.2);
        }

        .stat-item {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 14px;
            font-weight: 500;
            color: #e6edf3;
            background: transparent;
            padding: 0;
            border-radius: 0;
        }

        .stat-item i {
            font-size: 18px;
            width: 20px;
            color: #8b949e;
        }

        .stat-item .fa-star { color: #e3b341; }
        .stat-item .fa-code-fork { color: #57ab5a; }
        .stat-item .fa-eye { color: #58a6ff; }

        .stat-number {
            font-weight: 600;
            margin-right: 2px;
        }

        /* 一键更新卡片 (置顶) */
        .update-card {
            background: #161b22;
            border: 1px solid #238636;
            border-radius: 16px;
            padding: 18px 20px;
            margin-bottom: 24px;
        }
        .update-title {
            font-size: 16px;
            font-weight: 600;
            color: #7ee787;
            margin-bottom: 12px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .update-status {
            font-size: 13px;
            color: #c9d1d9;
            line-height: 1.6;
            margin-bottom: 14px;
            word-break: break-all;
        }
        .update-btn {
            background: #238636;
            color: #fff;
            border: none;
            padding: 10px 22px;
            border-radius: 30px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 8px;
        }
        .update-btn:hover { background: #2ea043; }
        .update-btn:active { transform: scale(0.97); }
        .switch-repo-btn {
            background: #21262d;
            color: #c9d1d9;
            border: 1px solid #30363d;
            padding: 10px 18px;
            border-radius: 30px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            margin-left: 8px;
        }
        .switch-repo-btn:hover { background: #30363d; color: #fff; }
        .switch-repo-btn:active { transform: scale(0.97); }

        /* 代理卡片 (透明感融入GitHub风格) */
        .proxy-card {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 16px;
            padding: 18px 20px;
            margin-bottom: 28px;
            transition: all 0.2s;
        }

        .proxy-title {
            font-size: 14px;
            font-weight: 600;
            color: #e6edf3;
            margin-bottom: 14px;
            display: flex;
            align-items: center;
            gap: 8px;
        }

        /* 折叠容器：限制高度，超出隐藏 */
        .proxy-options {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            margin-bottom: 16px;
            max-height: 120px;  /* 大约显示3行，约10-12个按钮 */
            overflow-y: auto;
            padding-bottom: 4px;
        }
        
        /* 自定义滚动条（可选） */
        .proxy-options::-webkit-scrollbar {
            height: 4px;
            width: 4px;
        }
        .proxy-options::-webkit-scrollbar-track {
            background: #21262d;
            border-radius: 4px;
        }
        .proxy-options::-webkit-scrollbar-thumb {
            background: #1f6feb;
            border-radius: 4px;
        }
        .proxy-tools {
            display: flex;
            align-items: center;
            gap: 8px;
            margin: 8px 0 4px;
            flex-wrap: wrap;
        }
        .proxy-tools button {
            background: #21262d;
            border: 1px solid #30363d;
            color: #c9d1d9;
            border-radius: 14px;
            padding: 4px 10px;
            font-size: 11px;
            cursor: pointer;
        }
        .proxy-tools button:active { background: #30363d; }
        #probeHint { font-size: 11px; color: #8b949e; }
        .proxy-btn .pname { vertical-align: middle; }
        .proxy-btn .sig { font-size: 10px; margin-left: 5px; vertical-align: middle; }
        .sig.s0 { color: #6e7681; }
        .sig.s1 { color: #3fb950; }
        .sig.s2 { color: #d29922; }
        .sig.s3 { color: #f0883e; }
        .sig.s4 { color: #f85149; }

        .proxy-btn {
            background: #21262d;
            border: 1px solid #30363d;
            color: #c9d1d9;
            padding: 6px 14px;
            border-radius: 30px;
            font-size: 12px;
            font-weight: 500;
            cursor: pointer;
            transition: 0.15s;
            white-space: nowrap;
        }

        .proxy-btn.active {
            background: #1f6feb;
            border-color: #1f6feb;
            color: white;
        }

        .proxy-btn:hover {
            background: #30363d;
            border-color: #8b949e;
        }

        .proxy-custom {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            margin-top: 6px;
        }

        .proxy-custom input {
            flex: 1;
            min-width: 180px;
            background: #0d1117;
            border: 1px solid #30363d;
            border-radius: 30px;
            padding: 8px 16px;
            font-size: 13px;
            color: #e6edf3;
            outline: none;
        }

        /* 自定义代理不是 <input>：点它弹原生输入框。
           WebView 里的可编辑输入框会自建 InputConnection，输入法用 getClipboard、
           按键滑动监听时容易卡住，所以这里只放一个"看起来像输入框"的 div。 */
        .proxy-custom .proxy-input {
            flex: 1;
            min-width: 180px;
            background: #0d1117;
            border: 1px solid #30363d;
            border-radius: 30px;
            padding: 8px 16px;
            font-size: 13px;
            color: #e6edf3;
            box-sizing: border-box;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            cursor: pointer;
        }

        .proxy-custom .proxy-input.empty {
            color: #6e7681;
        }

        /* 真正存值的隐藏域，绝不参与布局 */
        .proxy-custom input[type="hidden"] {
            display: none !important;
        }

        .proxy-custom input:focus {
            border-color: #1f6feb;
        }

        .proxy-custom button {
            background: #21262d;
            border: 1px solid #30363d;
            padding: 8px 20px;
            border-radius: 30px;
            color: white;
            cursor: pointer;
            font-size: 13px;
        }

        .proxy-custom button:hover {
            background: #30363d;
        }

        .proxy-status {
            font-size: 12px;
            color: #7ee787;
            margin-top: 14px;
            padding-top: 12px;
            border-top: 1px solid #30363d;
        }

        /* release卡片 完全GitHub Issue风格 */
        .release-card {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 16px;
            padding: 20px;
            margin-bottom: 20px;
            transition: 0.1s;
        }

        .version-header {
            display: flex;
            flex-wrap: wrap;
            align-items: baseline;
            justify-content: space-between;
            gap: 12px;
            margin-bottom: 12px;
        }

        .version-name {
            font-size: 20px;
            font-weight: 600;
            color: #f0f6fc;
            letter-spacing: -0.2px;
            word-break: break-word;
        }

        .version-badge {
            background: #1f6feb;
            color: white;
            font-size: 11px;
            font-weight: 600;
            padding: 4px 10px;
            border-radius: 40px;
            white-space: nowrap;
        }

        .meta-info {
            display: flex;
            flex-wrap: wrap;
            gap: 16px;
            margin-bottom: 18px;
            font-size: 12px;
            color: #8b949e;
            border-bottom: 1px solid #30363d;
            padding-bottom: 12px;
        }

        .meta-item {
            display: flex;
            align-items: center;
            gap: 5px;
        }

        .changelog {
            background: #0d1117;
            border-radius: 12px;
            padding: 14px 16px;
            margin-bottom: 18px;
            font-size: 13px;
            line-height: 1.5;
            border-left: 3px solid #3fb950;
            color: #b1bac4;
            max-height: 200px;
            overflow-y: auto;
        }

        .changelog-title {
            font-weight: 600;
            color: #58a6ff;
            margin-bottom: 8px;
            font-size: 12px;
        }

        .button-group {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin-top: 6px;
        }

        .btn {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 6px 16px;
            border-radius: 30px;
            font-size: 12px;
            font-weight: 500;
            text-decoration: none;
            transition: 0.15s;
            cursor: pointer;
            border: none;
            background: #21262d;
            color: #c9d1d9;
        }

        .btn-primary {
            background: #144B1F;
            color: #c9d1d9;
            border-radius: 8px;
            border: 1px solid #1B6F2B;
        }
        .btn-primary:hover {
            background: #2ea043;
        }

        .btn-source {
            background: #103978;
            color: #c9d1d9;
        }
        .btn-source:hover {
            background: #388bfd;
        }

        .btn-gh {
            background: #21262d;
            border: 1px solid #30363d;
        }
        .btn-gh:hover {
            background: #30363d;
            border-color: #8b949e;
        }

        .btn-warning {
            background: #9e5a1a;
            color: white;
        }
        .btn-warning:hover {
            background: #b86d1c;
        }

        .btn:active {
            transform: scale(0.97);
        }

        .no-assets {
            background: #21262d;
            padding: 6px 14px;
            border-radius: 30px;
            font-size: 12px;
            color: #e3b341;
            display: inline-flex;
            align-items: center;
            gap: 6px;
        }

        .loading-state {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 24px;
            text-align: center;
            padding: 60px 20px;
        }

        .spinner {
            width: 40px;
            height: 40px;
            margin: 0 auto 16px;
            border: 3px solid #30363d;
            border-top-color: #1f6feb;
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
        }

        @keyframes spin { to { transform: rotate(360deg); } }

        .error-card {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 24px;
            text-align: center;
            padding: 40px 20px;
        }

        .footer {
            margin-top: 48px;
            padding-top: 24px;
            border-top: 1px solid #30363d;
            text-align: center;
            font-size: 12px;
            color: #8b949e;
        }

        /* 弹窗 GitHub 风格 */
        .dialog-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0,0,0,0.7);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 1000;
            backdrop-filter: blur(6px);
        }

        .dialog-box {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 20px;
            max-width: 90%;
            width: 400px;
            overflow: hidden;
            box-shadow: 0 12px 32px rgba(0,0,0,0.5);
        }

        .dialog-title {
            background: #21262d;
            color: #f0f6fc;
            padding: 16px 20px;
            font-size: 16px;
            font-weight: 600;
            border-bottom: 1px solid #30363d;
        }

        .dialog-content {
            padding: 20px;
        }

        .dialog-file {
            background: #0d1117;
            padding: 10px;
            border-radius: 12px;
            font-weight: 500;
            font-size: 13px;
            word-break: break-all;
            margin-bottom: 16px;
            border: 1px solid #30363d;
        }

        .dialog-url-label {
            font-size: 11px;
            color: #8b949e;
            margin-bottom: 4px;
        }

        .dialog-url {
            font-size: 12px;
            font-family: monospace;
            background: #0d1117;
            padding: 10px;
            border-radius: 12px;
            word-break: break-all;
            border: 1px solid #30363d;
            color: #79c0ff;
        }

        .dialog-buttons {
            display: flex;
            border-top: 1px solid #30363d;
        }

        .dialog-buttons button {
            flex: 1;
            background: #161b22;
            border: none;
            padding: 14px;
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            color: #c9d1d9;
            transition: 0.1s;
        }

        .dialog-buttons button:first-child { color: #f85149; }
        .dialog-buttons button:nth-child(2) { border-left: 1px solid #30363d; color: #58a6ff; }
        .dialog-buttons button:last-child { background: #238636; color: white; border-radius: 0 0 8px 0; }

        .dialog-buttons button:active { background: #30363d; }
        .dialog-buttons button:last-child:active { background: #2ea043; }

        @media (max-width: 560px) {
            .stats-container { gap: 16px; justify-content: flex-start; }
            .repo-header { flex-direction: column; align-items: flex-start; }
            .button-group .btn { white-space: normal; }
            .proxy-btn { white-space: normal; word-break: keep-all; }
        }
    </style>
</head>
<body>
<div class="container">
    <!-- GitHub 头部区域 + 统计星星 (仿GitHub顶部风格) -->
    <div class="gh-header">
        <div class="repo-header">
            <i class="fab fa-github repo-icon"></i>
            <div class="repo-name">
                <span>__OWNER__ /</span> <span id="repoName">__REPO__</span>
                <span class="repo-badge" id="repoBadge">Public</span>
            </div>
        </div>
        <div class="repo-desc" id="repoDesc">中文输入法2 · 开源Rime输入法引擎安卓版</div>
    </div>

    <!-- 统计信息置顶 (Stars, Forks, Watchers 与 GitHub 图标准确一致) -->
    <div class="stats-container" id="github-stats">
        <!-- 动态注入星标/分支/观察者，带真实图标 -->
        <div class="stat-item"><i class="fas fa-star"></i> <span class="stat-number" id="starCount">—</span> stars</div>
        <div class="stat-item"><i class="fas fa-code-fork"></i> <span class="stat-number" id="forkCount">—</span> forks</div>
        <div class="stat-item"><i class="fas fa-eye"></i> <span class="stat-number" id="watcherCount">—</span> watchers</div>
    </div>

    <!-- 一键更新输入法卡片 (置顶) -->
    <div class="update-card" id="updateCard">
        <div class="update-title"><i class="fas fa-download"></i> 一键更新输入法 </div>
        <div class="update-status" id="updateStatus">正在检查版本…</div>
        <button class="update-btn" id="updateBtn"><i class="fas fa-sync-alt"></i> 检查更新并安装</button>
        <button class="switch-repo-btn" id="switchRepoBtn"><i class="fas fa-exchange-alt"></i> 切换仓库</button>
    </div>

    <!-- 代理加速卡片 (功能与UI不变，样式适配) -->
    <div class="proxy-card">
        <div class="proxy-title"><i class="fas fa-globe"></i> GitHub 加速代理
             <div style="text-align: right; margin-top: 4px;">
                <button id="toggleProxyExpand" style="background: none; border: none; color: #58a6ff; font-size: 12px; cursor: pointer;">▼ 展开全部</button>
            </div>
        </div>
        <div class="proxy-tools">
            <button id="probeBtn" title="逐个真取一次安装包开头，确认能下到文件才算可用">📶 验证可下载</button>
            <button id="cleanDeadBtn" title="把确认失效的代理（返回网页 / 404 / 连不上）从列表移除">🧹 清理失效</button>
            <button id="resetProxyBtn" title="恢复内置代理列表">↩ 恢复默认</button>
            <span id="probeHint"></span>
        </div>
        <div class="proxy-options" id="proxyOptions"></div>
        <div class="proxy-custom">
            <!-- 只做展示，点击后由 Lua 弹原生输入框；真正选中的值放在隐藏域里 -->
            <div class="proxy-input empty" id="customProxyView" onclick="requestCustomProxyInput()">点击输入自定义代理地址</div>
            <input type="hidden" id="customProxy">
            <button id="applyCustom"><i class="fas fa-check"></i> 使用</button>
        </div>
        <div class="proxy-status" id="proxyStatus">当前: 直连</div>
    </div>

    <div id="content">
        <div class="loading-state">
            <div class="spinner"></div>
            <p>正在加载版本发布...</p>
        </div>
    </div>

    <div class="footer">
        <p><i class="far fa-copyright"></i> 2026 __OWNER__/__REPO__ · 开源协议 GPLv3</p>
    </div>
</div>

<script>
    let currentProxyPrefix = '';
    let allDownloadUrls = [];
    let latestRelease = null;   // 最新 release（loadReleases 里赋值）
    // 当前仓库（由 Lua 端注入，支持在菜单里切换）
    const GH_OWNER = '__OWNER__';
    const GH_REPO  = '__REPO__';
    const REPO_API = 'https://api.github.com/repos/' + GH_OWNER + '/' + GH_REPO;

    //========== 一键更新：本地 tag 记录 / 检查 / 下载安装 ==========
    const TAG_KEY = 'ime_installed_tag_' + GH_OWNER + '_' + GH_REPO;  // 按仓库隔离，避免串味

    function getSavedTag() {
        return localStorage.getItem(TAG_KEY) || '';
    }
    function saveInstalledTag(tag) {
        localStorage.setItem(TAG_KEY, tag);
    }
    // 本机输入法 APK 的安装时间（毫秒），由 Lua 从 PackageManager 读取，不依赖本地存储
    let installTimeMs = 0;
    function getInstallTimeMs() {
        if (installTimeMs > 0) return installTimeMs;
        try {
            const r = LuaBridge.call("getInstallTime");
            installTimeMs = parseInt(r, 10) || 0;
        } catch (e) { installTimeMs = 0; }
        return installTimeMs;
    }
    function fmtTime(ms) {
        if (!ms || ms <= 0) return '未知';
        try { return new Date(ms).toLocaleString('zh-CN', {hour12:false}); }
        catch (e) { return String(ms); }
    }
    // 最新构建时间（毫秒）：优先用 APK 资源的 updated_at，回退到 release.published_at
    function getBuildTimeMs() {
        if (!latestRelease) return 0;
        const apk = pickArmApk(latestRelease);
        let iso = (apk && apk.updated_at) || latestRelease.published_at || latestRelease.created_at;
        const t = iso ? Date.parse(iso) : 0;
        return isNaN(t) ? 0 : t;
    }
    // Lua 下载安装完成后回调这里记录 tag 并刷新状态
    window.onUpdateInstalled = function(tag) {
        if (tag) saveInstalledTag(tag);
        refreshUpdateStatus();
    };

    // 当前代理下回来的不是安装包（多半是错误页）：把它判死，自动换下一个能下载的重试
    window.onUpdateBadProxy = function() {
        const cur = localStorage.getItem('github_proxy_prefix') || '';
        probeState[cur] = { ok: true, dl: false, ms: -1, code: 200, why: 'html', t: Date.now() };
        saveProbeState();
        renderProxyButtons();
        const b = bestProxy();
        if (b.url === null) {
            setProbeHint('当前代理下回来的不是安装包，且没有其它可用代理');
            alert('下载到的不是安装包（代理返回了错误页面）。\n\n请在代理列表里换一个带 ✔ 的地址，或点「📶 测速」重新验证。');
            return;
        }
        if (b.url === cur) return;
        saveProxySetting(b.url);
        setProbeHint('上一个代理下回来的不是安装包，已改用 ' + proxyLabel(b.url));
        alert('下载到的不是安装包（代理返回了错误页面）。\n已自动改用：' + proxyLabel(b.url) + '\n即将重新下载。');
        setTimeout(function () { try { checkUpdateAndInstall(); } catch (e) {} }, 300);
    };

    function pickArmApk(release) {
        if (!release || !release.assets) return null;
        const apks = release.assets.filter(a => a.name && a.name.toLowerCase().endsWith('.apk'));
        if (apks.length === 0) return null;
        // arm64 优先
        apks.sort((a, b) => {
            const ax = a.name.toLowerCase().includes('arm64') ? 1 : 0;
            const bx = b.name.toLowerCase().includes('arm64') ? 1 : 0;
            if (ax !== bx) return bx - ax;
            return a.name.localeCompare(b.name);
        });
        return apks[0];
    }

    function refreshUpdateStatus() {
        const el = document.getElementById('updateStatus');
        if (!el) return;
        if (!latestRelease) {
            el.innerHTML = '<i class="fas fa-spinner fa-spin"></i> 正在检查版本…';
            return;
        }
        const latest = latestRelease.tag_name || latestRelease.name || '';
        const buildMs = getBuildTimeMs();
        const installMs = getInstallTimeMs();
        // 主判断：构建时间晚于本机安装时间即视为有新构建（留 60 秒容差）
        const hasNew = (buildMs > 0 && installMs > 0)
            ? (buildMs > installMs + 60000)
            : null;  // 取不到时间则退回 tag 判断

        const buildLine = '构建：' + fmtTime(buildMs) + '<br>安装：' + fmtTime(installMs);
        if (hasNew === true) {
            el.innerHTML = '<i class="fas fa-exclamation-triangle" style="color:#e3b341;"></i> <b>发现新构建：</b>' + latest
                + '<br><span style="color:#8b949e;">' + buildLine + '</span>';
        } else if (hasNew === false) {
            el.innerHTML = '<i class="fas fa-check-circle" style="color:#3fb950;"></i> <b>已是最新：</b>' + latest
                + '<br><span style="color:#8b949e;">' + buildLine + '</span>';
        } else {
            // 时间不可用时回退到 tag 记录
            const saved = getSavedTag();
            if (saved && saved === latest) {
                el.innerHTML = '<i class="fas fa-check-circle" style="color:#3fb950;"></i> 已是最新：<b>' + latest + '</b>';
            } else {
                el.innerHTML = '<i class="fas fa-info-circle" style="color:#58a6ff;"></i> 最新版本：<b>' + latest + '</b>'
                    + '<br><span style="color:#8b949e;">无法读取安装时间，按 tag 判断 · 本地：' + (saved || '未记录') + '</span>';
            }
        }
    }

    function checkUpdateAndInstall() {
        if (!latestRelease) {
            alert('版本信息尚未加载，请稍候或点菜单「刷新」。');
            return;
        }
        const latest = latestRelease.tag_name || latestRelease.name || '';
        const buildMs = getBuildTimeMs();
        const installMs = getInstallTimeMs();
        const saved = getSavedTag();
        // 有时间用时间判断；取不到则回退 tag
        if (buildMs > 0 && installMs > 0) {
            if (buildMs <= installMs + 60000) {
                alert('已是最新版本。\n本机安装：' + fmtTime(installMs) + '\n最新构建：' + fmtTime(buildMs) + '\n无需更新。');
                return;
            }
        } else if (saved && saved === latest) {
            alert('已是最新版本：' + latest + '\n无需更新。');
            return;
        }
        const apk = pickArmApk(latestRelease);
        if (!apk) {
            alert('该版本（' + latest + '）的发布资产里没有找到 APK 文件。');
            return;
        }
        // 关键：下载前先用当前选中的代理前缀处理真实直链，和原版下载链路一致
        const finalUrl = applyProxy(apk.browser_download_url, currentProxyPrefix);
        const safeTag = latest.replace(/\|/g, '_');
        const msg = 'updateApk:' + finalUrl + '|' + safeTag + '|' + apk.name;
        LuaBridge.call(msg);
    }

    // LuaBridge 原生调用（内部下载器适配器）
    const LuaBridge = {
        call: function(message) {
            try {
                return prompt("LuaBridge:" + message);
            } catch (e) {
                console.error("Lua通信失败: " + e);
                return null;
            }
        }
    };
    
    // ===== 自定义代理输入（原生输入框桥） =====
    // 页面里不放可编辑的 <input>：WebView 的 InputConnection 会让输入法在
    // this.getClipboard()、按键滑动监听上卡死，所以点这个 div 时交给 Lua 弹原生 EditText。
    function getCustomProxyValue() {
        const hid = document.getElementById('customProxy');
        return hid ? (hid.value || '') : '';
    }
    function setCustomProxyValue(v) {
        v = v || '';
        const hid = document.getElementById('customProxy');
        if (hid) hid.value = v;
        const view = document.getElementById('customProxyView');
        if (!view) return;
        if (v) {
            view.textContent = v;
            view.classList.remove('empty');
        } else {
            view.textContent = '点击输入自定义代理地址';
            view.classList.add('empty');
        }
    }
    window.requestCustomProxyInput = function () {
        LuaBridge.call('askProxyInput:' + encodeURIComponent(getCustomProxyValue()));
    };
    // Lua 端输入完成后回填；有值就直接等同点了「使用」
    window.applyCustomProxyValue = function (v) {
        setCustomProxyValue(v);
        const btn = document.getElementById('applyCustom');
        if (btn && String(v || '').trim()) btn.click();
    };

    let proxyExpanded = false;
    const toggleBtn = document.getElementById('toggleProxyExpand');
    const proxyOptions = document.querySelector('.proxy-options');
    
    if (toggleBtn && proxyOptions) {
        toggleBtn.onclick = () => {
            proxyExpanded = !proxyExpanded;
            proxyOptions.style.maxHeight = proxyExpanded ? 'none' : '120px';
            toggleBtn.innerHTML = proxyExpanded ? '▲ 收起' : '▼ 展开全部';
        };
    }
    
    // 三按钮弹窗（保留原生逻辑）
    function showWebDialog(fileName, downloadUrl) {
        const existingOverlay = document.querySelector('.dialog-overlay');
        if (existingOverlay) existingOverlay.remove();

        const overlay = document.createElement('div');
        overlay.className = 'dialog-overlay';
        overlay.innerHTML = `
            <div class="dialog-box">
                <div class="dialog-title"><i class="fas fa-download"></i> 确认下载</div>
                <div class="dialog-content">
                    <div class="dialog-file"><i class="fas fa-file"></i> ${escapeHtml(fileName)}</div>
                    <div class="dialog-url-label"><i class="fas fa-link"></i> 下载链接</div>
                    <div class="dialog-url">${escapeHtml(downloadUrl)}</div>
                </div>
                <div class="dialog-buttons">
                    <button id="dialogCancel">取消</button>
                    <button id="dialogInside">内部下载</button>
                    <button id="dialogConfirm">下载</button>
                </div>
            </div>
        `;
        document.body.appendChild(overlay);
        document.body.style.overflow = 'hidden';

        const confirmBtn = overlay.querySelector('#dialogConfirm');
        const insideBtn = overlay.querySelector('#dialogInside');
        const cancelBtn = overlay.querySelector('#dialogCancel');

        const closeDialog = () => {
            overlay.remove();
            document.body.style.overflow = '';
        };
        
        confirmBtn.onclick = (e) => {
           // window.location.href = downloadUrl;
            LuaBridge.call("confirmBtnClick:" + downloadUrl);
            closeDialog();
        };
        
        insideBtn.onclick = () => {
            closeDialog();
            LuaBridge.call("insideBtnClick:" + downloadUrl);
        };
        
        cancelBtn.onclick = closeDialog;
        overlay.onclick = (e) => { if (e.target === overlay) closeDialog(); };
    }

    // 获取仓库统计数据并更新顶部(符合真实统计)
    async function fetchRepoStatsAndUpdate() {
        try {
            const response = await fetch(REPO_API);
            if (!response.ok) return;
            const repo = await response.json();
            document.getElementById('starCount').innerText = (repo.stargazers_count || 0).toLocaleString();
            document.getElementById('forkCount').innerText = (repo.forks_count || 0).toLocaleString();
            document.getElementById('watcherCount').innerText = (repo.watchers_count || 0).toLocaleString();
        } catch (error) {
            console.warn("无法获取仓库统计", error);
            document.getElementById('starCount').innerText = '?';
            document.getElementById('forkCount').innerText = '?';
            document.getElementById('watcherCount').innerText = '?';
        }
    }

    // 代理存储
    function saveProxySetting(prefix) {
        localStorage.setItem('github_proxy_prefix', prefix);
        currentProxyPrefix = prefix;
        updateProxyStatus(prefix);
        refreshAllDownloadLinks();
    }

    function updateProxyStatus(prefix) {
        const statusDiv = document.getElementById('proxyStatus');
        if (!prefix) {
            statusDiv.innerHTML = '<i class="fas fa-check-circle"></i> 当前: 直连';
            statusDiv.style.color = '#7ee787';
        } else {
            let displayPrefix = prefix.length > 55 ? prefix.substring(0, 52) + '...' : prefix;
            statusDiv.innerHTML = `<i class="fas fa-rocket"></i> 当前代理: ${displayPrefix}`;
            statusDiv.style.color = '#7ee787';
        }
    }

    // 把已经套过代理的地址还原成 GitHub 原始直链，避免二次拼接出废链
    function cleanProxiedUrl(u) {
        let s = String(u || '');
        // 1) ?q= 形式：https://ghfast.top/?q=https%3A%2F%2Fgithub.com%2F...
        const i = s.indexOf('?q=');
        if (i > 0) {
            const rest = s.substring(i + 3);
            try {
                const d = decodeURIComponent(rest);
                if (/^https?:\/\//i.test(d)) return d;
            } catch (e) {
                if (/^https?:\/\//i.test(rest)) return rest;
            }
        }
        // 2) 前缀形式：https://gh-proxy.org/https://github.com/... 或 .../?https://github.com/...
        let m = s.match(/^https?:\/\/[^\/]+\/+\??(https?:\/\/.+)$/);
        if (m) return m[1];
        // 3) host 形式：https://cors.isteed.cc/github.com/owner/...
        m = s.match(/^https?:\/\/[^\/]+\/github\.com(\/.+)$/);
        if (m) return 'https://github.com' + m[1];
        return s;
    }

    // 拼接代理：三种前缀形态自动识别
    //   ?q=  → 前缀 + 编码后的整条 URL
    //   / ?  → 前缀 + 整条 URL
    //   其它 → 前缀 + 路径部分（xget 的 /gh、cors.isteed 的 /github.com、raw.ihtw 的 /github.com）
    function applyProxy(url, proxyPrefix) {
        if (!proxyPrefix || !url) return url;
        const cleanUrl = cleanProxiedUrl(url);
        if (/\?q=$/.test(proxyPrefix)) return proxyPrefix + encodeURIComponent(cleanUrl);
        if (/[\/?]$/.test(proxyPrefix)) return proxyPrefix + cleanUrl;
        return proxyPrefix + cleanUrl.replace(/^https?:\/\/[^\/]+/, '');
    }

    function refreshAllDownloadLinks() {
        for (let item of allDownloadUrls) {
            const newUrl = applyProxy(item.originalUrl, currentProxyPrefix);
            item.element.dataset.currentUrl = newUrl;
        }
    }

    function registerDownloadLink(element, originalUrl) {
        const proxiedUrl = applyProxy(originalUrl, currentProxyPrefix);
        element.dataset.originalUrl = originalUrl;
        element.dataset.currentUrl = proxiedUrl;
        allDownloadUrls.push({ element: element, originalUrl: originalUrl });

        element.addEventListener('click', function(e) {
            e.preventDefault();
            const latestUrl = this.dataset.currentUrl || applyProxy(originalUrl, currentProxyPrefix);
            let fileName = "文件";
            if (originalUrl) {
                const urlParts = originalUrl.split('/');
                let lastPart = urlParts[urlParts.length - 1];
                if (lastPart && lastPart.includes('?')) lastPart = lastPart.split('?')[0];
                if (lastPart) fileName = decodeURIComponent(lastPart);
            }
            showWebDialog(fileName, latestUrl);
        });
    }

    function loadProxySetting() {
        const saved = localStorage.getItem('github_proxy_prefix');
        if (saved !== null) {
            currentProxyPrefix = saved;
            updateProxyStatus(saved);
            document.querySelectorAll('.proxy-btn').forEach(btn => {
                if (btn.dataset.proxy === saved) btn.classList.add('active');
                else btn.classList.remove('active');
            });
        } else {
            const defaultBtn = document.querySelector('.proxy-btn[data-proxy=""]');
            if (defaultBtn) defaultBtn.classList.add('active');
        }
        refreshAllDownloadLinks();
    }

    // ===== 代理列表 =====
    // 每条 url 是「拼接前缀」，用 applyProxy() 拼出最终下载地址：
    //   ...?q=       → 前缀 + encodeURIComponent(整条 URL)     （旧式 gh 加速）
    //   .../ 或 ...? → 前缀 + 整条 URL                          （gh-proxy / wget.la / npee）
    //   其它         → 前缀 + 路径部分（/owner/repo/...）        （xget / cors.isteed / raw.ihtw）
    // 内置的默认上屏；候选的只有「真的下到文件」才会自动出现。
    const PROXY_BUILTIN = [
        { url: '',                                  label: '⭕ 直连', direct: true },
        { url: 'https://ghfast.top/?q=',            label: '⚡ ghfast.top' },
        { url: 'https://ghproxy.net/?q=',           label: '📡 ghproxy.net' },
        { url: 'https://gh-proxy.org/',             label: '🪞 gh-proxy.org' },
        { url: 'https://wget.la/',                  label: '🚀 wget.la' },
        { url: 'https://gh.ddlc.top/?q=',           label: '📦 ddlc.top' },
        { url: 'https://gh.idayer.com/?q=',         label: '🇨🇳 idayer' }
    ];

    // 候选池：来自「Github 增强 - 高速下载」脚本（XIU2，v2.6.41）的加速源清单，
    // 默认不上屏；实测能完整取回文件才加入列表，失效的永远不会再占屏。
    const PROXY_CANDIDATES = [
        { url: 'https://gh-proxy.com/',             label: '🆕 gh-proxy.com' },
        { url: 'https://github.akams.cn/?q=',       label: '🆕 akams.cn' },
        { url: 'https://cdn.gh-proxy.org/',         label: '🆕 cdn.gh-proxy' },
        { url: 'https://edgeone.gh-proxy.org/',     label: '🆕 edgeone' },
        { url: 'https://hk.gh-proxy.org/',          label: '🆕 hk.gh-proxy' },
        { url: 'https://gh.h233.eu.org/',           label: '🆕 h233.eu.org' },
        { url: 'https://ghproxy.it/',               label: '🆕 ghproxy.it' },
        { url: 'https://gh.zwy.one/',               label: '🆕 gh.zwy.one' },
        { url: 'https://ghproxy.monkeyray.net/',    label: '🆕 monkeyray' },
        { url: 'https://github.boki.moe/',          label: '🆕 boki.moe' },
        { url: 'https://gh.jasonzeng.dev/',         label: '🆕 jasonzeng' },
        { url: 'https://gh.monlor.com/',            label: '🆕 monlor.com' },
        { url: 'https://github.geekery.cn/',        label: '🆕 geekery.cn' },
        { url: 'https://github.ednovas.xyz/',       label: '🆕 ednovas.xyz' },
        { url: 'https://ghfile.geekertao.top/',     label: '🆕 geekertao' },
        { url: 'https://ghp.keleyaa.com/',          label: '🆕 keleyaa' },
        { url: 'https://gh.chjina.com/',            label: '🆕 chjina.com' },
        { url: 'https://ghpxy.hwinzniej.top/',      label: '🆕 hwinzniej' },
        { url: 'https://cdn.crashmc.com/',          label: '🆕 crashmc' },
        { url: 'https://git.yylx.win/',             label: '🆕 yylx.win' },
        { url: 'https://gitproxy.mrhjx.cn/',        label: '🆕 mrhjx.cn' },
        { url: 'https://ghproxy.cxkpro.top/',       label: '🆕 cxkpro.top' },
        { url: 'https://gh.xxooo.cf/',              label: '🆕 xxooo.cf' },
        { url: 'https://down.npee.cn/?',            label: '🆕 npee.cn' },
        { url: 'https://cors.isteed.cc/github.com', label: '🆕 isteed.cc' },
        { url: 'https://raw.ihtw.moe/github.com',   label: '🆕 ihtw.moe' },
        { url: 'https://xget.xi-xu.me/gh',          label: '🆕 xget' }
    ];

    const PROBE_KEY = 'proxy_probe_state_v2';
    const DEAD_KEY = 'proxy_dead_urls_v1';
    const MANUAL_KEY = 'proxy_manual_pick_v1';
    const PROBE_TTL = 30 * 60 * 1000;   // 30 分钟内的结果直接复用
    const PROBE_CONC = 6;               // 同时测 6 个，太多会互相挤带宽、延迟失真

    let probeState = {};
    try { probeState = JSON.parse(localStorage.getItem(PROBE_KEY) || '{}') || {}; } catch (e) { probeState = {}; }
    let probeMap = {};         // idx -> url
    let probeSeq = 0;
    let probing = false;
    let probePending = 0;
    let probeDone = 0;
    let probeFinished = {};
    let probeQueue = [];
    let probeActive = 0;
    let probeStarted = false;
    let probeTargetUsed = '';
    let probeAgain = false;

    function isManualPick() {
        try { return localStorage.getItem(MANUAL_KEY) === '1'; } catch (e) { return false; }
    }
    function markManualPick() {
        try { localStorage.setItem(MANUAL_KEY, '1'); } catch (e) {}
    }

    function loadDead() {
        try { return JSON.parse(localStorage.getItem(DEAD_KEY) || '[]') || []; } catch (e) { return []; }
    }
    function saveDead(a) { try { localStorage.setItem(DEAD_KEY, JSON.stringify(a)); } catch (e) {} }
    function saveProbeState() { try { localStorage.setItem(PROBE_KEY, JSON.stringify(probeState)); } catch (e) {} }
    function customProxies() {
        try { return JSON.parse(localStorage.getItem('custom_proxies') || '[]') || []; } catch (e) { return []; }
    }
    function setProbeHint(t) {
        const el = document.getElementById('probeHint');
        if (el) el.textContent = t || '';
    }

    // 这一轮要测的：内置 + 候选（自定义地址格式不确定，不测，免得误判失效）
    function probeTargets() {
        const dead = loadDead();
        const out = [];
        // 直连也测：命中时它一定是「最快」的，就不用绕代理
        const add = function (p) {
            if (p.url && dead.indexOf(p.url) >= 0) return;
            if (out.some(function (x) { return x.url === p.url; })) return;
            out.push(p);
        };
        PROXY_BUILTIN.forEach(add);
        PROXY_CANDIDATES.forEach(add);
        return out;
    }

    // 屏幕上显示哪些：内置 + 自定义 + 实测能下到文件的候选
    function proxyList() {
        const dead = loadDead();
        const out = [];
        const push = function (p) {
            if (!p || dead.indexOf(p.url) >= 0) return;
            if (out.some(function (x) { return x.url === p.url; })) return;
            out.push(p);
        };
        PROXY_BUILTIN.forEach(push);
        customProxies().forEach(function (p) { push({ url: p.url, label: p.label, custom: true }); });
        PROXY_CANDIDATES.forEach(function (p) {
            const st = probeState[p.url];
            if (st && st.dl) push({ url: p.url, label: p.label, cand: true });
        });
        return out;
    }

    // 信号强度：✔ 320ms（已验证能下到文件）；其余按失败原因显示
    function sigHtml(p) {
        if (p.custom) return '';
        const st = probeState[p.url];
        if (!st) return '<span class="sig s0">…</span>';
        if (st.dl) {
            const ms = (typeof st.ms === 'number' && st.ms >= 0) ? st.ms : 0;
            const cls = ms < 1000 ? 's1' : (ms < 2500 ? 's2' : 's3');
            return '<span class="sig ' + cls + '">✔ ' + fmtMs(ms) + '</span>';
        }
        const why = st.why || '';
        if (why === 'html') return '<span class="sig s4">⚠ 返回网页</span>';
        if (why === 'json') return '<span class="sig s3">⚠ 返回报错</span>';
        if (why === 'limit') return '<span class="sig s2">⏳ 限流</span>';
        if (why === 'deny') return '<span class="sig s3">🔒 拒绝</span>';
        if (why === 'empty') return '<span class="sig s3">⚠ 空文件</span>';
        if (st.code) return '<span class="sig s4">✖ ' + st.code + '</span>';
        return '<span class="sig s4">✖ 不通</span>';
    }

    function renderProxyButtons() {
        const box = document.getElementById('proxyOptions');
        if (!box) return;
        const cur = localStorage.getItem('github_proxy_prefix') || '';
        box.innerHTML = '';
        proxyList().forEach(function (p) {
            const b = document.createElement('button');
            b.className = 'proxy-btn';
            if (p.custom) b.setAttribute('data-custom', 'true');
            b.setAttribute('data-proxy', p.url);
            b.innerHTML = '<span class="pname">' + escapeHtml(p.label) + '</span>' + sigHtml(p);
            if (p.url === cur) b.classList.add('active');
            b.addEventListener('click', function () {
                markManualPick();
                saveProxySetting(p.url);
                document.querySelectorAll('.proxy-btn').forEach(function (x) { x.classList.remove('active'); });
                this.classList.add('active');
                setCustomProxyValue('');
            });
            box.appendChild(b);
        });
    }

    // 测速靶子：优先用当前仓库最新 APK 的真实直链（就是等下要下的那个文件），
    // 拿不到 release 时退到仓库源码包（同样是二进制，能识破"返回网页"的假加速）。
    function probeTargetUrl() {
        const apk = (typeof latestRelease !== 'undefined' && latestRelease) ? pickArmApk(latestRelease) : null;
        if (apk && apk.browser_download_url) return apk.browser_download_url;
        return 'https://github.com/' + GH_OWNER + '/' + GH_REPO + '/archive/HEAD.zip';
    }

    function probeTarget(prefix) {
        return applyProxy(probeTargetUrl(), prefix);
    }

    // 判定"真的能下载"：只有拿到了文件字节（不是网页/报错页）才算
    function isDownloadable(st) {
        return !!(st && st.dl);
    }

    // 彻底废掉（连不上 / 404 / 返回网页）——「清理失效」只清这些，超时的不动
    function isDeadProxy(st) {
        if (!st || st.dl) return false;
        if (st.why === 'html' || st.why === 'json' || st.why === 'empty') return true;
        if (st.code >= 400 && st.code !== 429 && st.code !== 403) return true;
        return false;
    }

    // 自动选用：只在「验证过能下到文件」的里面挑最快的一个
    function bestProxy() {
        let best = null, bestMs = Infinity;
        probeTargets().forEach(function (p) {
            const st = probeState[p.url];
            if (!isDownloadable(st)) return;
            const ms = (typeof st.ms === 'number' && st.ms >= 0) ? st.ms : 99999;
            if (ms < bestMs) { bestMs = ms; best = p.url; }
        });
        return { url: best, ms: bestMs };
    }

    function proxyLabel(url) {
        const all = PROXY_BUILTIN.concat(customProxies()).concat(PROXY_CANDIDATES);
        for (let i = 0; i < all.length; i++) if (all[i].url === url) return all[i].label;
        return url || '⭕ 直连';
    }

    function fmtMs(ms) {
        return ms < 1000 ? (Math.round(ms) + 'ms') : ((ms / 1000).toFixed(1) + 's');
    }

    // 测完切到最快且「确认能下载」的那条；返回一句说明，没切换时返回空串。
    // 尊重手动选择：手点过、且那条现在也验证能下，就不覆盖。
    function autoPickProxy() {
        if (probing) return '';
        const cur = localStorage.getItem('github_proxy_prefix') || '';
        if (isManualPick() && isDownloadable(probeState[cur])) return '';
        const b = bestProxy();
        if (b.url === null) return '';
        if (b.url === cur) return '';
        saveProxySetting(b.url);
        const name = b.url === '' ? '直连' : (proxyLabel(b.url) + ' ' + fmtMs(b.ms));
        return '已自动选用 ' + name;
    }

    function finishProbe(url) {
        if (probeFinished[url]) return;
        probeFinished[url] = true;
        probeDone++;
        if (probeDone >= probePending) {
            probing = false;
            const targets = probeTargets();
            let ok = 0;
            targets.forEach(function (p) {
                if (isDownloadable(probeState[p.url])) ok++;
            });
            const picked = autoPickProxy();
            setProbeHint('实测 ' + targets.length + ' 个，确认可下载 ' + ok + ' 个'
                + (picked ? ' · ' + picked : (ok ? '' : ' · 保持当前设置')));
            if (probeAgain) {
                // 测的过程中靶子换了（release 刚加载完），用真地址再验一轮
                probeAgain = false;
                setTimeout(function () { probeWithTarget(true); }, 60);
            }
        } else {
            setProbeHint('验证中 ' + probeDone + '/' + probePending);
        }
        renderProxyButtons();
    }

    // Lua 回传：ok=连通，dl=确认真能拿到文件，why=失败原因
    window.proxyProbeResult = function (idx, ok, ms, code, dl, why) {
        const url = probeMap[String(idx)];
        // 直连的 url 是空串，不能用 !url 判断（会被当成没找到，直连结果永远丢失）
        if (url === undefined) return;
        const settled = !!probeFinished[url];
        probeState[url] = {
            ok: !!ok, dl: !!dl, ms: ms, code: code || 0,
            why: why || (ok ? '' : 'fail'), t: Date.now()
        };
        saveProbeState();
        // 已经按超时结算过的迟来结果：只更新状态，不再动计数，免得计数错乱
        if (!settled) {
            probeActive = Math.max(0, probeActive - 1);
            pumpProbe();
        }
        finishProbe(url);
    };

    function startProbeOne(p) {
        const idx = ++probeSeq;
        const startedAt = Date.now();
        probeMap[String(idx)] = p.url;
        probeActive++;
        let sent = false;
        try {
            LuaBridge.call('probeProxy:' + idx + '|' + encodeURIComponent(probeTarget(p.url)));
            sent = true;
        } catch (e) {}
        if (!sent) {
            probeState[p.url] = { ok: false, dl: false, ms: -1, code: 0, why: 'fail', t: startedAt };
            saveProbeState();
            probeActive = Math.max(0, probeActive - 1);
            finishProbe(p.url);
            return;
        }
        // 兜底：Lua 线程卡住时也要结束，别一直停在"验证中"
        setTimeout(function () {
            if (probeFinished[p.url]) return;
            const cur = probeState[p.url];
            // 只有本次还没回结果时才写超时结论（避免覆盖上一轮的旧数据判断）
            if (!cur || !cur.t || cur.t < startedAt) {
                probeState[p.url] = { ok: false, dl: false, ms: -1, code: 0, why: 'timeout', t: Date.now() };
                saveProbeState();
            }
            probeActive = Math.max(0, probeActive - 1);
            pumpProbe();
            finishProbe(p.url);
        }, 12000);
    }

    function pumpProbe() {
        while (probeActive < PROBE_CONC && probeQueue.length > 0) {
            startProbeOne(probeQueue.shift());
        }
    }

    function probeAll(force) {
        if (probing) return;
        const now = Date.now();
        const todo = probeTargets().filter(function (p) {
            const st = probeState[p.url];
            return force || !st || (now - st.t) > PROBE_TTL;
        });
        if (!todo.length) {
            const targets = probeTargets();
            let ok = 0;
            targets.forEach(function (p) { if (isDownloadable(probeState[p.url])) ok++; });
            const picked = autoPickProxy();
            setProbeHint('确认可下载 ' + ok + ' 个（结果 30 分钟内有效）' + (picked ? ' · ' + picked : ''));
            renderProxyButtons();
            return;
        }
        probing = true;
        probePending = todo.length;
        probeDone = 0;
        probeFinished = {};
        probeMap = {};
        probeQueue = todo.slice();
        probeActive = 0;
        setProbeHint('验证中 0/' + todo.length);
        pumpProbe();
    }

    // 拿到 release 信息再测，靶子才是真实的 APK 地址。
    // release 来得比兜底计时器晚时，靶子变了就自动再验一轮。
    function probeWithTarget(force) {
        const t = probeTargetUrl();
        const changed = probeStarted && t !== probeTargetUsed;
        probeStarted = true;
        probeTargetUsed = t;
        if (probing) {
            if (force || changed) probeAgain = true;
            return;
        }
        try { probeAll(force || changed); } catch (e) {}
    }

    function cleanDeadProxies() {
        const dead = loadDead();
        let n = 0;
        // 遍历全部候选（不只是屏幕上显示的），把已经判定失效的永久记下，
        // 以后连测都不用测
        probeTargets().forEach(function (p) {
            if (!p.url) return;   // 直连永远保留
            if (isDeadProxy(probeState[p.url]) && dead.indexOf(p.url) < 0) { dead.push(p.url); n++; }
        });
        if (n) {
            saveDead(dead);
            const picked = autoPickProxy();
            renderProxyButtons();
            setProbeHint('已清理 ' + n + ' 个失效代理' + (picked ? ' · ' + picked : ''));
            return;
        }
        setProbeHint('没有发现可判定为失效的代理（超时的不算）');
    }

    function resetProxyList() {
        saveDead([]);
        // 同时解除「手动指定」，回到测完自动选最快
        try { localStorage.removeItem(MANUAL_KEY); } catch (e) {}
        renderProxyButtons();
        setProbeHint('已恢复默认，正在重新测速…');
        probeAll(true);
    }

    function initProxyButtons() {
        renderProxyButtons();

        const pb = document.getElementById('probeBtn');
        if (pb) pb.addEventListener('click', function () {
            if (probing) { setProbeHint('正在验证中，' + probeDone + '/' + probePending); return; }
            probeAll(true);
        });
        const cb = document.getElementById('cleanDeadBtn');
        if (cb) cb.addEventListener('click', cleanDeadProxies);
        const rb = document.getElementById('resetProxyBtn');
        if (rb) rb.addEventListener('click', resetProxyList);

        // 应用自定义代理（标准化 URL + 存 localStorage + 立即启用）
        const applyBtn = document.getElementById('applyCustom');
        if (applyBtn) {
            applyBtn.addEventListener('click', function () {
                let customUrl = getCustomProxyValue().trim();
                if (!customUrl) return;

                let normalizedUrl = customUrl;
                // 三种写法都接受：...?q=（编码式）、.../ 或 ...?（前缀式）、.../gh（路径式）
                const isQ = /[?&]q=$/.test(normalizedUrl);
                const isPre = /[\/?]$/.test(normalizedUrl);
                const looksPath = /^https?:\/\/[^\/]+\/.+/.test(normalizedUrl);
                if (!isQ && !isPre && !looksPath) {
                    normalizedUrl += normalizedUrl.includes('?') ? '&q=' : '?q=';
                }

                let displayLabel;
                try {
                    const urlObj = new URL(normalizedUrl.includes('?q=') ? normalizedUrl.split('?q=')[0] : normalizedUrl);
                    displayLabel = urlObj.hostname.replace(/^www\./, '').split('.')[0].substring(0, 12);
                } catch (e) {
                    displayLabel = customUrl.substring(0, 15);
                }
                displayLabel = '🔧 ' + displayLabel;

                const list = customProxies();
                if (!list.some(function (p) { return p.url === normalizedUrl; })) {
                    list.push({ url: normalizedUrl, label: displayLabel });
                    localStorage.setItem('custom_proxies', JSON.stringify(list));
                }

                markManualPick();
                saveProxySetting(normalizedUrl);
                renderProxyButtons();
                setTimeout(function () {
                    document.querySelectorAll('.proxy-btn').forEach(function (b) { b.classList.remove('active'); });
                    const nb = Array.from(document.querySelectorAll('.proxy-btn')).find(function (btn) {
                        return btn.dataset.proxy === normalizedUrl;
                    });
                    if (nb) nb.classList.add('active');
                    setCustomProxyValue('');
                }, 20);
            });
        }

        // 打开页面自动验证一次（拿到 release 后靶子才是真实 APK 地址）；
        // 5 秒还没拿到 release 就用源码包兜底先测，别一直空着
        setTimeout(function () { try { probeWithTarget(); } catch (e) {} }, 5000);
    }

    // 加载 Releases (保持原汁原味功能)
    async function loadReleases() {
        try {
            const repoRes = await fetch(REPO_API);
            if (repoRes.ok) {
                const repo = await repoRes.json();
                document.getElementById('repoName').innerHTML = repo.name || GH_REPO;
                const nameSpan = document.querySelector('.repo-name span:first-child');
                if (nameSpan) nameSpan.innerText = (repo.owner && repo.owner.login || GH_OWNER) + ' /';
                document.getElementById('repoDesc').innerText = repo.description || '暂无仓库描述';
                document.title = `${repo.name || GH_REPO} · 下载`;
            }
        } catch(e) { /* 忽略 */ }

        try {
            const releaseRes = await fetch(REPO_API + '/releases');
            const data = await releaseRes.json();
            if (Array.isArray(data) && data.length > 0) latestRelease = data[0];  // releases 首个即最新
            // 已经有真实 APK 直链了，现在开始验证各代理能不能真的下到文件
            probeWithTarget();
            let html = '';
            for (const release of data) {
                const repoHome = 'https://github.com/' + GH_OWNER + '/' + GH_REPO;
                const sourceCodeUrl = `${repoHome}/archive/refs/tags/${release.tag_name}.zip`;
                const sourceCodeTarUrl = `${repoHome}/archive/refs/tags/${release.tag_name}.tar.gz`;
                let changelogHtml = '';
                if (release.body && release.body.trim()) {
                    let cleanBody = release.body.replace(/\\n/g, '<br>').replace(/#{1,3}/g, '');
                    changelogHtml = `<div class="changelog"><div class="changelog-title"><i class="fas fa-list-ul"></i> 更新日志</div>${cleanBody}</div>`;
                } else {
                    changelogHtml = `<div class="changelog"><div class="changelog-title"><i class="fas fa-pen"></i> 更新说明</div><span style="color:#8b949e;">暂无详细说明</span></div>`;
                }
                let assetsHtml = '';
                let hasApk = false;
                for (const asset of release.assets) {
                    if (asset.name.endsWith('.apk')) {
                        assetsHtml += `<a class="btn btn-primary download-link" data-url="${asset.browser_download_url}"><i class="fab fa-android"></i> ${asset.name}</a>`;
                        hasApk = true;
                    } else {
                        assetsHtml += `<a class="btn btn-primary download-link" data-url="${asset.browser_download_url}"><i class="fas fa-paperclip"></i> ${asset.name}</a>`;
                    }
                }
                if (!hasApk && release.assets.length === 0) {
                    assetsHtml = `<span class="no-assets"><i class="fas fa-exclamation-triangle"></i> 此版本暂无 APK 文件</span>`;
                }
                html += `
                    <div class="release-card">
                        <div class="version-header">
                            <span class="version-name">${escapeHtml(release.name || release.tag_name)}</span>
                            <span class="version-badge">${release.prerelease ? '预发布' : 'Latest'}</span>
                        </div>
                        <div class="meta-info">
                            <span class="meta-item"><i class="far fa-calendar-alt"></i> ${new Date(release.published_at).toLocaleDateString()}</span>
                            <span class="meta-item"><i class="fas fa-user-circle"></i> ${escapeHtml(release.author.login)}</span>
                            <span class="meta-item"><i class="fas fa-tag"></i> ${escapeHtml(release.tag_name)}</span>
                        </div>
                        ${changelogHtml}
                        <div class="button-group">
                            ${assetsHtml}
                            <a class="btn btn-source download-link" data-url="${sourceCodeUrl}"><i class="fas fa-code"></i> 源码 ZIP</a>
                            <a class="btn btn-source download-link" data-url="${sourceCodeTarUrl}"><i class="fas fa-file-archive"></i> 源码 TAR</a>
                            <a class="btn btn-gh" href="${repoHome}/tree/${release.tag_name}" target="_blank"><i class="fab fa-github"></i> GitHub</a>
                        </div>
                    </div>
                `;
            }
            document.getElementById('content').innerHTML = html;
            document.querySelectorAll('.download-link').forEach(link => {
                const originalUrl = link.dataset.url;
                if (originalUrl) registerDownloadLink(link, originalUrl);
            });
            refreshUpdateStatus();
        } catch(error) {
            document.getElementById('content').innerHTML = `
                <div class="error-card">
                    <div><i class="fas fa-cloud-download-alt" style="font-size: 42px; color:#f85149;"></i></div>
                    <div style="font-size:18px; font-weight:600; margin:16px 0;">网络请求失败</div>
                    <div style="color:#8b949e; margin-bottom:24px;">无法获取版本信息，请检查网络后刷新</div>
                    <button class="btn btn-warning" onclick="location.reload()"><i class="fas fa-sync-alt"></i> 刷新页面</button>
                </div>`;
        }
    }

    function escapeHtml(str) {
        if (!str) return '';
        return str.replace(/[&<>]/g, function(m) {
            if (m === '&') return '&amp;';
            if (m === '<') return '&lt;';
            if (m === '>') return '&gt;';
            return m;
        });
    }

    // 一键更新按钮绑定
    const updateBtn = document.getElementById('updateBtn');
    if (updateBtn) updateBtn.onclick = checkUpdateAndInstall;
    // 切换仓库按钮：通知 Lua 弹出输入框
    const switchRepoBtn = document.getElementById('switchRepoBtn');
    if (switchRepoBtn) switchRepoBtn.onclick = function() { LuaBridge.call('switchRepo'); };

    // 初始化
    initProxyButtons();
    loadProxySetting();
    refreshUpdateStatus();
    loadReleases();
    fetchRepoStatsAndUpdate();
</script>
</body>
</html>
]]



--参数：url是文件直链,path是目录,file是文件名
local function downloadFile(url, path, filename)
    local downloadManager = activity.getSystemService(Context.DOWNLOAD_SERVICE)
    local dlurl = Uri.parse(url)
    local request = DownloadManager.Request(dlurl)
    -- Lua 5.1 / LuaJ 没有按位或（'|' 是语法错误，整个脚本会加载失败）：
    -- NETWORK_MOBILE=1、NETWORK_WIFI=2，相加即 3，与 1|2 等价。
    request.setAllowedNetworkTypes(DownloadManager.Request.NETWORK_MOBILE
        + DownloadManager.Request.NETWORK_WIFI)

    -- 使用绝对路径
    local destFile = File(path, filename)
    local destUri = Uri.fromFile(destFile)
    request.setDestinationUri(destUri)

    request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
    request.setVisibleInDownloadsUi(true)

    local downloadId = downloadManager.enqueue(request)
    return downloadId
end

--查询状态
local function query(downloadId)
    local downloadManager=activity.getSystemService(Context.DOWNLOAD_SERVICE);
    local downloadQuery = DownloadManager.Query();
    downloadQuery.setFilterById({downloadId});
    local cursor = downloadManager.query(downloadQuery);
    if (cursor ~= nil and cursor.moveToFirst()) then -- 修复1: != 改为 ~=
        local fileUri = cursor.getString(cursor.getColumnIndex(DownloadManager.COLUMN_LOCAL_URI))
        -- 下载请求的状态
        local status = cursor.getInt(cursor.getColumnIndex(DownloadManager.COLUMN_STATUS))
        -- 下载文件的总字节大小
        local totalSize = cursor.getLong(cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)) -- / 1048576.0
        -- 已下载的字节大小
        local downloadedSize = cursor.getLong(cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)) --/ 1048576.0
        cursor.close()
        return fileUri,status,totalSize,downloadedSize
    end
    cursor.close()
end

local function formatSize(bytes)
    if bytes >= 1024 * 1024 * 1024 then
        return string.format("%.2f GB", bytes / (1024 * 1024 * 1024))
    elseif bytes >= 1024 * 1024 then
        return string.format("%.2f MB", bytes / (1024 * 1024))
    elseif bytes >= 1024 then
        return string.format("%.2f KB", bytes / 1024)
    else
        return string.format("%.2f B", bytes)
    end
end

local function toast_dialog(msg)
    local dialog = AlertDialog.Builder(activity)
    .setTitle(msg.title or "下载成功")
    .setMessage(msg.text)
    .setCancelable(false)
    .setNegativeButton(msg.btn or "打开", { onClick = msg.func })
    .setPositiveButton("取消", { onClick = function(v) end })
    local create = dialog.create()
    create.show()
end

--参数：url是文件直链,path是目录,file是文件名
function downloadWithProgress(url, filepath, filename)
    local downloadId = downloadFile(url, filepath, filename)
    local dlg = ProgressDialog(activity)
    dlg.setProgressStyle(ProgressDialog.STYLE_HORIZONTAL);
    --设置进度条的形式为水平进度条
    dlg.setTitle("即将开始下载...")
    dlg.setCancelable(false)--设置是否可以通过点击Back键取消
    dlg.setCanceledOnTouchOutside(false)--设置在点击Dialog外是否取消Dialog进度条
    dlg.setOnCancelListener{
        onCancel=function(l)
            print("将进入后台下载，请在通知栏检查下载进度")
        end}
    dlg.setButton(-1, "取消", function()
        dlg.dismiss()
        ti.stop()
    end)

    dlg.setMax(1)
    dlg.setProgress(0)
    dlg.show()
    local cancel = dlg.getButton(-1)
    cancel.setEnabled(false)
    -- public void android.app.ProgressDialog. setProgress(int)
    -- public void android.app.ProgressDialog. setProgressPercentFormat(java.text.NumberFormat)
    -- public void android.app.ProgressDialog. setProgressNumberFormat(java.lang.String)

    local ti=Ticker()
    ti.Period=100
    ti.onTick=function()
        --事件
        local fileUri,status,totalSize,downloadedSize = query(downloadId)
        if totalSize and totalSize>0 then
            if status==1 then
                dlg.setTitle("等待下载...")
                dlg.setCancelable(true)
                cancel.setEnabled(true) --
            elseif status==2 then
                dlg.setTitle("正在下载...")
                dlg.setMax(totalSize)
                dlg.setProgress(downloadedSize)
                dlg.setProgressNumberFormat("%1d B/ %2d B")
                -- dlg.setProgressNumberFormat("%.2f MB / %.2f MB")  -- 显示两位小数
            elseif status==4 then
                dlg.setTitle("下载暂停...")
                dlg.setCancelable(true)
                cancel.setEnabled(true) --
            elseif status==8 then
                dlg.setTitle("下载成功")
                dlg.setMax(totalSize)
                dlg.setProgress(totalSize)
                local msg = {
                    text = "路径：" .. filepath,
                    func = function(v) end
                }
                -- toast_dialog(msg)
                dlg.dismiss()
                ti.stop()
            elseif status==16 then
                dlg.dismiss()
                ti.stop()
            end
        end
    end
    ti.start()
end

-- 读取本机输入法 APK 的安装/更新时间（毫秒时间戳）
-- 脚本运行在输入法进程内，activity.getPackageName() 即输入法包名
local function getInstallTimeMs()
    local ok, t = pcall(function()
        local pm = activity.getPackageManager()
        local pi = pm.getPackageInfo(activity.getPackageName(), 0)
        return tonumber(pi.lastUpdateTime) or 0
    end)
    if ok and t and t > 0 then return t end
    return 0
end

-- ===== 安装 APK：权限 + FileProvider =====
-- 两个坑都会表现成「没有安装权限 / 装不上」：
-- 1) Android 8 起必须声明 REQUEST_INSTALL_PACKAGES（16 号补丁已加进 manifest），
--    并且用户要在「安装未知应用」里给本应用打开开关，否则系统直接拒绝；
-- 2) targetSdk 24 起不能再把 file:// 交给安装器，会抛 FileUriExposedException，
--    必须换成 FileProvider 的 content:// 地址。
local INSTALL_PERM_REQ = 10021
local apkInstallPending = nil
local lastDownloadId = nil

local function sdkInt()
    local ok, v = pcall(function()
        return luajava.bindClass("android.os.Build$VERSION").SDK_INT
    end)
    return (ok and tonumber(v)) or 0
end

local function canInstallPackages()
    if sdkInt() < 26 then return true end
    local ok, can = pcall(function()
        return activity.getPackageManager().canRequestPackageInstalls()
    end)
    return ok and (can == true)
end

local function openInstallPermissionSettings()
    local pkg = activity.getPackageName()
    local ok = pcall(function()
        local it = Intent("android.settings.MANAGE_UNKNOWN_APP_SOURCES")
        it.setData(Uri.parse("package:" .. pkg))
        activity.startActivityForResult(it, INSTALL_PERM_REQ)
    end)
    if ok then return true end
    return pcall(function()
        local it = Intent("android.settings.APPLICATION_DETAILS_SETTINGS")
        it.setData(Uri.parse("package:" .. pkg))
        activity.startActivityForResult(it, INSTALL_PERM_REQ)
    end)
end

local function launchInstaller(path)
    local uri
    -- 首选 DownloadManager 自己给出的 content:// ：不受存储权限与
    -- FileProvider 路径规则影响，只要还是这次下载的那条记录就能读。
    if lastDownloadId then
        local okD, u = pcall(function()
            return activity.getSystemService(Context.DOWNLOAD_SERVICE)
                .getUriForDownloadedFile(lastDownloadId)
        end)
        if okD and u then uri = u end
    end
    if not uri then
        local ok, u = pcall(function()
            -- manifest 里注册的是 android.content.FileProvider，
            -- authority = 应用包名 + ".fileprovider"
            return luajava.bindClass("android.content.FileProvider").getUriForFile(
                activity, activity.getPackageName() .. ".fileprovider", File(path))
        end)
        if ok and u then uri = u else uri = Uri.fromFile(File(path)) end
    end

    local it = Intent(Intent.ACTION_VIEW)
    it.setDataAndType(uri, "application/vnd.android.package-archive")
    it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    it.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    activity.startActivity(it)
end

-- 从授权页回来就接着装，不用重新下载
local function tryPendingInstall()
    local p = apkInstallPending
    if not p then return end
    if not canInstallPackages() then return end
    -- 有 DownloadManager 记录时，即使路径读不到（没给全盘权限）也能用 content:// 装
    if not lastDownloadId and not File(p).exists() then return end
    apkInstallPending = nil
    local ok = pcall(launchInstaller, p)
    if not ok then
        AlertDialog.Builder(activity)
            .setTitle("需手动安装")
            .setMessage("自动调起安装器失败（系统限制）。\n安装包已保存到：\n" .. p ..
                "\n请到文件管理器里点它安装。")
            .setPositiveButton("知道了", nil)
            .show()
    end
end

-- 授权页返回：onActivityResult
function onActivityResult(req, result, data)
    -- req 可能被 LuaJ 转成整型，也可能是 Java Integer，两种都认
    local code = tonumber(req) or tonumber(tostring(req))
    if code == INSTALL_PERM_REQ then tryPendingInstall() end
end

-- 个别 ROM 的授权页不返回 result，靠 resume 兜底
function onResume()
    if apkInstallPending then tryPendingInstall() end
end

-- 调起系统安装；没有授权就先去授权页，回来自动继续
local function installApkFile(path)
    apkInstallPending = path
    if not canInstallPackages() then
        AlertDialog.Builder(activity)
            .setTitle("需要允许安装未知应用")
            .setMessage("系统默认禁止本应用启动安装器。\n" ..
                "请在接下来的页面里打开「允许安装未知应用」；返回后会自动继续安装，不用重新下载。")
            .setPositiveButton("去开启", function() openInstallPermissionSettings() end)
            .setNegativeButton("取消", function() apkInstallPending = nil end)
            .show()
        return
    end
    tryPendingInstall()
end

-- 下载到的到底是不是安装包：APK 本质是 ZIP，开头必须是 "PK"。
-- 代理出错时经常回 200 + 一页错误网页，DownloadManager 会把它存成 .apk，
-- 等到安装才报"解析包错误"。这里提前拦下，直接换下一个代理重下。
local function fileLooksLikeZip(path)
    local ok, yes = pcall(function()
        local f = File(path)
        if not f.isFile() or f.length() < 4 then return false end
        local ins = luajava.newInstance("java.io.FileInputStream", f)
        local b1 = ins.read()
        local b2 = ins.read()
        pcall(function() ins.close() end)
        return b1 == 80 and b2 == 75   -- 'P' 'K'
    end)
    return ok and yes == true
end

-- 一键更新：下载 APK（链接已由 JS 套好代理前缀）→ 安装 → 回调 JS 记录 tag
local function downloadUpdateApk(url, tag, fileName)
    if not fileName or fileName == "" or not fileName:lower():match("%.apk$") then
        fileName = "update-" .. tostring(tag) .. ".apk"
    end
    local savePath = "/storage/emulated/0/Download/"

    local downloadId = downloadFile(url, savePath, fileName)
    local dlg = ProgressDialog(activity)
    dlg.setProgressStyle(ProgressDialog.STYLE_HORIZONTAL)
    dlg.setTitle("正在下载输入法…")
    dlg.setMessage(fileName)
    dlg.setCancelable(false)
    dlg.setCanceledOnTouchOutside(false)
    dlg.setMax(100)
    dlg.setProgress(0)
    dlg.show()

    local ti = Ticker()
    ti.Period = 150
    ti.onTick = function()
        local ok, fileUri, status, totalSize, downloadedSize = pcall(query, downloadId)
        if not ok or not status then return end
        if totalSize and totalSize > 0 then
            dlg.setProgress(math.floor(downloadedSize * 100 / totalSize))
        end
        if status == 8 then  -- STATUS_SUCCESSFUL
            dlg.dismiss(); ti.stop()
            local full = savePath .. fileName
            lastDownloadId = downloadId
            if not fileLooksLikeZip(full) then
                -- 下回来的不是安装包（多半是代理解析出的错误页），删掉重来
                pcall(function() File(full).delete() end)
                lastDownloadId = nil
                pcall(function()
                    web.loadUrl("javascript:onUpdateBadProxy()")
                end)
                return
            end
            -- 通知 JS 记录本次 tag（用 pcall 防止 loadUrl 异常）
            pcall(function()
                web.loadUrl("javascript:onUpdateInstalled('" .. tostring(tag) .. "')")
            end)
            installApkFile(full)
        elseif status == 16 then  -- STATUS_FAILED
            dlg.dismiss(); ti.stop()
            AlertDialog.Builder(activity)
                .setTitle("下载失败")
                .setMessage("下载未成功。请检查网络或换一个可用的加速代理后重试。")
                .setPositiveButton("确定", nil)
                .show()
        end
    end
    ti.start()
end

local switchRepoDialog  -- WebView 里的「自定义代理地址」不再用网页内输入框：
-- 网页里只放一个 div，点它走这里弹原生 EditText，绕开 WebView 输入框在
-- 输入法 this.getClipboard() / 按键滑动监听上的卡死问题。
local function jsStringLit(v)
    v = tostring(v or "")
    v = v:gsub("\\", "\\\\")
    v = v:gsub("'", "\\'")
    v = v:gsub("\r", "\\r")
    v = v:gsub("\n", "\\n")
    v = v:gsub("<", "\\x3c")
    return "'" .. v .. "'"
end

local function askProxyInputDialog(initial)
    local d = activity.getResources().getDisplayMetrics().density
    local function px(n) return math.floor(n * d + 0.5) end

    local lay = LinearLayout(activity)
    lay.setOrientation(LinearLayout.VERTICAL)
    lay.setPadding(px(20), px(8), px(20), 0)

    local ed = EditText(activity)
    ed.setSingleLine(true)
    ed.setHint("如 https://your-proxy.com/?q=")
    ed.setText(initial or "")
    -- 光标放到末尾：改域名/端口时不用先手动点到后面
    pcall(function() ed.setSelection(ed.getText().length()) end)
    lay.addView(ed, LinearLayout.LayoutParams(-1, -2))

    AlertDialog.Builder(activity)
        .setTitle("自定义代理地址")
        .setMessage("填 http(s)://…?q= 形式的代理前缀；留空表示不用自定义代理")
        .setView(lay)
        .setPositiveButton("确定", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
            onClick = function()
                local v = ed.getText().toString()
                v = v:match("^%s*(.-)%s*$") or v
                pcall(function()
                    web.evaluateJavascript("applyCustomProxyValue(" .. jsStringLit(v) .. ")", nil)
                end)
            end
        }))
        .setNegativeButton("取消", nil)
        .show()
end

-- 判定一次探测结果：拿到的是不是"真正的文件"
-- 只看状态码不够 —— 镜像出错时经常回 200 + 一页 HTML 错误页。
-- 返回 ok（连通）、dl（确认能下到文件）、why（原因标记）
local function classifyProbe(code, ctype, clen, bytes)
    local n = #bytes
    local head = ""
    if n > 0 then
        local take = math.min(n, 48)
        local tmp = {}
        for k = 1, take do tmp[k] = bytes[k] end
        -- Lua 5.2 是 unpack，5.3+ 收到 table.unpack
        local up = table.unpack or unpack
        head = string.char(up(tmp))
    end
    local isZip  = (n >= 4 and bytes[1] == 80 and bytes[2] == 75)   -- "PK"
    local isHtml = head:match("^%s*<") ~= nil
    local isJson = head:match("^%s*[%[{]") ~= nil
    local ct = tostring(ctype or ""):lower()

    if code == 0 then
        return false, false, "fail"
    elseif code == 429 then
        return true, false, "limit"
    elseif code == 403 then
        return true, false, "deny"
    elseif code ~= 200 and code ~= 206 then
        return true, false, "http"
    elseif isZip then
        -- 开头的 PK\x03\x04：APK / ZIP / 源码包，肯定是文件
        return true, true, "zip"
    elseif isHtml or ct:find("text/html", 1, true) then
        return true, false, "html"
    elseif isJson then
        return true, false, "json"
    elseif n == 0 then
        return true, false, "empty"
    end
    -- 不是网页也不是报错，有实体数据
    return true, true, "data"
end

-- 代理验证：子线程真去取一次文件开头，看拿回来的是不是文件本身。
-- 只判 HTTP 状态码是不够的 —— 大量镜像在出错时会回 200 + 一页 HTML 错误页，
-- 那种地址"能连上"但下不了文件，必须看内容才能分辨。
local function probeProxyAsync(idx, url)
    local started = pcall(function()
        local System = luajava.bindClass("java.lang.System")
        local Runnable = luajava.createProxy("java.lang.Runnable", {
            run = function()
                local t0 = System.currentTimeMillis()
                local code, ctype, clen = 0, "", -1
                local bytes = {}
                pcall(function()
                    local conn = luajava.newInstance("java.net.URL", url).openConnection()
                    conn.setConnectTimeout(4000)
                    conn.setReadTimeout(5000)
                    conn.setInstanceFollowRedirects(true)
                    conn.setUseCaches(false)
                    conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 12)")
                    conn.setRequestProperty("Accept", "*/*")
                    -- 只取开头，够判断类型就行，不整包下载
                    conn.setRequestProperty("Range", "bytes=0-1023")
                    local rc = conn.getResponseCode()
                    code = tonumber(rc) or tonumber(tostring(rc)) or 0
                    pcall(function() ctype = tostring(conn.getContentType() or "") end)
                    pcall(function() clen = tonumber(conn.getContentLength()) or -1 end)
                    if code == 200 or code == 206 then
                        local ins
                        pcall(function() ins = conn.getInputStream() end)
                        if ins then
                            -- 只读开头 512 字节：足够分辨 zip / 网页 / 报错，
                            -- 也不用把几十 MB 的包拖下来
                            for _ = 1, 512 do
                                local b = ins.read()
                                b = tonumber(b) or tonumber(tostring(b)) or -1
                                if b < 0 then break end
                                bytes[#bytes + 1] = b
                            end
                            pcall(function() ins.close() end)
                        end
                    end
                    pcall(function() conn.disconnect() end)
                end)

                local ms = System.currentTimeMillis() - t0

                local ok, dl, why = classifyProbe(code, ctype, clen, bytes)
                if not ok then ms = -1 end

                local script = string.format("window.proxyProbeResult(%d,%s,%d,%d,%s,'%s')",
                    idx, ok and "true" or "false", ms, code, dl and "true" or "false", why)
                activity.runOnUiThread(function()
                    pcall(function() web.evaluateJavascript(script, nil) end)
                end)
            end
        })
        luajava.newInstance("java.lang.Thread", Runnable).start()
    end)
    if not started then
        -- 线程都没起来也要回一个结果，否则页面一直停在"验证中"
        pcall(function()
            web.evaluateJavascript(
                string.format("window.proxyProbeResult(%d,false,-1,0,false,'fail')", idx), nil)
        end)
    end
end

local switchRepoDialog  -- 前向声明：定义在下方，handleMessage 需提前引用

local function handleMessage(message)
    if message == "getInstallTime" then
        return tostring(getInstallTimeMs())
    elseif message == "switchRepo" then
        pcall(function() switchRepoDialog() end)
        return "ok"
    elseif message:find("^insideBtnClick:") then
        local url = message:sub(16)
        local fileName = url:match("([^/]+)$") or "download.apk"
        local savePath = "/storage/emulated/0/Download/"
        downloadWithProgress(url, savePath, fileName)
        return "processing"
    elseif message:find("^confirmBtnClick:") then
        local url = message:sub(17)
        activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        return "confirmBtnClick"
    elseif message:find("^probeProxy:") then
        -- 格式：probeProxy:<序号>|<encodeURIComponent(完整测速地址)>
        local idxS, enc = message:sub(12):match("^(%d+)|(.+)$")
        if not (idxS and enc) then return "bad" end
        local url = enc
        pcall(function()
            url = luajava.bindClass("java.net.URLDecoder").decode(enc, "UTF-8")
        end)
        probeProxyAsync(tonumber(idxS), url)
        return "async"
    elseif message:find("^askProxyInput") then
        -- 格式：askProxyInput:<encodeURIComponent(当前值)>
        local tail = message:match("^askProxyInput:(.*)$")
        local init = ""
        if tail and tail ~= "" then
            pcall(function()
                local dec = luajava.bindClass("java.net.URLDecoder")
                init = dec.decode(tail, "UTF-8")
            end)
        end
        -- onJsPrompt 在主线程同步回调里，不能在这里等对话框，先弹再异步回填
        activity.runOnUiThread(function() askProxyInputDialog(init) end)
        return "async"
    elseif message:find("^updateApk:") then
        -- 格式：updateApk:<带代理前缀的下载链接>|<tag>|<文件名>
        local payload = message:sub(11)
        local url, tag, fileName = payload:match("^([^|]+)|([^|]+)|(.+)$")
        if url and tag then
            downloadUpdateApk(url, tag, fileName)
            return "processing"
        end
    end
    return "unhandled"
end


local msg = {
    title = "关于",
    text = About,
    btn = "",
    func = nil
}

-- 切换仓库：手动输入和点曾用仓库都走这里，写偏好 + 记历史 + 重载页面
local function applyRepo(o, r)
    local oldKey = currentOwner .. "/" .. currentRepo
    currentOwner, currentRepo = o, r
    saveCurrentRepo(o, r)
    pushRepoHistory(o, r, oldKey)
    activity.setTitle(o .. "/" .. r .. " • 一键更新")
    pcall(function()
        web.loadDataWithBaseURL("https://github.com/", renderHtml(), "text/html", "UTF-8", nil)
    end)
end

-- 切换仓库输入框（适配任意公开 GitHub 仓库；下面列出曾用仓库，点一下直接切）
switchRepoDialog = function()
    local dm2 = activity.getResources().getDisplayMetrics()
    local function d(n) return math.floor(n * dm2.density + 0.5) end

    local lay = LinearLayout(activity)
    lay.setOrientation(LinearLayout.VERTICAL)
    lay.setPadding(d(20), d(8), d(20), 0)

    local ed = EditText(activity)
    ed.setHint("格式：owner/repo")
    ed.setText(currentOwner .. "/" .. currentRepo)
    ed.setSingleLine(true)
    lay.addView(ed, LinearLayout.LayoutParams(-1, -2))

    local curKey = currentOwner .. "/" .. currentRepo
    local hist = {}
    for _, v in ipairs(loadRepoHistory()) do
        if v ~= curKey then hist[#hist + 1] = v end
    end

    local dlgRef
    if #hist > 0 then
        local tv = TextView(activity)
        tv.setText("曾用仓库（点一下直接切换）")
        tv.setTextSize(12)
        tv.setPadding(0, d(12), 0, d(2))
        lay.addView(tv)

        -- 不用 ListView + LuaAdapter：本脚本环境里 LuaAdapter 是 nil（会直接崩）。
        -- 历史最多 8 条，堆 TextView 更省事，也不受不同 androlua 版本适配器类路径差异影响。
        local sc = ScrollView(activity)
        local listLay = LinearLayout(activity)
        listLay.setOrientation(LinearLayout.VERTICAL)
        local ripple = 0
        pcall(function()
            ripple = activity.getResources().getIdentifier("selectableItemBackground", "attr", "android")
        end)
        for _, v in ipairs(hist) do
            local row = LinearLayout(activity)
            row.setOrientation(LinearLayout.HORIZONTAL)

            local item = TextView(activity)
            item.setText(v)
            item.setTextSize(15)
            item.setPadding(d(4), d(12), d(4), d(12))
            if ripple and ripple ~= 0 then
                pcall(function() item.setBackgroundResource(ripple) end)
            end
            item.setOnClickListener(luajava.createProxy("android.view.View$OnClickListener", {
                onClick = function()
                    if dlgRef then dlgRef.dismiss() end
                    local o, r = v:match("^([^/]+)/([^/]+)$")
                    if o and r then applyRepo(o, r) end
                end
            }))
            row.addView(item, LinearLayout.LayoutParams(0, -2, 1))

            -- 删除这一条历史（只动 history，不影响当前仓库）
            local del = TextView(activity)
            del.setText("✕")
            del.setTextSize(15)
            del.setTextColor(0xFFF85149)
            del.setPadding(d(14), d(12), d(6), d(12))
            del.setOnClickListener(luajava.createProxy("android.view.View$OnClickListener", {
                onClick = function()
                    removeRepoHistory(v)
                    if dlgRef then dlgRef.dismiss() end
                    pcall(function() switchRepoDialog() end)
                end
            }))
            row.addView(del, LinearLayout.LayoutParams(-2, -2))

            listLay.addView(row, LinearLayout.LayoutParams(-1, -2))
        end
        sc.addView(listLay)
        -- 最多露 3 行，再多就在里面滚动
        lay.addView(sc, LinearLayout.LayoutParams(-1, math.min(#hist, 3) * d(44)))
    else
        local hint = TextView(activity)
        hint.setText("暂无曾用仓库记录；切换一次后自动保存，下次可直接点选")
        hint.setTextSize(11)
        hint.setPadding(0, d(10), 0, 0)
        lay.addView(hint)
    end

    dlgRef = AlertDialog.Builder(activity)
        .setTitle("切换 GitHub 仓库")
        .setMessage("输入 owner/repo，例如 qttttttp/trime2\n支持任意公开仓库")
        .setView(lay)
        .setPositiveButton("确定", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
            onClick = function()
                local input = ed.getText().toString()
                input = input:match("^%s*(.-)%s*$") or input
                local o, r = input:match("^([^/]+)/([^/]+)$")
                if o and r then
                    applyRepo(o, r)
                else
                    AlertDialog.Builder(activity)
                        .setTitle("格式错误")
                        .setMessage("正确格式：owner/repo")
                        .setPositiveButton("确定", nil)
                        .show()
                end
            end
        }))
        .setNegativeButton("取消", nil)
        .show()
end

-- 回到输入法主界面（本脚本运行在输入法进程内，getPackageName 即输入法包名）
local function backToMainUI()
    -- 主界面 PrefLauncher 是 singleTask，NEW_TASK 即可把它带回前台并自动清顶；
    -- 无需 CLEAR_TOP，避免额外销毁主界面任务栈里其它页面
    local flags = Intent.FLAG_ACTIVITY_NEW_TASK
    local ok = pcall(function()
        local pm = activity.getPackageManager()
        local intent = pm.getLaunchIntentForPackage(activity.getPackageName())
        if not intent then error("no launch intent") end
        intent.addFlags(flags)
        activity.startActivity(intent)
    end)
    if not ok then
        -- 兜底：直接指定主界面 Activity 类名
        pcall(function()
            local it = Intent()
            it.setClassName(activity.getPackageName(), "com.osfans.trime.PrefLauncher")
            it.addFlags(flags)
            activity.startActivity(it)
        end)
    end
    activity.finish()
end

activity.onCreateOptionsMenu = function(menu)
    local refreshItem = menu.add("刷新")
    refreshItem.setShowAsAction(1)
    refreshItem.setOnMenuItemClickListener(function()
        web.reload()
        return true
    end)

    local aboutItem = menu.add("关于")
    aboutItem.setOnMenuItemClickListener(function()
        toast_dialog(msg)
        return true
    end)

    local switchItem = menu.add("切换仓库")
    switchItem.setOnMenuItemClickListener(function()
        switchRepoDialog()
        return true
    end)

    local backItem = menu.add("返回").setOnMenuItemClickListener(function()
        -- 原路退回：等于按系统返回键，回到启动本工具的界面（工具列表）
        local ok = pcall(function() activity.onBackPressed() end)
        if not ok then pcall(function() activity.finish() end) end
        return true
    end)

    local exitItem = menu.add("返回输入法主界面").setOnMenuItemClickListener(function()
        backToMainUI()
        return true
    end)

    return true
end

local function initWebView()
    web = ids.webView
    -- 启用 Cookie
    CookieManager.getInstance().setAcceptCookie(true)

    local settings = web.getSettings()
    settings.setJavaScriptEnabled(true)
    settings.setDomStorageEnabled(true)
    settings.setDatabaseEnabled(true)
    settings.setCacheMode(WebSettings.LOAD_DEFAULT)
    settings.setUserAgentString(settings.getUserAgentString() .. " Chrome/120.0.0.0")
    -- 设置自适应屏幕
    settings.setLoadWithOverviewMode(true)
    settings.setUseWideViewPort(true)
    settings.setLayoutAlgorithm(WebSettings.LayoutAlgorithm.TEXT_AUTOSIZING)

    web.setWebChromeClient(luajava.override(WebChromeClient, {
        onJsPrompt=function(superCall, view, url, message, defaultValue, result)
            if message and message:find("^LuaBridge:") then
                local cmd = message:sub(11)
                local response = handleMessage(cmd)
                result.confirm(response)
                return true
            end
            return superCall.onJsPrompt(view, url, message, defaultValue, result)
        end,
        onProgressChanged = function(superCall, view, newProgress)
            if newProgress >= 100 then
                activity.runOnUiThread(function()
                    if ids.loadingLayout then
                        ids.loadingLayout.setVisibility(8)
                        ids.resultLayout.setVisibility(0)
                    end
                end)
            end
        end
    })())

    web.setWebViewClient(luajava.override(WebViewClient, {
        onPageFinished = function(superCall, view, url)
            activity.runOnUiThread(function()
                if ids.loadingLayout then
                    ids.loadingLayout.setVisibility(8)
                    ids.resultLayout.setVisibility(0)
                end
            end)
        end
    })())

    web.loadDataWithBaseURL("https://github.com/", renderHtml(), "text/html", "UTF-8", nil)

end

function onCreate()
    layout = loadlayout(layout, ids)
    ids.pro.setIndeterminate(true)
    ids.fxtext.setText("正在加载……")
    activity.setContentView(layout)

    loadSavedRepo()
    activity.setTitle(currentOwner .. "/" .. currentRepo .. " • 一键更新")

    local ok, err = pcall(initWebView)
    if not ok then
        local tv = TextView(activity)
        tv.setPadding(30, 30, 30, 5)
        tv.setTextIsSelectable(true)
        tv.setText("初始化失败: \n" .. tostring(err))
        activity.setContentView(tv)
    end
end

function onDestroy()
    -- 无需手动清理：Activity 销毁时 WebView 会随进程自动回收。
    -- 手动 clearCache 反而会清掉资源缓存、拖慢下次打开，故移除。
end

-- function onStart()
-- print("LogCat 开始")
-- end

-- function onResume()
-- print("LogCat 恢复")
-- end

-- function onPause()
-- print("LogCat 暂停")
-- end

-- function onStop()
-- print("LogCat 停止")
-- end

