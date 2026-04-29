#!/bin/bash
# Judge0 Docker entrypoint.
#
# Step 1: Bootstrap cgroup v2 controllers at runtime (before switching to the
#         judge0 user). On cgroup v1 systems this block is a no-op.
CGROUP_PATH="/sys/fs/cgroup"
if [ -f "$CGROUP_PATH/cgroup.controllers" ]; then
    echo "[judge0-bootstrap] cgroup v2 detected — enabling controllers"
    echo "+cpuset +cpu +memory +pids" > "$CGROUP_PATH/cgroup.subtree_control" 2>/dev/null || true
    if [ -f "$CGROUP_PATH/cpuset.cpus.effective" ]; then
        cat "$CGROUP_PATH/cpuset.cpus.effective" > "$CGROUP_PATH/cpuset.cpus" 2>/dev/null || true
    fi
    if [ -f "$CGROUP_PATH/cpuset.mems.effective" ]; then
        cat "$CGROUP_PATH/cpuset.mems.effective" > "$CGROUP_PATH/cpuset.mems" 2>/dev/null || true
    fi
    mkdir -p "$CGROUP_PATH/isolate"
    echo "+cpuset +cpu +memory +pids" > "$CGROUP_PATH/isolate/cgroup.subtree_control" 2>/dev/null || true
    if [ -f "$CGROUP_PATH/cpuset.cpus.effective" ]; then
        cat "$CGROUP_PATH/cpuset.cpus.effective" > "$CGROUP_PATH/isolate/cpuset.cpus" 2>/dev/null || true
    fi
    if [ -f "$CGROUP_PATH/cpuset.mems.effective" ]; then
        cat "$CGROUP_PATH/cpuset.mems.effective" > "$CGROUP_PATH/isolate/cpuset.mems" 2>/dev/null || true
    fi
    echo "[judge0-bootstrap] Controllers active: $(cat $CGROUP_PATH/cgroup.controllers)"
else
    echo "[judge0-bootstrap] cgroup v1 detected — skipping v2 bootstrap"
fi

# Step 2: Start cron daemon for Judge0 scheduled tasks.
sudo cron

# Step 3: Hand off to the CMD (server or workers).
exec "$@"
