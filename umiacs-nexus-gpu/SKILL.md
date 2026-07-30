---
name: umiacs-nexus-gpu
description: Use this skill whenever the user wants to run, debug, train, evaluate, or benchmark anything on the UMD UMIACS/Nexus SLURM cluster (CML partition, cml-furongh lab account, tron partition, or any mention of Nexus/CML/SLURM GPU access, gpualloc/gpurun/gpush, salloc/srun on this cluster, or "our GPU cluster"/"school GPUs" in the context of Furong Huang's lab). Also use it when the user is setting up a brand-new machine or account for this cluster and needs initialization, or hits errors like "no active allocation", "invalid partition/qos", stuck logins, or a slow/overloaded login node. Covers account tiers and priority order, safe login-node vs compute-node behavior, allocating and reusing GPU allocations across multiple agent sessions, when to run things directly vs prepare an sbatch script for the user, and where to store data/checkpoints.
---

# UMIACS/Nexus GPU cluster (Furong Huang lab, CML partition)

You are operating an agent session with shell access to one of the Nexus
cluster's **submission nodes** (reached via `nexuscml.umiacs.umd.edu`,
backed by `nexuscml00`/`nexuscml01`). This node has no GPU and tight
CPU/memory limits, and is shared by everyone waiting to submit jobs. The
whole point of this skill is to get you onto a real GPU allocation for
actual work while never treating the submission node itself as a place to
compute. (If you write to a *local* path like `/tmp` or `/scratch0` on one
submission node, note that it won't be visible if you reconnect and land
on the other one.)

First time on this machine/account? Jump to "First-time setup" below before
anything else. Already set up? Skip to "Standard workflow."

## Golden rules (read these before running anything GPU-heavy)

1. **Never run GPU/CPU-heavy work directly on the submission node.** Not
   even "just a quick test." It's shared cluster-wide, and one person
   accidentally running compute there routinely degrades it for everyone
   else logged in system-wide. Lightweight things (`git`, `ls`, `cat`,
   editing files, `tail -f` on a log) are fine directly on the submission
   node -- anything that touches a GPU or does real CPU work must go
   through an allocation.
2. **SLURM commands (`salloc`, `srun`, `squeue`, `scancel`, `sinfo`) and the
   `gpu*` helpers must run with full shell permissions, not inside a
   restricted/sandboxed tool-execution mode.** They talk to the SLURM
   controller and will fail or hang under a locked-down sandbox. If your
   tool-calling environment has a "sandboxed" vs "full access" bash mode,
   use full access for these.
3. **Short vs long work is a hard fork, not a judgment call you skip:**
   - Short (a quick check, a small eval, a few minutes of debugging, under
     ~30 min): run it yourself with `gpurun '<command>'` inside the
     existing allocation.
   - Long (full training runs, large sweeps, anything multi-hour): do
     **not** run it yourself, even inside an allocation. Prepare the exact
     command (or a complete `sbatch` script) and hand it to the user to
     submit with `sbatch`. Long jobs need to survive your session ending,
     get proper log files, and not tie up an interactive allocation.
   - If you're not sure which bucket a task falls in, ask the user rather
     than guessing wrong in either direction.
4. **`sinfo` can be slow on this cluster -- give it time rather than assuming
   it's hung.** For a quick "what's running" check, prefer
   `squeue -u $USER` or the bundled `gpustatus`.
5. **`show_available_nodes` is broken in some environments** (missing
   Python) -- don't use it; use `squeue`/`sinfo` instead.

## First-time setup

If this is a new machine or account, or you're not sure `gpualloc` /
`gpurun` / `gpush` / `gpustatus` exist yet, run the init script from the
submission node (full-permission shell, not sandboxed):

```bash
bash scripts/nexus-init.sh
```

This installs the four helper scripts to `~/bin`, adds `~/bin` to `PATH`
in `~/.bashrc`, creates `~/.nexus/` for job-id bookkeeping, and checks for
`/cmlscratch/$USER` (home directories here are a 30GB backed-up NFS mount
-- don't put datasets or checkpoints there; see `references/storage.md`).
It's idempotent; safe to re-run if you're unsure whether it already
happened. Open a new shell or `source ~/.bashrc` afterward so the new
`PATH` takes effect.

If the user doesn't have a Nexus account yet at all, that's a human step
you can't do for them: they request one at `intranet.umiacs.umd.edu`
listing `furongh@umiacs.umd.edu` as PI. Point them at the top-level
README.md for the walkthrough.

## Cluster tiers (which account/partition/qos to request)

Full detail, including exact hardware per node and how to verify names
live on the cluster, is in `references/cluster-tiers.md` -- read it before
picking anything non-default. Summary, in priority order:

1. **`gpualloc furongh`** (or `furongh1` for a single-GPU quick test) --
   the lab's own dedicated nodes (`account=cml-furongh`,
   `partition=cml-furongh`, `qos=cml-high_long`). Try this first. Note
   this QoS caps you at 8 GPUs total across your own concurrent jobs, and
   isn't guaranteed to be enabled on every faculty account -- if `salloc`
   rejects it, that's the likely reason (see cluster-tiers.md).
