#!/usr/bin/env bash
# deploy_fork.sh — 纯 fork 仓库一键部署 Hermes Agent
# 作者：豆包包5号 · 2026-10-26 · 状态：初稿待拍板（未进 fork）
# 用法：
#   ./deploy_fork.sh --profile doubaobaoX [--tag family-v1] [--commit 20b2294f46] [--dir ~/.hermes/hermes-agent]
# 依赖：git, uv, python3.11；github 不通的环境需已开着代理（脚本自动探测 7890）
set -euo pipefail

TAG=""
COMMIT="20b2294f46"          # 默认冻结点（2026-09-16 家族决议）
# DEST 默认值用 /home/jqllxew 兜底——profile 环境下 HOME 被劫持到 profiles/<name>/home（4姐 10-19 踩过的坑）
REAL_HOME=$(getent passwd "$(id -un)" | cut -d: -f6)
DEST="${REAL_HOME:-$HOME}/.hermes/hermes-agent"
PROFILE=""
PROXY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --tag)     TAG="$2"; shift 2 ;;
    --commit)  COMMIT="$2"; shift 2 ;;
    --dir)     DEST="$2"; shift 2 ;;
    --proxy)   PROXY="$2"; shift 2 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

[[ -n "$PROFILE" ]] || { echo "用法: $0 --profile <name> [--tag|--commit|--dir|--proxy]"; exit 1; }

# ① 代理探测（目标必须是真实仓库 URL——裸域名会被 git 当仓库名，永远 not found，2姐 10-26 实测）
FORK_URL="git@github.com:jqllxew/hermes-agent.git"
if [[ -z "$PROXY" ]] && ! timeout 5 git ls-remote "$FORK_URL" &>/dev/null; then
  if curl -s --max-time 3 -x http://127.0.0.1:7890 https://github.com &>/dev/null; then
    PROXY="http://127.0.0.1:7890"
  fi
fi
[[ -n "$PROXY" ]] && export https_proxy="$PROXY" && echo "[1/5] 走代理 $PROXY"

# ② 拉代码（唯一来源 = fork；已有目录必须就是本 fork，不静默改写）
echo "[2/5] clone fork → $DEST"
if [[ -d "$DEST/.git" ]]; then
  ACTUAL=$(git -C "$DEST" remote get-url origin 2>/dev/null || echo "?")
  if [[ "$ACTUAL" != *"/hermes-agent.git" || "$ACTUAL" == *"NousResearch"* ]]; then
    echo "❌ $DEST 的 origin 是 $ACTUAL（上游/非本 fork）——纯 fork 部署不碰上游，请用 --dir 指定其他目录"; exit 1
  fi
  git -C "$DEST" fetch origin
  git -C "$DEST" checkout "${TAG:-$COMMIT}"
else
  git clone "$FORK_URL" "$DEST"
  git -C "$DEST" checkout "${TAG:-$COMMIT}"
fi

# ③ venv + editable install
echo "[3/5] uv venv + pip install -e ."
cd "$DEST"
[[ -d venv ]] || uv venv venv --python 3.11
uv pip install -e . --python venv/bin/python

# ④ systemd（模板在 repo 内）
echo "[4/5] systemd 服务 hermes-gateway@$PROFILE"
if [[ -w /etc/systemd/system ]] || sudo -n true 2>/dev/null; then
  sudo cp "$DEST/hermes-gateway@.service" /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now "hermes-gateway@$PROFILE"
else
  echo "  ⚠️ 无 sudo，跳过 systemd——手动: cp hermes-gateway@.service /etc/systemd/system/ && systemctl enable --now hermes-gateway@$PROFILE"
fi

# ⑤ profile 数据面（只建骨架，不碰已有）
echo "[5/5] profile 骨架"
P="${REAL_HOME:-$HOME}/.hermes/profiles/$PROFILE"
mkdir -p "$P"/{logs,scripts,cron}
[[ -f "$P/config.yaml" ]] || echo "  ⚠️ $P/config.yaml 不存在——从备份 tar 恢复或手写（model/feishu 两段必填）"
[[ -f "$P/.env" ]] || echo "  ⚠️ $P/.env 不存在——至少要 FEISHU_APP_ID/FEISHU_APP_SECRET"

echo "✅ 完成。验证: $DEST/venv/bin/python -m hermes_cli.main --version"
