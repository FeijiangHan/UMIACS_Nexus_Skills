# UMIACS_Nexus_Skills

给 coding agent（Claude Code / Codex 等）用的 **UMD UMIACS / Nexus GPU 集群**技能包，
面向 Furong Huang (furongh) 实验室成员。核心内容在 [`umiacs-nexus-gpu/`](umiacs-nexus-gpu/) 目录里
（`SKILL.md` + `scripts/` + `references/`）。这个顶层 README 是给**第一次用这套远程 GPU 的人**看的，
讲清楚"从 0 到跑起第一个 GPU 任务"该怎么做。

> ℹ️ 分区/QOS/存储路径这些信息已经对照用户提供的官方 wiki 页面（`Nexus/CML`、`SLURM`）截图核实过，
> 不是瞎猜的。但集群配置会变，跑之前建议还是照下面"验证"部分的命令自己确认一遍——如果某个命令报
> `invalid partition`/`invalid qos`，说明名称可能变了，去问 staff@umiacs.umd.edu 或翻官方 wiki：
> - https://wiki.umiacs.umd.edu/umiacs/index.php/Nexus/CML
> - https://wiki.umiacs.umd.edu/umiacs/index.php/SLURM

---

## 1. 集群是什么、分几级

UMIACS 的 Nexus 集群用 **SLURM** 做资源调度。你不会直接登上装了 GPU 的机器，而是：

```
你的电脑 --ssh--> 登录节点 (login node, 没有 GPU)
                     |
                     | 用 SLURM 命令 (salloc/srun) 申请一台/几台 GPU
                     v
                  计算节点 (compute node, 真正有 GPU 的机器)
```

具体登录地址是 **`nexuscml.umiacs.umd.edu`**（背后轮询到 `nexuscml00`/`nexuscml01` 两台实际的登录/提交节点）。
**登录节点没有 GPU，CPU/内存也限制得很死，而且是全实验室甚至全系共用的。** 千万不要在登录节点上直接跑
训练、跑推理、甚至"随手测一下"的重计算——经常有人图省事直接在登录节点跑东西，结果全系统跟着卡顿。
登录节点只适合：`ssh` 进来、`cd`、`git`、编辑文件、提交 SLURM 任务这类轻量操作。
（小坑：如果你往登录节点的本地目录如 `/tmp`、`/scratch0` 存了东西，下次得连到同一台节点才能看到。）

我们实验室能用到的资源分了几个优先级（详见 `umiacs-nexus-gpu/references/cluster-tiers.md`，含官方 QoS
限额表）：

| 优先级 | 怎么申请 | 说明 |
|---|---|---|
| 1️⃣ 实验室专属节点 | `account=cml-furongh partition=cml-furongh qos=cml-high_long` | cml30 (8×A6000)、cml36 (8×H200)、cml38 (8×B300)、cml37 (4×RTX 6000 Blackwell)。优先用这个。QoS 上限：单用户同时最多 8 张卡、最长 14 天；某些账号可能默认没开这个 QoS，报错就找 staff 开通。 |
| 2️⃣ 全系共享 tron 分区 | `partition=tron qos=high` | 共享的 RTX A6000 池，实验室节点满了/挂了时用。 |
| 3️⃣ Scavenger（白嫖） | `partition=cml-scavenger qos=cml-scavenger` | 全 CML 共享、随时可能被抢占（kill掉）的机会资源，最长 3 天，全体用户合计上限 24 张卡。只适合能随时续跑（有 checkpoint）的任务。 |

> 账单小知识：`cml-furongh` 这个账号不管你提交到哪个 partition，扣的都是同一份配额。如果拿
> `cml-furongh` 账号跑到 `cml-dpart`（默认 partition）上，会占用本该留给 `cml-furongh` partition（也
> 就是实验室专属节点）的配额——正常情况下 account 和 partition 都用 `cml-furongh` 配对着用就好，不要
> 混着用。

## 2. 申请账号（人工步骤，agent 做不了）

