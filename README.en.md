# UMIACS_Nexus_Skills

A coding-agent skill (Claude Code / Codex, etc.) for the **UMD UMIACS / Nexus GPU cluster**,
built for members of the Furong Huang (furongh) lab. The actual skill lives in
[`umiacs-nexus-gpu/`](umiacs-nexus-gpu/) (`SKILL.md` + `scripts/` + `references/`). This
top-level README is aimed at someone who has **never used this remote GPU cluster before** --
it walks through going from zero to your first GPU job.

> ℹ️ The partition/QoS/storage details below have been checked against the official UMIACS
> wiki pages (`Nexus/CML`, `SLURM`) as provided by the lab -- they aren't guesses. Cluster
> configuration can still change over time, so verify with the commands shown below before
> relying on anything. If a command errors with `invalid partition`/`invalid qos`, the naming
> may have changed -- check with staff@umiacs.umd.edu or the wiki directly:
> - https://wiki.umiacs.umd.edu/umiacs/index.php/Nexus/CML
> - https://wiki.umiacs.umd.edu/umiacs/index.php/SLURM

---

## 1. What the cluster is, and its tiers

UMIACS's Nexus cluster uses **SLURM** for scheduling. You never log directly into a machine
with GPUs -- instead:

```
Your computer --ssh--> submission node (no GPU)
                          |
                          | SLURM commands (salloc/srun) request GPU(s)
                          v
                       compute node (the actual GPU machine)
```

