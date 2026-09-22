# Demo Scripts Repository

This is a built-in demo repository showing how to structure custom ulh scripts.
ulh puts it into `apps/cli/data/repos/demo-scripts/` on the first start.

## Scripts Included

### 1. Hello World (`hello`)
A simple greeting script that asks for your name.

**Actions:**
- `run` - Say hello to someone

**Parameters:**
- `NAME` - Your name (default: "World")

### 2. System Info (`system-info`)
Display system information and disk usage.

**Actions:**
- `show` - Display system details (hostname, OS, kernel, uptime)
- `disk` - Show disk usage (df -h)

### 3. File Backup (`file-backup`)
Simple file backup utility.

**Actions:**
- `backup` - Backup a file to a destination

**Parameters:**
- `SOURCE_FILE` - File to backup (default: /etc/hosts)
- `BACKUP_DIR` - Where to save the backup (default: /tmp)

## Structure

```
demo-scripts/
├── README.md              # This file
├── config.yaml            # Script definitions
└── scripts/
    ├── hello.sh           # Hello world script (uses ulh's helpers)
    ├── system-info.sh     # System info script
    └── file-backup.sh     # File backup script
```

## How to Use

1. Start ulh: `bash ~/ulh/apps/cli/ulh.sh`
2. Select: `2) Demo Scripts`
3. Choose a script and action
4. Fill in any prompts
5. Confirm execution

## Testing

This demo repository is configured in `apps/cli/config/repo.yaml`. It ships
disabled; to turn it on, remove the `#` in front of `enabled:`:

```yaml
demo-scripts:
  name: "Demo Scripts"
  url: ""
  path: "demo-scripts"
  auth_method: "none"
  enabled:
```

Flags are **presence-based**: `enabled:` switches the repo on just by being
there - its value is ignored. `auto_update: false` would therefore switch
auto-update *on*. To keep something off, leave the line out.

It's a local repository (no git needed) for easy testing of the custom repository system.

## Next Steps

To create your own custom repository:

1. Create a new directory: `apps/cli/data/repos/my-scripts/`
2. Create `config.yaml` with script definitions (scripts are referenced by `path`)
3. Create `scripts/` directory with your scripts - `hello.sh` is a good start
4. Add entry to `apps/cli/config/repo.yaml`:
   ```yaml
   my-scripts:
     name: "My Scripts"
     path: "my-scripts"
     enabled:
   ```
5. Run ulh and test!

## Tips

- Scripts don't need `chmod +x` - ulh runs them with `bash`
- ulh's helpers (`parse_parameters`, `log_info`, `detect_os`, ...):
  `source "$(dirname "$0")/../../../lib/bootstrap.sh"` as in `hello.sh`
- Or parse parameters yourself from the comma-separated string: `ACTION="${1%%,*}"`
- Use `exit 0` for success, `exit 1` for failure
- Add descriptions and prompts in `config.yaml` for user-friendly menus
