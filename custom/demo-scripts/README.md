# Demo Scripts Repository

This is a built-in demo repository showing how to structure custom LIAUH scripts.

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
├── custom.yaml            # Script definitions
└── scripts/
    ├── hello.sh           # Hello world script
    ├── system-info.sh     # System info script
    └── file-backup.sh     # File backup script
```

## How to Use

1. Start LIAUH: `bash liauh.sh`
2. Select: `2) Custom: Demo Scripts`
3. Choose a script and action
4. Fill in any prompts
5. Confirm execution

## Testing

This demo repository is configured in `custom/repo.yaml` with:

```yaml
demo-scripts:
  name: "Demo Scripts"
  path: "demo-scripts"
  enabled: true
  auto_update: false
```

It's a local repository (no git needed) for easy testing of the custom repository system.

## Next Steps

To create your own custom repository:

1. Create a new directory: `custom/my-scripts/`
2. Create `custom.yaml` with script definitions
3. Create `scripts/` directory with your scripts
4. Add entry to `repo.yaml`:
   ```yaml
   my-scripts:
     name: "My Scripts"
     path: "my-scripts"
     enabled: true
     auto_update: false
   ```
5. Run LIAUH and test!

## Tips

- Scripts don't need `chmod +x` - LIAUH handles permissions
- Parse parameters from the comma-separated string: `ACTION="${1%%,*}"`
- Use `exit 0` for success, `exit 1` for failure
- Add descriptions and prompts in `custom.yaml` for user-friendly menus
