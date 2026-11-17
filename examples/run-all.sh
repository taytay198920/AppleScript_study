#!/usr/bin/env bash
# 逐个运行示例，验证它们能跑通。
#
# 用法：
#   cd examples && ./run-all.sh              # 跑全部
#   ./run-all.sh 01 02 07                    # 只跑指定编号
#   ./run-all.sh --fast                      # 跳过需要 GUI 授权的（04）
#
# 安全说明：
#   - 全部示例都以「只读 / dry-run / 临时目录」方式运行，不改动用户数据。
#   - 06 会临时改写剪贴板，脚本会先备份、跑完还原。
#   - 04 需要 Safari 自动化授权，首次运行会弹授权框；--fast 可跳过。
#   - 08 只跑 --dry-run，不碰 Calendar，因此不需要授权。
set -uo pipefail

cd "$(dirname "$0")"

FAST=0
targets=()
for arg in "$@"; do
    if [ "$arg" = "--fast" ]; then FAST=1; else targets+=("$arg"); fi
done
if [ ${#targets[@]} -eq 0 ]; then targets=(01 02 03 04 05 06 07 08); fi

pass=0; fail=0; skip=0

run_one() {
    local label="$1"; shift
    printf '\n\033[1m== %s ==\033[0m\n' "$label"
    if osascript "$@" >/tmp/runall.out 2>/tmp/runall.err; then
        head -10 /tmp/runall.out
        printf '\033[32m   ✅ PASS\033[0m\n'; pass=$((pass+1))
    else
        head -10 /tmp/runall.out; head -3 /tmp/runall.err
        printf '\033[31m   ❌ FAIL\033[0m\n'; fail=$((fail+1))
    fi
}

# 06 需要剪贴板里有文本：先备份原内容
clip_backup="$(osascript -e 'try
	return (the clipboard) as text
on error
	return ""
end try' 2>/dev/null)"

for num in "${targets[@]}"; do
    case "$num" in
        01) run_one "01-hello" 01-hello.applescript 甲 乙 ;;
        02) run_one "02-text-utils" 02-text-utils.applescript ;;
        03) tmp="$(mktemp -d)"; mkdir -p "$tmp/in"
            for f in IMG_001.jpg IMG_002.jpg note.txt; do : > "$tmp/in/$f"; done
            run_one "03-batch-rename (dry-run)" 03-batch-rename.applescript "$tmp/in" 'prefix:2026_'
            rm -rf "$tmp" ;;
        04) if [ "$FAST" = "1" ]; then
                printf '\n\033[33m== 04-safari-tabs-export 已跳过（--fast）==\033[0m\n'; skip=$((skip+1))
            else
                run_one "04-safari-tabs-export" 04-safari-tabs-export.applescript
            fi ;;
        05) src="$(mktemp -d)"; dst="$(mktemp -d)"
            echo hello > "$src/a.txt"; mkdir -p "$src/sub"; echo world > "$src/sub/b.txt"
            run_one "05-daily-backup (dry-run)" 05-daily-backup.applescript "$src" "$dst" --dry-run
            run_one "05-daily-backup (真跑一次)" 05-daily-backup.applescript "$src" "$dst" --keep 2
            rm -rf "$src" "$dst" ;;
        06) printf '  测试\t文本\r\n含  多余空白  ' | pbcopy
            run_one "06-clipboard-history" 06-clipboard-history.applescript
            printf '%s' "$clip_backup" | pbcopy ;;
        07) run_one "07-shell-bridge" 07-shell-bridge.applescript ;;
        08) run_one "08-calendar-batch (dry-run)" 08-calendar-batch.applescript \
                08-calendar-batch.sample.txt --dry-run ;;
        *)  printf '\n\033[33m== 未知编号 %s，跳过 ==\033[0m\n' "$num"; skip=$((skip+1)) ;;
    esac
done

printf '\n\033[1m== 汇总 ==\033[0m\n  通过 %d，失败 %d，跳过 %d\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
