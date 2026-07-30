# Nexus/CML cluster tiers (Furong Huang lab)

Verified against the official UMIACS wiki (`Nexus/CML` and `SLURM` pages, as
exported by the user on 2026-07-30) plus the lab's own usage notes. Where a
number could plausibly change over time (billing limits, QoS caps), it's
called out as "at time of writing" -- re-check with the commands below if
something is rejected.

## Login / submission nodes

SSH to **`nexuscml.umiacs.umd.edu`** to reach a submission node (this is a
round-robin alias). The two actual submission nodes behind it are:

- `nexuscml00.umiacs.umd.edu`
- `nexuscml01.umiacs.umd.edu`

If you write to a **local** directory on a submission node (`/tmp`,
`/scratch0`), you must reconnect to that *same* node later to see it again
-- don't assume the alias always lands you on the same box. Submission
nodes have no GPU and are shared, so treat them like any other login node
(see Golden rules in SKILL.md).

## Partitions

| Partition | Who | Notes |
|---|---|---|
| `cml-dpart` | Any CML user | Default partition. Guaranteed allocations. |
| `cml-scavenger` | Any CML user | Longer time / more resources than `cml-dpart`, but preemptable by any other `cml-*` partition job. |
| `cml-furongh` | Furong Huang's sponsored users (our lab) | Exclusive priority access to the lab's purchased nodes. Guaranteed. |
| `cml-ramani`, `cml-sfeizi` | Other faculty's sponsored users | Not ours -- don't submit here. |
| `cml-director` | Users named by CML's director | Not lab-specific. |
| `scavenger` | Institute-wide (Nexus) | CML nodes also sit in this institute-wide preemptible partition. Lowest preemption priority: any `cml-*` job (other than `cml-scavenger`) can preempt both `cml-scavenger` and `scavenger` jobs; `cml-scavenger` jobs can in turn preempt `scavenger` jobs. |

## Accounts

The base account `cml` is available to everyone and gets you the
`cml-default`/`cml-medium` QoS only, with a modest shared billing limit. Our
lab's sponsored account is **`cml-furongh`** -- use it to get the higher
QoS tiers and priority on the lab's own nodes.

Check what you're actually entitled to before assuming a QoS/partition is
available:

```bash
show_assoc                       # UMIACS wrapper, shows your account/QoS associations
sacctmgr show assoc user=$USER format=account,partition,qos%40
```

**Billing gotcha (from the wiki, don't skip this):** the `cml-furongh`
account's billing limit is charged no matter which partition you submit
to. If you use the `cml-furongh` *account* while submitting to the
`cml-dpart` *partition*, you consume the same billing pool that gates your
access to the `cml-furongh` *partition* (the lab's own nodes). Keep
`account=cml-furongh` paired with `partition=cml-furongh` for the
dedicated-node case; don't casually mix them.

## QoS reference (from `show_qos --all | grep cml`, at time of writing)

| QoS | Max wall time | Max TRES (per job) | Max jobs/user | Max TRES/user |
|---|---|---|---|---|
| `cml-default` | 7-00:00:00 | cpu=4, gpu=1, mem=32G | 2 | -- |
| `cml-high` | 1-12:00:00 | cpu=16, gpu=4, mem=128G | 2 | -- |
| `cml-high_long` | 14-00:00:00 | cpu=32, gpu=8 | 8 | gpu=8 |
| `cml-medium` | 3-00:00:00 | cpu=8, gpu=2, mem=64G | 2 | -- |
| `cml-scavenger` | 3-00:00:00 | gpu=24 | -- | gpu=24 |
| `cml-very_high` | 1-12:00:00 | cpu=32, gpu=8, mem=256G | 8 | gpu=12 |

Two things worth internalizing:
- **`cml-high_long` caps you at 8 GPUs total across your own jobs at once**
  (`MaxTRESPU gres/gpu=8`). Requesting an 8-GPU job under this QoS uses your
  *entire* per-user GPU quota under it -- you can't also run a second job
  under the same QoS until the first ends.
- `cml-high_long` and `cml-very_high` "may not be available to all faculty
  accounts" per the wiki -- if `salloc --qos=cml-high_long` is rejected,
  that's why; ask staff@umiacs.umd.edu to have it enabled for
  `cml-furongh` if the lab hasn't already.
- Not specifying `--qos` gets you `cml-default` on a CML account -- always
  set it explicitly for anything beyond a trivial 1-GPU/32GB job.

## Priority order for this lab

1. **`gpualloc furongh`** (or `furongh1` for a single-GPU quick test) --
   `account=cml-furongh partition=cml-furongh qos=cml-high_long`. Try this
   first; it's the lab's own guaranteed hardware.
2. **`gpualloc tron`** -- cluster-wide shared RTX A6000 pool
   (`partition=tron qos=high`). Use when the lab's nodes are full or down.
3. **`gpualloc scavenger`** -- `partition=cml-scavenger`, preemptable, for
   restartable/checkpointed work only, cluster-wide GPU cap of 24 at a
   time (shared across all CML users under that QoS, not just you).

## Lab hardware

| Node | GPUs |
|---|---|
| cml30 | 8x RTX A6000 |
| cml36 | 8x H200 |
| cml38 | 8x B300 |
| cml37 | 4x RTX 6000 (Blackwell), described as the lab's "local workstation" |

The wiki confirms `cml30/34/37` and similar nodes exist in the CML
partition's network fabric (`cml[17-28,30-32,34,37]`, `cml[35-36,38]`), but
does **not** publish a GPU-per-node table -- the hardware breakdown above
comes from the lab's own notes, not the wiki. Before targeting a specific
node with `--nodelist=cml30` (etc.), confirm it's up and has the GPU type
you expect:

```bash
sinfo -p cml-furongh -o "%N %T %G %C %m"
```

GPU **gres type strings** (e.g. whether H200 shows up as `gpu:h200` or
something else) aren't published either -- read them off the `sinfo`
output above rather than guessing, especially for the newer H200/B300
hardware.

## Getting an account

New lab members request a Nexus account through
`intranet.umiacs.umd.edu`, listing **furongh@umiacs.umd.edu** as PI. This
is a human step -- an agent cannot request accounts on someone's behalf.
See the top-level README.md for the step-by-step version aimed at
brand-new users. Faculty (or their delegate) manage who has access to the
`cml-furongh` account via the Directory app's Security Groups section
(`intranet.umiacs.umd.edu/directory/secgroup`, group prefixed `cml_`).

## References

- UMIACS Nexus/CML wiki: https://wiki.umiacs.umd.edu/umiacs/index.php/Nexus/CML
- UMIACS SLURM wiki: https://wiki.umiacs.umd.edu/umiacs/index.php/SLURM
- SLURM upstream quickstart: https://slurm.schedmd.com/quickstart.html
- Contact for cluster issues: staff@umiacs.umd.edu

These wiki pages are intranet-only -- an agent running outside the campus
network/VPN can't fetch them. If new facts are needed beyond what's in
this file, ask the human to check and report back rather than guessing.