The login address is **`nexuscml.umiacs.umd.edu`** (a round-robin alias in front of the two
actual submission nodes, `nexuscml00`/`nexuscml01`). **The submission node has no GPU, has
tight CPU/memory limits, and is shared by the entire lab (and beyond).** Never run training,
inference, or even a "quick test" directly there -- it's a common mistake that slows the whole
system down for everyone. The submission node is only for lightweight things: `ssh` in, `cd`,
`git`, editing files, and submitting SLURM jobs.
(Small gotcha: if you write to a local path on the submission node, e.g. `/tmp` or `/scratch0`,
you'll need to reconnect to that same node later to see it again.)

Our lab has access to a few resource tiers, in priority order (full detail, including the
official QoS limits table, is in `umiacs-nexus-gpu/references/cluster-tiers.md`):

| Priority | How to request | Notes |
|---|---|---|
| 1️⃣ Lab's dedicated nodes | `account=cml-furongh partition=cml-furongh qos=cml-high_long` | cml30 (8x A6000), cml36 (8x H200), cml38 (8x B300), cml37 (4x RTX 6000 Blackwell). Use this first. QoS caps: max 8 GPUs per user at once, max 14-day wall time; some accounts may not have this QoS enabled by default -- ask staff to turn it on if it's rejected. |
| 2️⃣ Shared `tron` partition | `partition=tron qos=high` | Shared RTX A6000 pool, cluster-wide. Use when the lab's own nodes are full or down. |
| 3️⃣ Scavenger (opportunistic) | `partition=cml-scavenger qos=cml-scavenger` | Institute-wide, preemptible at any time, max 3-day wall time, 24-GPU cap shared across *all* CML users. Only for restartable/checkpointed work. |

> Billing gotcha: the `cml-furongh` account's billing limit is charged no matter which
> partition you submit to. Using the `cml-furongh` account against the default `cml-dpart`
> partition eats into the same quota that gates access to the `cml-furongh` partition (the
> lab's own nodes) -- keep account and partition paired as `cml-furongh`/`cml-furongh` and
> don't mix them.

## 2. Getting an account (a human step -- an agent can't do this for you)

1. Go to `intranet.umiacs.umd.edu`.
2. Request a Nexus account with your UMD email, listing **furongh@umiacs.umd.edu** as PI.
3. Wait for approval (usually handled by lab/UMIACS admins).
4. Once approved, UMIACS will give you login details (typically
   `ssh <username>@nexuscml.umiacs.umd.edu`). Confirm specifics with a labmate or
   staff@umiacs.umd.edu if anything's unclear.

## 3. First login: initialize your environment

Once logged into the submission node (with full shell permissions, not a restricted sandbox --
SLURM commands need it), run the init script once:

```bash
cd umiacs-nexus-gpu
bash scripts/nexus-init.sh
```

It's idempotent (safe to re-run) and does the following:

- Installs the four helper scripts (`gpualloc` / `gpurun` / `gpush` / `gpustatus`) into
  `~/bin`, and adds `~/bin` to `PATH` via `~/.bashrc`.
- Creates `~/.nexus/` to remember which SLURM job you're currently using.
- Checks whether `/cmlscratch/$USER` (CML's network scratch) is available, and offers to lay
  out a `data/checkpoints/logs/code/envs` skeleton under it.

**Why the storage check matters:** your `$HOME` (`/nfshomes/$USER`) only has a **30GB** quota
(backed up, but small) -- the wiki explicitly asks users not to put datasets or model
checkpoints there. The real workspace is `/cmlscratch/$USER` (200GB by default, extendable to
800GB, **not backed up, no snapshots**). If you need long-term, backed-up, team-shared
storage, you can request a `/fs/cml-projects/<project-name>` allocation (up to 6TB, 120-day
cycle, requires faculty approval). See `umiacs-nexus-gpu/references/storage.md` for the full
breakdown, including the read-only `/fs/cml-datasets` / `/fs/cml-models` shares and per-node
local scratch (`/scratch0`, etc.).

Open a new shell (or `source ~/.bashrc`) afterward so the updated `PATH` takes effect.

## 4. Run your first GPU test job (fastest path)

```bash
# Step 1: allocate one GPU for 8 hours, return it when done
gpualloc furongh1 8:00:00 1

# gpualloc prints something like:
#   Allocated job id: 123456  (profile=furongh1 count=1 time=8:00:00)
#   export GPU_JOBID=123456   <- only needed if you want THIS session pinned to this job
#                                (relevant when multiple sessions run at once)

# Step 2: run a test command inside that allocation to confirm the GPU actually works
gpurun 'nvidia-smi'
gpurun 'python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"'

# Step 3: (optional) attach to the same job from another terminal, e.g. for an interactive shell
gpush          # jumps straight in if there's exactly one RUNNING job; prompts if there are several

# Step 4: check current status
gpustatus
```

- **Short tasks** (a quick test, a small eval, a few minutes of debugging): run them yourself
  with `gpurun '<command>'` inside the existing allocation. Don't allocate a new job per
  command.
- **Long tasks** (a real training run, a large sweep, multi-hour jobs): don't run these inside
  your interactive allocation. Write an `sbatch` script and submit it as a real SLURM job
  (`sbatch xxx.sh`) -- that way the job survives your terminal/session ending, and logging is
  handled properly.

## 5. Shutting down / releasing when you're done

**An allocation consumes the lab's shared quota from the moment it's granted, whether or not
you're actually using it** -- release it as soon as you're done:

```bash
# release the currently-default allocation
scancel $(cat ~/.nexus/current_jobid)

# or release a specific job id
scancel 123456

# see all your jobs (make sure you didn't forget to close one)
squeue -u $USER
```

## 6. Multiple agent sessions / terminals sharing the same account

If you (or your coding agent) have several sessions using GPUs at once, note that `gpurun`/
`gpush` default to "whatever job the most recent `gpualloc` recorded" (stored in
`~/.nexus/current_jobid`). If a session needs to stay pinned to *its own* allocation and not
get its default target hijacked by another session's later `gpualloc` call, run this right
after that session's own `gpualloc`:

```bash
export GPU_JOBID=<the job id gpualloc just printed>
```

That session's `gpurun`/`gpush` calls will then stay locked to that job regardless of what
other sessions do.

## 7. Need to run a Jupyter notebook?

The cluster officially supports running Jupyter on a compute node and tunneling back to your
local machine over SSH. Full steps (including common gotchas like port conflicts and a stuck
tunnel) are in `umiacs-nexus-gpu/references/jupyter.md`. Short version: set up a venv/conda
env inside the allocation -> use `gpush` to open a foreground shell and run
`jupyter notebook --no-browser --port=8889 --ip=0.0.0.0` -> from your local machine, run
`ssh -N -f -L localhost:8888:<compute-node>:8889 <username>@nexuscml.umiacs.umd.edu` -> open
`localhost:8888` in a browser.

## 8. Troubleshooting

Check `umiacs-nexus-gpu/references/troubleshooting.md` first -- common issues include:

- Submission node feels slow / commands time out -- likely someone else running heavy compute
  there; don't join them.
- SLURM commands fail inside a "sandboxed" shell -- they need full permissions, not a
  restricted sandbox.
- `gpurun`/`gpush` report "No active allocation" -- the job expired, was preempted, or was
  never created; run `gpualloc` again.
- `sinfo` takes forever -- this cluster's `sinfo` is known to be slow; wait it out, or use
  `squeue -u $USER`/`gpustatus` instead.
- `salloc` errors with `invalid partition`/`invalid qos` -- besides a typo, it can also mean
  a QoS like `cml-high_long` isn't enabled on your account yet, or the `cml-furongh` account's
  billing quota is being eaten by another partition (see the billing note in section 1). Run
  `show_assoc` or `sacctmgr show assoc user=$USER` to see what you actually have access to.

## Directory layout

```
UMIACS_Nexus_Skills/
├── README.md                      <- Chinese-language onboarding guide
├── README.en.md                   <- this file: English onboarding guide
└── umiacs-nexus-gpu/              <- the actual agent skill (for Claude Code / Codex)
    ├── SKILL.md                   <- the agent's core operating manual
    ├── scripts/
    │   ├── nexus-init.sh          <- first-time setup for a new account/machine
    │   ├── gpualloc               <- request one long-lived GPU allocation
    │   ├── gpurun                 <- run a command inside an existing allocation
    │   ├── gpush                  <- attach to a RUNNING job from your own terminal
    │   └── gpustatus               <- check current allocation status
    └── references/
        ├── cluster-tiers.md       <- full resource-tier detail + how to verify on the cluster
        ├── storage.md             <- where data/checkpoints should live
        ├── jupyter.md             <- running Jupyter on a compute node + SSH tunnel
        └── troubleshooting.md     <- common errors and how to diagnose them
```

## Wiring this skill into Claude Code / Codex

Copy (or symlink) the entire `umiacs-nexus-gpu/` directory into your agent's skills directory,
e.g. for Claude Code:

```bash
cp -r umiacs-nexus-gpu ~/.claude/skills/umiacs-nexus-gpu
```

After that, whenever the conversation mentions Nexus/CML/SLURM GPUs or `gpualloc`/`gpurun`/
`gpush`, the agent will automatically read the operating rules in `SKILL.md`.