2. **`gpualloc tron`** -- cluster-wide shared RTX A6000 pool
   (`partition=tron`, `qos=high`). Use when tier 1 is full or down.
3. **`gpualloc scavenger`** -- institute-wide preemptible partition
   (`cml-scavenger`). Only for restartable, checkpointed work -- it can be
   killed by a higher-priority job at any time, and is capped at 24 GPUs
   total shared across all CML users on that QoS, not just you.

Pick the profile, GPU count, and time limit based on what the task
actually needs and what's currently free (`gpustatus -v` or `sinfo`), then
**propose it to the user and get confirmation before allocating** --
`gpualloc` queues a real job and consumes the lab's shared quota. Only
allocate without asking if the user has explicitly said to go ahead.

## Standard workflow

```bash
# 1. Allocate once, reuse many times.
gpualloc furongh1 8:00:00 1      # profile, time, gpu count

# 2. Run short things inside it.
gpurun 'python train.py --smoke-test'

# 3. Check status any time.
gpustatus

# 4. When fully done, release it.
scancel $(cat ~/.nexus/current_jobid)
```

Do not request a new allocation per command -- `gpualloc` is for one
long-lived job that `gpurun`/`gpush` then target repeatedly. Re-allocating
per command wastes queue time and quota.

If `gpurun` or `gpush` report "No active allocation" or "not RUNNING",
stop and tell the user the allocation is gone (ended, preempted, or never
created) rather than retrying blindly -- they need to decide whether to
`gpualloc` again.

## Multiple jobs / multiple agent sessions sharing the account

`gpurun` and `gpush` target `$GPU_JOBID` if it's set in the current shell,
otherwise the most recent job recorded in `~/.nexus/current_jobid`
(written by the last `gpualloc` call from *any* session). This matters
when more than one agent session or terminal is working against the same
account at once:

- If this session needs a dedicated allocation that stays fixed even if
  another session runs `gpualloc` later, export the pin right after
  allocating: `export GPU_JOBID=<jobid>` (printed by `gpualloc`).
- The user can attach to any RUNNING job from their own terminal with
  `gpush` (prompts to pick one if several are RUNNING) or `gpush <jobid>`
  for a specific one.
- Release with `scancel <jobid>` when a job is no longer needed --
  allocations consume the lab's shared GPU quota for their entire time
  limit whether or not anything is actually running on them, so don't
  leave one idle longer than necessary.

## Storage: where experiment data and checkpoints live

Never point a job's dataset, checkpoint, log, or conda-env path at
`$HOME` (`/nfshomes/$USER`, 30GB, backed-up NFS). Default to
`/cmlscratch/$USER` (200GB, not backed up) for experiment data instead --
see `references/storage.md` for the full breakdown (project directories,
local per-node scratch, read-only dataset/model shares) and the
recommended per-project directory layout.

## Running a Jupyter notebook

If the user wants an interactive notebook against an allocation rather
than a shell, see `references/jupyter.md` for the verified
venv-inside-allocation + SSH-tunnel workflow. The notebook server itself
needs to keep running in a foreground shell, so start it via `gpush` from
the user's own terminal, not something an agent session holds open.

## Preparing long jobs for the user to submit

For anything that should not run inside your own interactive allocation
(see Golden rule 3), write a complete `sbatch` script rather than a bare
command line -- it should set `--account`/`--partition`/`--qos` matching
the tier chosen above, request the GPUs/time/mem the task needs, `cd` into
the right scratch directory, activate the right environment, and redirect
output to a log file under that project's `logs/` directory. Hand the
script and the exact `sbatch path/to/script.sh` invocation to the user;
don't submit it yourself unless they've asked you to.

## Troubleshooting

Common failure modes (login-node overload, sandbox restrictions, stuck
PENDING jobs, invalid partition/qos, cross-session job-id confusion) and
how to diagnose each are in `references/troubleshooting.md`. Check there
before improvising a workaround.
