#!/bin/bash
# cgroup v2 bootstrap — runs at container startup (as root, before exec "$@").
#
# On cgroup v2 systems the unified hierarchy is mounted at /sys/fs/cgroup and
# resource controllers must be explicitly delegated down the tree before isolate
# can create sub-cgroups. This script:
#   1. Detects whether the host is running cgroup v2 (unified hierarchy).
#   2. Enables cpu, memory, and pids controllers in the root cgroup AND in an
#      "isolate" sub-cgroup so that isolate --cg can create per-sandbox groups.
#   3. Is a no-op on cgroup v1 — it exits cleanly without touching anything.
#
# Rationale for writing to cgroup.subtree_control instead of cgroup.controllers:
#   cgroup.controllers is read-only (kernel-managed). cgroup.subtree_control is
#   the write target for delegating controllers to children.
#
# The script uses "|| true" on every write because Docker may already have
# enabled some controllers, and writing an already-active controller is an EBUSY
# error on some kernels — we want to continue either way.

set -e

CGROUP_PATH="/sys/fs/cgroup"

if [ -f "$CGROUP_PATH/cgroup.controllers" ]; then
    echo "[judge0-bootstrap] cgroup v2 detected — enabling controllers"

    # Enable controllers in the root cgroup's subtree.
    echo "+cpu +memory +pids" > "$CGROUP_PATH/cgroup.subtree_control" 2>/dev/null || true

    # Create a dedicated sub-cgroup for isolate sandboxes and delegate the same
    # controllers into it. isolate will create per-box sub-cgroups under here
    # when invoked with --cg (or the equivalent cg= setting in isolate.conf).
    mkdir -p "$CGROUP_PATH/isolate"
    echo "+cpu +memory +pids" > "$CGROUP_PATH/isolate/cgroup.subtree_control" 2>/dev/null || true

    echo "[judge0-bootstrap] Controllers active in root: $(cat $CGROUP_PATH/cgroup.controllers)"
    echo "[judge0-bootstrap] Controllers active in /isolate: $(cat $CGROUP_PATH/isolate/cgroup.controllers 2>/dev/null || echo 'n/a')"
else
    echo "[judge0-bootstrap] cgroup v1 detected — skipping v2 bootstrap"
fi

exec "$@"
