# Hermes Agent 纯 fork 仓库部署方案

> 起草：豆包包5号 · 2026-10-26 · 状态：草稿待好运宝宝拍板
> 需求：只基于 fork 仓库（jqllxew/hermes-agent）即可完整部署一台新机/重建本机，不依赖 NousResearch 上游可达性。

## 一、现状摸底（实测数据）

| 项 | 实测值 |
|---|---|
| 本地 checkout | `/home/jqllxew/.hermes/hermes-agent`，main@20b2294f46（= fork/main HEAD，零漂移） |
| fork | `git@github.com:jqllxew/hermes-agent.git`，领先上游 41 个自家 commit（feishu 插件迁移、approval 放宽、图片占位修复等全部家底已在 fork/main 上） |
| 上游 | origin=NousResearch/hermes-agent，fork 落后它 22682 commit（**但这无关紧要——我们不追上游，9-16 已冻结**） |
| 安装方式 | editable install：`hermes-agent 0.18.2` 直接指向 repo 目录（venv/pyvenv.cfg 显示 uv venv, Python 3.11） |
| 启动入口 | systemd `hermes-gateway@<profile>.service`，ExecStart = venv python -m hermes_cli.main gateway run -p %i --replace；模板副本在 repo 内 untracked |
| 依赖网络 | github 直连不通，走 mihomo:7890 代理 |

关键结论：**fork/main 已经是自足的**——41 个自家 commit 全推上去了，本地 main 与 fork/main 同点。上游只是个永远不再 fetch 的历史来源。所以「纯 fork 部署」缺的不是代码，是**一套可复现的安装流程 + 数据面（profiles）分离**。

## 二、部署方案（核心四步，一台新机 30 分钟内跑完）

### 步骤 0：前置
```bash
# 需要：Python 3.11（uv 装最稳）、git、ssh key（拉私有 fork）、代理（github 不通的环境）
uv python install 3.11
```

### 步骤 1：拉仓库（唯一代码来源 = fork）
```bash
export https_proxy=http://127.0.0.1:7890   # 视网络环境
git clone git@github.com:jqllxew/hermes-agent.git ~/.hermes/hermes-agent
cd ~/.hermes/hermes-agent
git checkout 20b2294f46   # 冻结点；或 fork/main 最新（见「版本策略」节）
```

### 步骤 2：装 venv（editable install，改代码即时生效——全家现状同款）
```bash
uv venv venv --python 3.11
uv pip install -e .          # pyproject.toml 是唯一依赖清单，fork 自足
```

### 步骤 3：systemd 服务（模板在 repo 内，跟仓库走）
```bash
sudo cp ~/.hermes/hermes-agent/hermes-gateway@.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-gateway@<profile名>
```
（现有 override：TimeoutStopSec=210、doubaobao5 的 stale-timeout.conf 属机器级微调，不进 repo，手抄即可）

### 步骤 4：profile 数据面
```bash
mkdir -p ~/.hermes/profiles/<profile>
# 最小可跑：config.yaml（model/feishu 段）+ .env（FEISHU_APP_ID/SECRET）+ SOUL.md
# 从备份恢复全套：/opt/jqllxew/doubaobao-backups/ 最新 tar 里的 profiles/<name>/
```

## 三、版本策略（跟 fork 走的三档）

1. **冻结档（现行）**：钉 20b2294f46 不动。部署=checkout 这个 commit。零风险，适合新机先跑起来。
2. **跟随档**：定期 `git fetch fork && git merge fork/main`。fork/main 就是全家唯一真相线，上游永远不看。需要的话给 fork/main 打 tag（如 `family-v1`）作为下次全家的共同锚点。
3. **发布档（可选升级）**：fork 里已有 scripts/release.py 和 v2026.9.x tag 序列，可走 `git tag family-v1 && git push fork family-v1`，把「当前全家在跑什么」变成 fork 上的正式 tag，部署脚本可以 `--branch family-v1` 直接指。

## 四、风险与边界（实测过/没测过的分开说）

- ✅ 已验证：fork/main 含全部自家 41 commit；本地与 fork/main 零漂移；pyproject 依赖清单自足；systemd 模板在 repo 内。
- ⚠️ 待证：~~干净机器上 uv pip install -e . 是否一把过~~ → **已实证（10-26 演练）**：干净 clone fork@20b2294f46 + 全新 uv venv，`uv pip install -e .` 一把过，`hermes_cli` 导入 OK，`hermes --version` 报 v0.16.0 (upstream 20b2294f)，CLI --help 正常。全程仅用 pyproject 依赖清单，无历史包兜底。演练目录已清理。
- ⚠️ 注意：`.install_method` 文件写的 git；editable install 意味着 repo 目录即运行代码——**repo 树上不能乱动**（家规已有：改共享代码先发 diff）。
- 数据面（profiles/备份/.bypy cookie）全在 repo 外，换机只搬代码+两份文件（config/.env），符合「代码与状态分离」。

## 五、落地物清单（可选，拍板后我可以做）

1. `scripts/deploy_fork.sh`：把步骤 0-4 固化成一个脚本（参数：profile 名、commit/tag），放 fork 里全家共用。
2. 给 fork/main 打 `family-v1` tag 固化当前全家共同点。
3. 部署演练：在本机用 `git clone` 到临时目录 + 独立 venv 跑一遍 `hermes --help`，验证「纯 fork 可装」闭环（不动现役 venv）。
