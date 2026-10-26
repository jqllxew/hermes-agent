#!/usr/bin/env bash
# hermes_health.sh — fork 部署健康自检（一条命令出报告）
# 作者：豆包包5号 · 2026-10-26 · 家族部署脚本族之一
# 用法：hermes_health.sh [repo_dir]   默认 REAL_HOME/.hermes/hermes-agent
set -uo pipefail
REAL_HOME=$(getent passwd "$(id -un)" | cut -d: -f6)
REPO="${1:-${REAL_HOME:-$HOME}/.hermes/hermes-agent}"
VENV_PY="$REPO/venv/bin/python"
FAIL=0

echo "=== Hermes 部署健康自检 $(date '+%F %T') ==="

# ① 仓库身份与版本
if [[ -d "$REPO/.git" ]]; then
  COMMIT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)
  ORIGIN=$(git -C "$REPO" remote get-url origin 2>/dev/null)
  echo "[repo] $REPO @ $COMMIT"
  echo "[origin] $ORIGIN"
  if [[ "$ORIGIN" == *"NousResearch"* ]]; then
    echo "  ⚠️ origin 指向上游（纯 fork 部署要求 fork）"; FAIL=1
  fi
  # 本地与 fork/main 漂移检测（有网络才测，失败不算病）
  if timeout 8 git -C "$REPO" ls-remote origin HEAD &>/dev/null; then
    AHEAD=$(git -C "$REPO" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
    # origin/main 本地引用可能过期（切 remote 后未 fetch）——数值离谱就提示先 fetch 防假数
    if [[ "$AHEAD" =~ ^[0-9]+$ && "$AHEAD" -gt 500 ]]; then
      echo "[drift] 落后 $AHEAD 个 commit——数值可疑，origin/main 引用可能过期，建议: git -C $REPO fetch origin"
    else
      echo "[drift] 落后 fork/main $AHEAD 个 commit"
    fi
  else
    echo "[drift] 无网络，跳过"
  fi
else
  echo "❌ $REPO 不是 git 仓库"; FAIL=1
fi

# ② venv / CLI 可用性
if [[ -x "$VENV_PY" ]]; then
  VER=$("$VENV_PY" -m hermes_cli.main --version 2>&1 | head -1) && echo "[cli] $VER" || { echo "❌ CLI 起不来"; FAIL=1; }
else
  echo "❌ venv 不存在: $VENV_PY"; FAIL=1
fi

# ③ gateway 服务状态（所有 profile）
echo "[gateway]"
while read -r svc; do
  ST=$(systemctl is-active "$svc" 2>/dev/null)
  echo "  $svc: $ST"
  [[ "$ST" == "active" ]] || FAIL=1
done < <(systemctl list-units 'hermes-gateway@*' --no-legend --plain 2>/dev/null | awk '{print $1}')

echo "=== 结论: $([[ $FAIL -eq 0 ]] && echo '全部正常 ✅' || echo '有异常 ❌（见上行）') ==="
exit $FAIL
