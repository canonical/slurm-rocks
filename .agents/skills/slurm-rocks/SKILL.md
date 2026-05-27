---
name: slurm-rocks
description: Use when editing or creating files under the rocks/ directory, including rockcraft.yaml files, scripts/, or any Pebble service configuration for Slurm rocks (slurmctld, slurmd, slurmdbd, slurmrestd, sackd, login). Also use when discussing rock packaging, Pebble layers, or entrypoint scripts.
---

# Slurm Rocks Development

This skill covers development and testing of OCI container images (rocks) for
Slurm workload manager components, built with Rockcraft and managed by Pebble.

## Project layout

```
rocks/
  slurmctld/    - Slurm central management daemon
  slurmd/       - Slurm compute node daemon
  slurmdbd/     - Slurm database daemon
  slurmrestd/   - Slurm REST API daemon
  sackd/        - Slurm auth and credential kiosk daemon
  login/        - Slurm login node (extends sackd with sshd/sssd)
```

Each rock directory contains:
- `rockcraft.yaml` - Rock definition (base, packages, services, parts)
- `scripts/` - Entrypoint and helper scripts included in the rock

## Testing requirements

After ANY change to files under `rocks/`, you MUST verify the rock builds
successfully before considering the task complete.

### Commands

| Scope | Command |
|-------|---------|
| Single rock | `just pack <rock-name>` (e.g., `just pack slurmd`) |
| All rocks | `just pack` |
| Lint YAML | `just lint` |
| Clean builds | `just clean` |

### Workflow

1. Make changes to rock files
2. Run `just lint` to catch YAML syntax issues
3. Run `just pack <rock-name>` for the specific rock(s) you changed
4. If the pack fails, fix the issue and re-run
5. Built rocks are output to `_build/`

### Common build failures

- **Missing packages**: A package listed in `overlay-packages` doesn't exist
  in the configured APT repository. Check the PPA at
  `ppa:ubuntu-hpc/slurm-wlm-25.11` for available package names.
- **Script not found**: The `organize` mapping in a `dump` part doesn't match
  the actual source file path. Verify paths in `source` and `organize`.
- **Permission errors in overlay-script**: Commands run in a chroot; ensure
  paths reference `$CRAFT_OVERLAY` prefix correctly.
- **Service command not found**: The `command` in the Pebble service definition
  must reference a path that exists in the final rock filesystem
  (typically `/usr/sbin/` for scripts organized there via parts).

## Upstream reference

These rocks aim for compatibility with the
[Slinky slurm-operator](https://github.com/SlinkyProject/slurm-operator)
Helm charts. The operator expects specific container entrypoint behavior,
signal handling, and the ability to pass arguments via the container command.
The `entrypoint-service` field in `rockcraft.yaml` enables this.

## Style conventions

- Scripts use `#!/usr/bin/env bash` shebang
- Scripts use `set -euo pipefail` (or `set -uo pipefail` if exit-on-error
  would conflict with signal traps)
- License header: Apache-2.0 (Canonical) for new files
- Slurm UID/GID: 401 (matching Slinky's expectation, differs from Debian's
  default of 64030)
- Packages include `-dbgsym` variants for debugging
