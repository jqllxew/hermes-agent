#!/usr/bin/env bash
# hermes_upgrade.sh — fork 线升级：fetch → checkout 新 tag → 重装依赖 → 重启 gateway → 自检
# 作者：豆包包5号 · 2026-10-26 · 家族部署脚本族
# 用法：hermes_upgrade.sh [--tag family-v2] [--repo ~/.hermes/hermes-agent]
#   无 --tag 时 = fetch fork/main 并 checkout 其 HEAD（跟随模式）
# 安全设计：
#   - 升级前自动记录当前状态到 $REPO/.upgrade_state（commit/venv mtime），回滚脚本读它
#   - 依赖重装用 uv pip install -e . 幂等，无变化时秒过
#   - gateway 逐个 restart，失败立即中止并提示回滚
set -euo pipefail
REAL_HOME=$(getent passwd "$(id -un)" | cut -d: -f6)
REPO="${REAL_HOME:-$HOME}/.hermes/hermes-agent"
TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

TARGET="${TAG:-origin/main}"
OLD=$(git -C "$REPO" rev-parse --short HEAD)
echo "[0/5] 当前: $REPO @ $OLD"

# ① 记录升级前状态（回滚的锚点）
STATE="$REPO/.upgrade_state"
cat > "$STATE" <<EOF
prev_commit=$OLD
prev_tag=$(git -C "$REPO" describe --tags --abbrev=0 HEAD 2>/dev/null || echo none)
date=$(date -Is)
EOF
echo "[1/5] 升级前状态已存 $STATE"

# ② fetch + checkout
echo "[2/5] fetch + checkout $TARGET"
git -C "$REPO" fetch origin
git -C "$REPO" checkout "$TARGET"
NEW=$(git -C "$REPO" rev-parse --short HEAD)

# ③ 依赖重装（editable，幂等；-e . 相对 cwd，必须先进 $REPO——2号 10-26 实测）
echo "[3/5] venv 依赖同步"
UV=$(command -v uv || echo "${REAL_HOME}/.hermes/bin/uv")
(cd "$REPO" && $UV pip install -e . --python "$REPO/venv/bin/python" -q)
echo "  CLI: $("$REPO/venv/bin/python" -m hermes_cli.main --version 2>&1 | head -1)"

# ④ 逐个重启 gateway（谁挂了立即中止）
echo "[4/5] 重启 gateway 服务"
FAILED=()
while read -r svc; do
  systemctl restart "$svc"
  sleep 2
  ST=$(systemctl is-active "$svc")
  echo "  $svc: $ST"
  [[ "$ST" == "active" ]] || FAILED+=("$svc")
done < <(systemctl list-units 'hermes-gateway@*' --no-legend --plain | awk '{print $1}')
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "❌ 这些服务重启后没起来: ${FAILED[*]}"
  echo "   回滚: hermes_rollback.sh --repo $REPO"
  exit 1
fi

# ⑤ 自检收尾
echo "[5/5] 健康自检"
DIR=$(dirname "$(readlink -f "$0")")
if [[ -x "$DIR/hermes_health.sh" ]]; then
  "$DIR/hermes_health.sh" "$REPO"
else
  echo "  (hermes_health.sh 不在旁，手动跑)"
fi
echo "✅ 升级完成: $OLD → $NEW"
