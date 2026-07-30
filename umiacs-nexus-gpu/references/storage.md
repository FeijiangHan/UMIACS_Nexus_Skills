# Storage conventions

Verified against the official `Nexus/CML` wiki page (exported by the user
on 2026-07-30). CML has three types of writable user storage and two
types of read-only shared storage:

| Location | Path | Size | Backed up? | Use for |
|---|---|---|---|---|
| Home directory | `/nfshomes/<username>` | 30GB | Yes (snapshots + backups) | Dotfiles, small configs, `~/bin` helpers, `~/.nexus/current_jobid`. **Not** for datasets/checkpoints. |
| Project directory | `/fs/cml-projects/<name-you-choose>` | up to 6TB, 120-day allocation | Yes (nightly) | Long-lived project data shared across a team; requires faculty (+ director if >3TB) approval via staff@umiacs.umd.edu. |
| Network scratch | `/cmlscratch/<username>` | 200GB default (extendable to 800GB by request, more needs faculty approval) | **No** -- no snapshots, no backups | Day-to-day datasets, checkpoints, logs, conda/venv envs. This is the default answer to "where do I put my stuff." |
| Local scratch (per compute node) | `/scratch0`, `/scratch1`, ... | node-dependent | **No**, and unaccessed files are deleted after 90 days by a monthly `tmpwatch` job | Fastest available storage, but only for the lifetime of a single job -- stage data in at job start, stage results out before the job ends. |
| Datasets (read-only) | `/fs/cml-datasets` | -- | -- | Shared curated datasets. |
| Models (read-only) | `/fs/cml-models` | -- | -- | Shared pretrained model weights. |

## Rule of thumb

- **Never put datasets, checkpoints, or conda/venv environments under
  `/nfshomes/$USER` ($HOME).** 30GB disappears fast and the wiki explicitly
  asks users not to share data there.
- **Default to `/cmlscratch/$USER`** for anything experiment-related. It's
  automounted -- if `ls /cmlscratch/$USER` looks empty or the path seems
  not to exist yet, `cd` into it first (per the wiki, automounts don't
  always show up until accessed) or use the fully-qualified path directly.
- Use `/fs/cml-projects/<name>` instead of scratch only when the data
  needs to survive longer than you'd trust unprotected scratch to, or
  needs to be shared with labmates under a stable path -- it requires a
  request to staff (see table above), so don't default to it for routine
  experiment output.
- Use local `/scratch0`-style paths inside a job only when I/O speed
  actually matters (e.g. very large datasets, small-file-heavy training
  loops) and you reliably copy results out before the allocation ends --
  anything left there past job end may vanish (90-day `tmpwatch`, but
  don't rely on the grace period).

## Check your actual quota/usage

```bash
df -h ~                 # home quota, per the wiki's documented command
df -h /cmlscratch/$USER
du -sh /cmlscratch/$USER/*  # what's eating your scratch space
```

## Per-experiment layout

Use a consistent shape under `/cmlscratch/$USER/<project-name>/` so
multiple experiments -- and multiple agent sessions sharing the same
account -- don't collide:

```
/cmlscratch/$USER/<project-name>/
├── code/          # checkout or symlink to the repo being run
├── data/          # input datasets (read-mostly; or symlink into /fs/cml-datasets)
├── checkpoints/   # model checkpoints, one subdir per run
│   └── <run-id>/
├── logs/          # stdout/stderr, tensorboard, wandb offline dirs
└── envs/          # conda/venv environments, if not using module-provided ones
```

`nexus-init.sh` detects whether `/cmlscratch/$USER` exists and offers to
create this skeleton automatically. Use a distinct `<run-id>` (timestamp
or descriptive slug) per run so concurrent runs don't overwrite each
other's checkpoints or logs.

## Before deleting anything

Network scratch has **no backups and no snapshots**, and local scratch is
purged automatically after 90 days of inaccess. Never `rm -rf` a
checkpoints/ or data/ directory without confirming with the user first --
treat it the same as any other hard-to-reverse action; there is no
undo here.
