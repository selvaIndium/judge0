# CGROUP_V2_CHANGES.md — Judge0 cgroup v2 Compatibility Fix

## Overview

Judge0 depends on **isolate** for sandboxing. The original setup assumed **cgroup v1** semantics: isolate expected sub-cgroups under `/sys/fs/cgroup/memory/...`, Docker mounted `/sys/fs/cgroup` read-only by default, and the worker silently crashed with a misleading `/box/script.py not found` error when isolate failed to initialize.

This changeset makes Judge0 work on **cgroup v2** environments (WSL 2, Ubuntu 22.04+, modern Cloud VMs) **without any GRUB kernel boot flags**, while remaining fully backward-compatible with cgroup v1 hosts.

---

## Files Changed

### `Dockerfile`

**Why:** The `judge0/compilers:1.4.0` base image ships isolate built from the `judge0/isolate` fork at commit `ad39cc4d` — a cgroup v1-era fork that does not support the `--cg` flag on unified cgroup v2 hierarchies. We add a new `RUN` layer that:

1. Installs `libcap-dev`, `libseccomp-dev`, `pkg-config` (build dependencies for isolate v2).
2. Clones `https://github.com/ioi/isolate` at tag **`v2.4`** (latest stable as of 2026-04).
3. Builds only the `isolate` and `isolate-check-environment` targets (skipping `isolate-cg-keeper` which requires systemd and is unused by Judge0).
4. Installs the new binary over the old one (same path: `/usr/local/bin/isolate`).
5. Runs `isolate --version` as a build-time smoke-test to confirm the binary works.

isolate v2.x introduces full cgroup v2 support: it detects the unified hierarchy automatically and uses the correct cgroup paths when `--cg` is passed.

---

### `docker-entrypoint.sh`

**Why:** On a cgroup v2 host, newly-created cgroup directories do not automatically inherit resource controllers — they must be explicitly delegated by writing to `cgroup.subtree_control`. Docker does not do this automatically. The entrypoint now:

1. Detects cgroup v2 at runtime by checking for `/sys/fs/cgroup/cgroup.controllers`.
2. Writes `+cpu +memory +pids` to the root `cgroup.subtree_control`.
3. Creates `/sys/fs/cgroup/isolate` and delegates the same controllers into it.
4. Falls back silently to cgroup v1 behaviour if the detection file is absent.
5. Then starts `cron` and `exec "$@"` as before.

This runs as `root` (before `USER judge0` takes effect at runtime) so it has the necessary write access to the cgroup filesystem.

---

### `scripts/entrypoint-cgroup-bootstrap.sh`

**Why:** Standalone version of the bootstrap logic, kept for reference and for operators who want to call it separately (e.g. from a Kubernetes init container). The `docker-entrypoint.sh` inlines this logic directly for simplicity.

---

### `docker-compose.yml`

**Why:** Two changes per isolate-running service (`server` and `worker`):

| Field | Value | Reason |
|---|---|---|
| `cap_add: [SYS_ADMIN]` | Added | isolate uses `clone()`, `unshare()`, and cgroup operations that require `SYS_ADMIN` |
| `security_opt: [seccomp:unconfined]` | Added | isolate's default seccomp profile blocks the specific `clone()` flags isolate uses |
| `cgroupns: host` | Added | Makes `/sys/fs/cgroup` inside the container refer to the real host hierarchy; required for isolate to walk the cgroup tree correctly |
| `/sys/fs/cgroup:/sys/fs/cgroup:rw` | Changed from `privileged: true` implicit | Allows isolate to create sub-cgroups at runtime |

`privileged: true` is removed and replaced with these targeted capabilities — this is more secure than a blanket privileged container while still granting what isolate needs.

---

### `docker-compose.dev.yml`

**Why:** Same changes as `docker-compose.yml` applied to the development `judge0` service. `privileged: true` removed; explicit capabilities and cgroup mount added.

---

### `app/jobs/isolate_job.rb`

**Why:** The original code ran `isolate --init` without checking its exit code:

```ruby
@workdir = `isolate #{cgroups} -b #{box_id} --init`.chomp
```

When isolate failed (e.g., because `/sys/fs/cgroup` was read-only or cgroup controllers weren't delegated), `@workdir` received isolate's error message as a string, and the worker tried to open files inside a nonexistent path. This produced the confusing `/box/script.py not found` error that obscured the real root cause.

Two guards are now added in `initialize_workdir`:

1. **Exit code check:** captures stdout+stderr from `--init`, checks `$?.success?`, and raises a `RuntimeError` with a human-readable message that names cgroup v2 setup explicitly.
2. **Boxdir existence check:** even if isolate exits 0 (possible with partial cgroup delegation), if the sandbox directory wasn't actually created, raises a `RuntimeError` with guidance to check `CGROUP_V2_CHANGES.md`.

These errors flow through the existing `rescue Exception => e` at the top of `perform`, which sets `submission.status = Status.boxerr` and persists the error message — so the API response will contain the diagnostic message directly.

---

## How to Run on cgroup v2 (WSL 2 / Modern Linux)

```bash
# 1. Build the image
docker build -t bitblazer/judge0-cgv2:latest .

# 2. Tag for the wsl2-ready alias
docker tag bitblazer/judge0-cgv2:latest bitblazer/judge0-cgv2:wsl2-ready

# 3. Start the stack
docker compose up -d

# 4. Verify cgroup v2 is active inside the worker
docker exec judge0-worker-1 cat /sys/fs/cgroup/cgroup.controllers
# Expected: cpu io memory pids (order may vary)

# 5. Verify cgroup mount is writable
docker exec judge0-worker-1 bash -c "touch /sys/fs/cgroup/probe && echo writable && rm /sys/fs/cgroup/probe"

# 6. Test isolate directly
docker exec judge0-worker-1 isolate --box-id=0 --cg --init
docker exec judge0-worker-1 ls /var/local/lib/isolate/0/box

# 7. Submit a test job
curl -X POST http://localhost:2358/submissions \
  -H 'Content-Type: application/json' \
  -d '{"source_code":"print(42)","language_id":71}' | jq .
```

---

## Compatibility

| Environment | Status |
|---|---|
| cgroup v2 (WSL 2, Ubuntu 22.04+, Debian 12+) | ✅ Fixed |
| cgroup v1 (older Ubuntu/Debian, GRUB flag) | ✅ Unchanged — bootstrap is a no-op |
| cgroup v2 hybrid mode | ✅ Bootstrap handles both |

**GRUB workaround (`systemd.unified_cgroup_hierarchy=0`) is NOT used or required.**

---

## Image Published

- `bitblazer/judge0-cgv2:latest`
- `bitblazer/judge0-cgv2:wsl2-ready`
