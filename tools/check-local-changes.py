#!/usr/bin/env python3
"""
check-local-changes.py —— 找出「源码树里改了、但补丁包里没有」的文件

背景：这个项目靠 patches/*.patch 在 CI 的干净树上复现本地构建。
本地直接 `gradlew assembleRelease` 会用到所有未提交改动，而 CI 只认补丁。
只要有一处文件漏进补丁，CI 就会在某个步骤炸掉（历史上漏过两次：
Boost 的 vmd 模块、OpenCC 缺字典跳过），或者更糟——编出一个行为不同的包。

用法：
    python3 tools/check-local-changes.py <源码树> [补丁目录]

做文件级检查（不做行级，避免多补丁文件产生噪音）：
  - 有改动但没有任何补丁涉及
  - 新增文件但补丁里没有 `new file` 记录
子模块与构建产物自动排除。退出码 1 表示有遗漏。
白名单：源码树根目录 .unpatched-allow，每行一个路径（支持后缀匹配）。
"""
import re
import subprocess
import sys
from pathlib import Path

SKIP_PREFIX = ("app/libs/", "app/src/main/assets/mlkit-offline/", "app/build/", "build/")
SKIP_SUFFIX = (".tar.xz", ".aar", ".apk", ".zip")
SKIP_EXACT = (".unpatched-allow",)


def git(args, cwd):
    r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("git %s 失败:\n%s" % (" ".join(args), r.stderr))
    return r.stdout


def submodule_paths(src):
    f = src / ".gitmodules"
    if not f.exists():
        return set()
    return set(re.findall(r"^\s*path\s*=\s*(.+)$", f.read_text(encoding="utf-8"), re.M))


def covered_files(pdir):
    """补丁涉及的文件 → 是否带 new file"""
    touched, created = set(), set()
    for p in sorted(pdir.glob("*.patch")):
        cur, is_new = None, False
        for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("diff --git "):
                if cur and is_new:
                    created.add(cur)
                m = re.search(r" b/(.+)$", line)
                cur, is_new = (m.group(1) if m else None), False
                if cur:
                    touched.add(cur)
                continue
            if line.startswith("new file mode"):
                is_new = True
        if cur and is_new:
            created.add(cur)
    return touched, created


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1]).resolve()
    pdir = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "patches"

    subs = submodule_paths(src)
    allow_file = src / ".unpatched-allow"
    allow = []
    if allow_file.exists():
        allow = [l.strip() for l in allow_file.read_text(encoding="utf-8").splitlines()
                 if l.strip() and not l.startswith("#")]

    def skip(path):
        if path in SKIP_EXACT or path.startswith(SKIP_PREFIX) or path.endswith(SKIP_SUFFIX):
            return True
        if any(path == s or path.startswith(s.rstrip("/") + "/") for s in subs):
            return True
        return any(path == a or path.endswith(a) for a in allow)

    modified = [l for l in git(["diff", "--name-only", "HEAD"], src).splitlines() if l.strip()]
    untracked = [l for l in git(["ls-files", "--others", "--exclude-standard"], src).splitlines() if l.strip()]

    touched, created = covered_files(pdir)

    problems = []
    for f in sorted(set(modified) | set(untracked)):
        if skip(f):
            continue
        if f in untracked:
            if f not in created:
                problems.append((f, "新增文件，补丁里没有对应 new file"))
        elif f not in touched:
            problems.append((f, "有改动，没有任何补丁涉及"))

    if problems:
        print("!! 以下改动不会出现在 CI 构建里：")
        for f, why in problems:
            print("   %-72s %s" % (f, why))
        print("\n共 %d 处。补 patch，或写进 .unpatched-allow 明确表示「本地专属」。" % len(problems))
        return 1
    print("OK: 本地改动都能在补丁里找到对应（补丁涉及 %d 个文件）" % len(touched))
    return 0


if __name__ == "__main__":
    sys.exit(main())