1. 打开 `intranet.umiacs.umd.edu`。
2. 用 UMD 邮箱申请 Nexus 账号，PI 一栏填 **furongh@umiacs.umd.edu**。
3. 等待审批（一般是实验室/UMIACS 管理员处理）。
4. 拿到账号后，UMIACS 会给你登录方式（通常是 `ssh <username>@<login-host>`，具体登录节点地址找
   labmate 或 staff@umiacs.umd.edu 确认，本仓库不代猜地址）。

## 3. 第一次登录：初始化环境

登录到登录节点后（不是在沙盒/受限终端里，SLURM 命令需要完整权限），跑一次初始化脚本：

```bash
cd umiacs-nexus-gpu
bash scripts/nexus-init.sh
```

它会做这几件事，而且可以重复跑不会出问题：

- 把 `gpualloc` / `gpurun` / `gpush` / `gpustatus` 四个小工具装到 `~/bin`，并把 `~/bin` 加进
  `~/.bashrc` 的 `PATH`。
- 建 `~/.nexus/` 目录，用来记住"我当前在用哪个 SLURM job"。
- 检查你的 `/cmlscratch/$USER`（CML 的 network scratch）是否可用，如果可用，问你要不要顺手建一套
  `data/checkpoints/logs/code/envs` 的目录结构。

**为什么要专门检查这个：** 你的 `$HOME`（即 `/nfshomes/$USER`）只有 **30GB** 配额（虽然有备份），数据集、
模型 checkpoint 这些大文件**不要**往 `$HOME` 里塞，官方也明确建议 home 目录只放个人配置文件。真正干活的
地方是 `/cmlscratch/$USER`（默认 200GB，可申请到 800GB，**不备份不做快照**）。如果需要长期、有备份、能
跟组里人共享的存储，可以申请 `/fs/cml-projects/<项目名>`（最多 6TB，120 天一个周期，需要老师批准）。
详见 `umiacs-nexus-gpu/references/storage.md`（里面还有只读的 `/fs/cml-datasets`、`/fs/cml-models`，以及
计算节点本地的 `/scratch0` 这类临时盘的说明）。

装完之后开一个新终端，或者 `source ~/.bashrc`，让 `PATH` 生效。

## 4. 跑第一个 GPU 测试任务（最快上手路径）

```bash
# 第一步：申请一张卡，8 小时，跑完就还
gpualloc furongh1 8:00:00 1

# gpualloc 会打印类似：
#   Allocated job id: 123456  (profile=furongh1 count=1 time=8:00:00)
#   export GPU_JOBID=123456   <- 如果你要固定这个 session 用这张卡（多 session 同时用时才需要）

# 第二步：在这个分配里跑一个测试命令，确认 GPU 真的能用
gpurun 'nvidia-smi'
gpurun 'python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"'

# 第三步：需要的话，从另一个终端"挂"到同一个 job 上（比如你想开个交互式 shell）
gpush          # 只有一个 RUNNING job 时直接进去；多个的话会让你选

# 第四步：看当前状态
gpustatus
```

- **短任务**（几分钟内的小测试/小 eval/debug）：自己用 `gpurun '<命令>'` 在已有分配里跑，别为每条命令
  单独申请一次卡。
- **长任务**（正式训练、大规模 sweep、跑几个小时以上）：不要在交互式分配里自己跑，写一个 `sbatch`
  脚本，让它作为真正的 SLURM job 提交（`sbatch xxx.sh`），这样任务不依赖你的终端/session 存活，日志也
  规范。

## 5. 用完了怎么关闭 / 释放

**分配着的卡从申请那一刻起就占着实验室的共享配额，不管你有没有真的在用它** —— 用完尽快释放：

```bash
# 释放当前默认分配的 job
scancel $(cat ~/.nexus/current_jobid)

# 或者指定 job id 释放
scancel 123456

# 查看自己名下所有 job（确认有没有忘记关的）
squeue -u $USER
```

