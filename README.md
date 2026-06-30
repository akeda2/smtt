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
