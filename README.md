# smtt, turbot and sockt
### Tools for manipulating cores on modern Linux systems
SMT & turbo on/off/toggle

sockt - offline target sockets and cap online CPUs per socket

### smtt/turbot Usage
```
smtt on|off|t
turbot on|off|t

Both also accept: get, h, -h, --help

't' toggles
When run with no options, both print current status.
```
### sockt Usage
```
   -l <N>    Limit socket 0 to <N> online CPUs
   -a <N>    Limit every detected socket to <N> online CPUs
   -m <MAP>  Limit specific sockets (socket:count[,socket:count...])
   -r        Restore all CPUs to online state
   -s        Offline all CPUs on all sockets except socket 0
   -S <ID>   Offline all CPUs on socket <ID>
   -n        Dry-run: print actions without writing changes
   -h        Show help

Mutating operations (-l/-a/-m/-r/-s/-S) require root privileges.
`-n` skips writes and allows safe preview without root.
`-r` cannot be combined with `-l`, `-a`, `-m`, `-s`, or `-S`.
`-l` cannot be combined with `-a`.
`-m` cannot be combined with `-l` or `-a`.
Status output shows all detected sockets.
When run with no options, prints current status
```

### sockt Examples
```
# Show current socket and CPU online/offline state
sockt.sh

# Preview all non-zero sockets being offlined (no writes)
sockt.sh -n -s

# Offline all sockets except socket 0
sudo sockt.sh -s

# Keep 8 online CPUs on every detected socket
sudo sockt.sh -a 8

# Apply per-socket limits (socket 0 -> 8, socket 1 -> 6)
sudo sockt.sh -m 0:8,1:6

# Preview per-socket mapping before applying
sockt.sh -n -m 0:8,1:6

# Offline only socket 2
sudo sockt.sh -S 2

# Restore all CPUs online
sudo sockt.sh -r
```

### setperf Usage
```
setperf.sh [-y] <perf|sav|pow|ond>

Modes:
   perf*       performance
   sav*|pow*   powersave
   ond*        ondemand (mapped to balanced when using powerprofilesctl)

Options:
   -y          Apply without confirmation prompt
   -h          Show help

Behavior:
   - Prefers powerprofilesctl when available.
   - Falls back to cpupower, then cpufreq sysfs.
   - Prints current power/frequency status after applying.
```

### setperf Examples
```
# Interactive: set performance mode
setperf.sh perf

# Non-interactive: set powersave mode
setperf.sh -y sav

# Set ondemand/balanced mode
setperf.sh ond
```

### pinfreq Usage
```
pinfreq.sh [-y] <frequency_mhz> [<upper_mhz>]

Options:
   -y          Apply without confirmation prompt
   -h          Show help

Notes:
   - Frequencies are integers in MHz.
   - One value pins min=max to that value.
   - Two values set min/max range.
   - Requires cpupower.
```

### pinfreq Examples
```
# Pin all cores to exactly 2400 MHz (interactive)
pinfreq.sh 2400

# Set range 1800-3200 MHz (no prompt)
pinfreq.sh -y 1800 3200
```

### ppws Usage
```
sudo ppws.sh [--lock] [-p <package_idx>] [<PL1_W> [PL2_W]]

No wattage args:
   Show current PL1/PL2 and firmware ceilings.

One wattage arg:
   Set PL1 and PL2 to the same value.

Two wattage args:
   Set PL1 and PL2 independently.

Options:
   -p <idx>    Restrict action to one package/socket index
   --lock      Write PL1+PL2 and set MSR lock bit (until reboot)

Requirements:
   - Must run as root.
   - Optional tools for advanced paths: msr-tools, devmem/devmem2, pciutils.
```

### ppws Examples
```
# Show current package power limits on all packages
sudo ppws.sh

# Set PL1=PL2=125 W on all packages
sudo ppws.sh 125

# Set PL1=125 W and PL2=190 W on package 0 only
sudo ppws.sh -p 0 125 190

# Set and lock limits until next reboot
sudo ppws.sh --lock 125 190
```

### Install
```
sudo ./inst.sh
Installs all above to /usr/local/bin
```

### Quick Self-Test
```
chmod +x ./selftest.sh
./selftest.sh

# Verbose mode (shows command output for passing tests)
./selftest.sh -v
```