## 6. 多个 agent session / 多个终端同时用同一账号

如果你（或你的 coding agent）同时开了好几个 session 都要用 GPU，注意 `gpurun`/`gpush` 默认认的是
"最近一次 `gpualloc` 记下来的 job"（存在 `~/.nexus/current_jobid` 里）。如果某个 session 需要固定用
自己申请的那张卡、不被别的 session 后来申请的卡"抢走"默认目标，就在那次 `gpualloc` 之后跑：

```bash
export GPU_JOBID=<刚才 gpualloc 打印的 job id>
```

这样这个 session 里的 `gpurun`/`gpush` 就一直锁定这个 job，不受其他 session 影响。

## 7. 需要跑 Jupyter Notebook？

官方支持在计算节点上跑 Jupyter，再用 SSH 隧道连回本地，完整步骤（含常见坑，比如端口冲突、隧道卡住怎么
办）写在 `umiacs-nexus-gpu/references/jupyter.md`。简单说：在分配里装好 venv/conda 环境 → 用 `gpush`
开个前台 shell 跑 `jupyter notebook --no-browser --port=8889 --ip=0.0.0.0` → 本地跑
`ssh -N -f -L localhost:8888:<计算节点>:8889 <用户名>@nexuscml.umiacs.umd.edu` 建隧道 → 浏览器打开
`localhost:8888`。

## 8. 遇到问题

先看 `umiacs-nexus-gpu/references/troubleshooting.md`，常见的坑都写在里面，包括：

- 登录节点很卡/命令超时 —— 大概率是有人在登录节点跑重计算，别加入他们。
- SLURM 命令在"沙盒"里跑不通 —— 需要完整权限的终端，不能在受限沙盒里跑。
- `gpurun`/`gpush` 报 "No active allocation" —— 卡到期/被抢占/根本没申请过，重新 `gpualloc`。
- `sinfo` 转半天 —— 这个集群的 `sinfo` 本来就慢，多等一会，或者用 `squeue -u $USER`/`gpustatus`。
- `salloc` 报 `invalid partition`/`invalid qos` —— 除了名称打错，也可能是 `cml-high_long` 这类 QoS
  没在你的账号上开通，或者 `cml-furongh` 账号的账单配额被别的 partition 占用了（见上面第 1 节的账单小
  知识）。用 `show_assoc` 或 `sacctmgr show assoc user=$USER` 看看自己到底有哪些权限。

## 目录结构

```
UMIACS_Nexus_Skills/
├── README.md                      <- 你在看的这个：新手上手指南（中文）
└── umiacs-nexus-gpu/              <- 真正的 agent skill（英文，给 Claude Code / Codex 读）
    ├── SKILL.md                   <- agent 的核心操作手册
    ├── scripts/
    │   ├── nexus-init.sh          <- 新账号/新机器初始化
    │   ├── gpualloc               <- 申请一个长期存活的 GPU 分配
    │   ├── gpurun                 <- 在已有分配里跑一条命令
    │   ├── gpush                  <- 从你自己的终端挂到某个 RUNNING job 上
    │   └── gpustatus               <- 查看当前分配状态
    └── references/
        ├── cluster-tiers.md       <- 各级资源的详细信息 + 怎么在集群上验证
        ├── storage.md             <- 数据/checkpoint 该放哪
        ├── jupyter.md             <- 计算节点上跑 Jupyter + SSH 隧道
        └── troubleshooting.md     <- 常见报错和排查思路
```

## 把这个 skill 接到 Claude Code / Codex 里

把 `umiacs-nexus-gpu/` 整个目录复制（或软链接）到你 agent 的 skills 目录下即可，例如 Claude Code：

```bash
cp -r umiacs-nexus-gpu ~/.claude/skills/umiacs-nexus-gpu
```

之后只要对话里提到 Nexus/CML/SLURM GPU、`gpualloc`/`gpurun`/`gpush`，agent 就会自动读取
`SKILL.md` 里的操作规范。
