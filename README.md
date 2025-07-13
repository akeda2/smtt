# smtt, turbot and sockt
### Tools for manipulating cores on modern Linux systems
SMT & turbo on/off/toggle

sockt - turn socket1 off and limit socket0

### smtt/turbot Usage
```
smtt on|off|t
turbot on|off|t

't' toggles
When run with no options, both print current status.
```
### sockt Usage
```
   -l <N>    Limit socket 0 to <N> online CPUs
   -r        Restore all CPUs to online state
   -s        Offline all CPUs on socket 1
When run with no options, prints current status
```
### Install
```
./inst.sh
Installs all above to /usr/local/bin
```
