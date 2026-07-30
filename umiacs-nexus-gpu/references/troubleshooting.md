# Troubleshooting

## "command not found: gpualloc" (or gpurun/gpush/gpustatus)
`~/bin` isn't on `PATH` yet, or `nexus-init.sh` hasn't been run. Run
`bash scripts/nexus-init.sh` from this skill directory, then open a new
shell or `source ~/.bashrc`.

## SLURM commands hang or fail only inside a sandboxed/restricted shell
`salloc`, `srun`, `squeue`, `scancel`, `sinfo`, and the `gpu*` helpers talk
to the SLURM controller and need full network/process permissions. If
you're running inside a restricted coding-agent sandbox, these calls will
fail or hang -- run them in the unrestricted/full-permission mode instead.
This is a known characteristic of this environment, not a cluster problem.

## `gpurun`/`gpush` says "No active allocation" / "not RUNNING"
The allocation referenced by `~/.nexus/current_jobid` (or `$GPU_JOBID` if
you set it) has ended, been preempted, or was never created. Run
`gpustatus` to see current jobs, then `gpualloc <profile>` again if
nothing is RUNNING. Don't retry the same failing `gpurun` call in a loop --
a dead allocation won't come back on its own.

## `sinfo` is very slow or times out
This is a known characteristic of this cluster's `sinfo` -- allow extra
time rather than assuming it hung. Prefer `squeue -u $USER` for quick
status checks; reach for `sinfo`/`gpustatus -v` only when you need
partition-wide node availability.

## `show_available_nodes` doesn't work
This helper is broken in some environments (missing Python 3.6). Don't use
it -- use `squeue -u $USER` and `sinfo` instead, as above.

## Login node feels slow / commands are timing out
The login node has no GPU and strict CPU/memory limits, and is shared by
everyone on the cluster -- it's common for someone to accidentally run
heavy computation there and degrade it for everyone. Never run training,
evaluation, or other GPU/CPU-heavy work directly on the login node: use
`gpurun` inside an allocation for short work, or a submitted `sbatch`
script for anything long. See SKILL.md's "Golden rules" section.

## salloc is rejected with "invalid partition" or "invalid qos"
Run the UMIACS-provided check:
```bash
show_assoc
sacctmgr show assoc user=$USER format=account,partition,qos%40
```
to see what you're actually entitled to. Two known causes per the wiki:
`cml-high_long`/`cml-very_high` QoS "may not be available to all faculty
accounts" (ask staff@umiacs.umd.edu to enable it for `cml-furongh` if
missing), and the `cml-furongh` account's billing limit is shared across
whatever partition you submit to -- if it's exhausted, `salloc` will
reject requests even for the right partition/QoS names. Don't silently
substitute a guessed name -- tell the user what changed and why.

## Job runs but modules/conda don't seem loaded, or works on one node but not another
If the compute node's OS differs from the submission node's, or you're
using GNU Modules non-interactively, the UMIACS Modules setup needs the
non-interactive-shell handling described in their Modules documentation --
this is why the bundled `gpurun`/`gpush` explicitly use `bash -ic` (`-i`
for interactive) rather than a bare `bash -c`, so `~/.bashrc` (and any
conda/module init in it) actually gets sourced.

## Job is stuck PENDING for a long time
Check the reason with `squeue -u $USER -o "%i %T %r"` (the `%r` reason
code, e.g. `Resources`, `Priority`, `QOSMaxGRESPerUser`) rather than
guessing. If it's a hard resource cap (e.g. you're already at your QOS's
GPU limit), free up an existing allocation with `scancel` or fall back to
the next tier in `cluster-tiers.md` instead of waiting indefinitely.

## Multiple agent sessions interfering with each other's allocation
Each `gpualloc` call overwrites `~/.nexus/current_jobid` with the newest
job. If a session needs to stay pinned to *its own* allocation regardless
of what other sessions do, it must `export GPU_JOBID=<jobid>` right after
its own `gpualloc` call -- see SKILL.md's "Multiple sessions" section.
