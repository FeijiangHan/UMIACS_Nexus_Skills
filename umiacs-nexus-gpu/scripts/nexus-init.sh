#!/usr/bin/env bash
# One-time setup for a new user/machine on the Nexus login node.
# Safe to re-run -- every step is idempotent.
#
# What this does:
#   1. Installs gpualloc/gpurun/gpush/gpustatus into ~/bin and makes sure
#      ~/bin is on PATH (appends one line to ~/.bashrc if missing).
#   2. Creates ~/.nexus/ to hold the current-job-id file (keeps clutter out
#      of $HOME's root, unlike the older ~/.cursor_slurm_jobid convention).
#   3. Checks for your CML network scratch directory (/cmlscratch/$USER) --
#      home directories on this cluster are a 30GB NFS mount not meant for
#      datasets/checkpoints (see references/storage.md), so scratch is
#      where experiment data should live.
#   4. Creates a per-project working-directory skeleton (data/, checkpoints/,
#      logs/, code/) under whichever storage location it found, IF the user
#      confirms one (see references/storage.md for the manual fallback).
#
# Run this from the login node (not inside the sandbox -- see SKILL.md).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== 1. Installing helper scripts to ~/bin =="
mkdir -p ~/bin
for f in gpualloc gpurun gpush gpustatus; do
  cp "$SCRIPT_DIR/$f" ~/bin/"$f"
  chmod +x ~/bin/"$f"
  echo "  installed ~/bin/$f"
done

if ! grep -q '# added by umiacs-nexus-gpu skill' ~/.bashrc 2>/dev/null; then
  {
    echo ''
    echo '# added by umiacs-nexus-gpu skill'
    echo 'export PATH="$HOME/bin:$PATH"'
  } >> ~/.bashrc
  echo "  appended ~/bin to PATH in ~/.bashrc (open a new shell, or 'source ~/.bashrc', to pick it up)"
else
  echo "  ~/bin already on PATH per ~/.bashrc, skipping"
fi

echo
echo "== 2. Creating ~/.nexus (job-id bookkeeping) =="
mkdir -p ~/.nexus
echo "  ~/.nexus ready"

echo
echo "== 3. Checking CML network scratch (/cmlscratch/\$USER) =="
TARGET="/cmlscratch/$USER"
# /cmlscratch is automounted -- `test -d` alone can miss it before it's
# been touched, so try `ls` on it first to trigger the automount.
ls "$TARGET" >/dev/null 2>&1
if [ -d "$TARGET" ]; then
  echo "  found: $TARGET"
  read -r -p "Create a project skeleton under $TARGET ? [y/N] " ans || ans="n"
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    mkdir -p "$TARGET"/{data,checkpoints,logs,code,envs}
    echo "  created $TARGET/{data,checkpoints,logs,code,envs}"
    echo "  point your jobs' output/checkpoint dirs at $TARGET, not \$HOME"
  else
    echo "  skipped -- create it manually later with:"
    echo "    mkdir -p $TARGET/{data,checkpoints,logs,code,envs}"
  fi
else
  echo "  $TARGET not found/accessible from this shell."
  echo "  Run 'df -h /cmlscratch/\$USER' yourself and see references/storage.md"
  echo "  -- do NOT default to storing datasets/checkpoints under \$HOME (only 30GB, backed up NFS)."
fi

echo
echo "== Done. Open a new shell (or 'source ~/.bashrc') to get gpualloc/gpurun/gpush/gpustatus on PATH. =="
