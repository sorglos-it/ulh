# Demo Scripts Repository

This is a built-in demo repository showing how to structure custom ulh scripts.

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
    ├── hello.sh           # Hello world script
    ├── system-info.sh     # System info script
    └── file-backup.sh     # File backup script
```

## How to Use

1. Start ulh: `bash ulh.sh`
2. Select: `2) Custom: Demo Scripts`
3. Choose a script and action
4. Fill in any prompts
5. Confirm execution

## Testing

This demo repository is configured in `custom/repo.yaml`. It ships disabled;
to turn it on, remove the `#` in front of `enabled:`:

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

1. Create a new directory: `custom/my-scripts/`
2. Create `config.yaml` with script definitions (scripts are referenced by `path`)
3. Create `scripts/` directory with your scripts
4. Add entry to `repo.yaml`:
   ```yaml
   my-scripts:
     name: "My Scripts"
     path: "my-scripts"
     enabled:
   ```
5. Run ulh and test!

## Tips

- Scripts don't need `chmod +x` - ulh handles permissions
- Parse parameters from the comma-separated string: `ACTION="${1%%,*}"`
- Use `exit 0` for success, `exit 1` for failure
- Add descriptions and prompts in `config.yaml` for user-friendly menus
