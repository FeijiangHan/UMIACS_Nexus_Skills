# Running Jupyter on a compute node

Verified against the official UMIACS `SLURM` wiki page. Use this when the
user wants an interactive notebook against an allocated GPU rather than a
plain shell.

## 1. Set up the environment (once, inside an allocation)

```bash
gpurun 'python -m venv ~/jupyterenv && source ~/jupyterenv/bin/activate && pip install jupyter'
```

(Conda works too, per the wiki -- use whichever the project already relies
on.)

## 2. Start the notebook server inside the allocation

```bash
gpush   # or: gpurun-based long-lived shell, since this needs to stay running
# inside that shell:
source ~/jupyterenv/bin/activate
jupyter notebook --no-browser --port=8889 --ip=0.0.0.0
```

Note the **compute node hostname** this lands on (`squeue -j <jobid> -o
%N`, or `hostname` inside the shell) -- you need it for the tunnel below.
This shell must stay open for the notebook to keep running, so this is a
job for the user's own terminal (via `gpush`), not something an agent
should hold open on the user's behalf.

## 3. Tunnel from the user's local machine

```bash
ssh -N -f -L localhost:8888:<compute-node>:8889 <username>@nexuscml.umiacs.umd.edu
```

This produces no output on success (by design, due to the `-N -f`
flags). If the UMIACS network isn't reachable directly (off campus,
no VPN), this step will hang or fail -- that's a network reachability
issue, not a Jupyter problem.

Then open `localhost:8888` in a browser. Newer Jupyter versions require a
token from the server's terminal output
(`localhost:8888/?token=<...>`) -- copy it from where `jupyter notebook`
printed it in step 2.

## Gotchas (from the wiki)

- If port 8889 is already taken on that compute node by someone else's
  process, pick a different ephemeral port and use it consistently in
  both the `jupyter notebook --port=` and the `ssh -L` command.
- The `ssh -N -f -L ...` tunnel process can't be interrupted with Ctrl+C.
  Hitting Ctrl+Z instead leaves the local port stuck until restart -- if
  you need to redo the tunnel, use a different local port rather than
  fighting the stuck one.
- To confirm the notebook is actually running on the GPU node you
  expect, run `import socket; socket.gethostname()` in a cell.
