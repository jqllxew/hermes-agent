#!/usr/bin/env bash
# hermes_rollback.sh — 回滚到最近一次升级前的完整状态
# 作者：豆包包5号 · 2026-10-26 · 家族部署脚本族
# 回滚三件套（2姐要求的全量回退）：
#   ① repo checkout 回 .upgrade_state 记录的 prev_commit
#   ② venv 依赖重装同步回旧 commit 的 pyproject（editable install 本身就是状态恢复）
#   ③ 重启所有 gateway 让运行时回到旧代码
# 用法：hermes_rollback.sh [--to <commit|tag>] [--repo <dir>] [--keep-venv]
#   默认读 $REPO/.upgrade_state；--to 可显式指定任意目标
set -euo pipefail
REAL_HOME=$(getent passwd "$(id -un)" | cut -d: -f6)
REPO="${REAL_HOME:-$HOME}/.hermes/hermes-agent"
TO=""
KEEP_VENV=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to) TO="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --keep-venv) KEEP_VENV=1; shift ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

# ① 回滚目标解析
STATE="$REPO/.upgrade_state"
if [[ -z "$TO" ]]; then
  [[ -f "$STATE" ]] || { echo "❌ 无 $STATE，也没有 --to——不知道回哪去"; exit 1; }
  TO=$(grep '^prev_commit=' "$STATE" | cut -d= -f2)
  echo "[state] 读到升级前记录: $(cat "$STATE" | tr '\n' ' ')"
fi
CUR=$(git -C "$REPO" rev-parse --short HEAD)
echo "[1/4] repo 回退: $CUR → $TO"

# ② 工作区安全检查：有未提交改动先拒绝（回滚不吞脏工作区）
if ! git -C "$REPO" diff --quiet || ! git -C "$REPO" diff --cached --quiet; then
  echo "❌ 工作区有未提交改动，先 stash/commit 再回滚（回滚不吞脏状态）"; exit 1
fi
git -C "$REPO" checkout "$TO"
NOW=$(git -C "$REPO" rev-parse --short HEAD)

# ③ venv 依赖同步回旧 commit（这是 2姐说的「venv 状态漂移也要落回去」）
if [[ $KEEP_VENV -eq 0 ]]; then
  echo "[2/4] venv 依赖同步回 $NOW 的 pyproject"
  UV=$(command -v uv || echo "${REAL_HOME}/.hermes/bin/uv")
  # -e . 是相对 cwd 的——必须先进 $REPO（2号 10-26 实测：不 cd 会报 "does not appear to be a Python project"）
  (cd "$REPO" && $UV pip install -e . --python "$REPO/venv/bin/python" -q)
  (cd "$REPO" && "$REPO/venv/bin/python" -m hermes_cli.main --version 2>&1 | head -1)
else
  echo "[2/4] 跳过 venv 同步（--keep-venv）"
fi

# ④ 重启全部 gateway（无权限环境降级提示，不静默死）
echo "[3/4] 重启 gateway"
FAILED=()
while read -r svc; do
  ERRF=$(mktemp)
  if ! systemctl restart "$svc" 2>"$ERRF"; then
    echo "  $svc: restart 失败 ($(head -1 "$ERRF"))"
    FAILED+=("$svc"); rm -f "$ERRF"; continue
  fi
  rm -f "$ERRF"
  sleep 2
  ST=$(systemctl is-active "$svc")
  echo "  $svc: $ST"
  [[ "$ST" == "active" ]] || FAILED+=("$svc")
done < <(systemctl list-units 'hermes-gateway@*' --no-legend --plain | awk '{print $1}')
[[ ${#FAILED[@]} -gt 0 ]] && { echo "❌ 没起来: ${FAILED[*]}——若为权限问题请手动 sudo systemctl restart 后重跑，或查 journalctl"; exit 1; }

echo "[4/4] 清理升级状态文件"
rm -f "$STATE"
echo "✅ 回滚完成: $CUR → $NOW（venv + gateway 均已落回）"
