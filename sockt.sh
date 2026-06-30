#!/usr/bin/env bash
# sockt.sh - offline sockets and cap online CPUs on multi-socket Linux systems
# Usage: sockt.sh [-l <N>] [-a <N>] [-m <MAP>] [-s] [-S <ID>] [-r] [-n]
#   -l <N>    Limit socket 0 to <N> online CPUs
#   -a <N>    Limit every detected socket to <N> online CPUs
#   -m <MAP>  Limit specific sockets, e.g. 0:8,1:6
#   -s        Offline all CPUs on all sockets except socket 0
#   -S <ID>   Offline all CPUs on socket <ID>
#   -r        Restore all CPUs to online state
#   -n        Dry-run (print actions, do not write)

set -euo pipefail
shopt -s nullglob

usage() {
  cat <<'EOF'
Usage: sockt.sh [-l <N>] [-a <N>] [-m <MAP>] [-s] [-S <ID>] [-r] [-n] [-h]
  -l <N>    Limit socket 0 to <N> online CPUs
  -a <N>    Limit every detected socket to <N> online CPUs
  -m <MAP>  Limit specific sockets (format: socket:count[,socket:count...])
  -S <ID>   Offline all CPUs on socket <ID>
  -r        Restore all CPUs to online state
  -s        Offline all CPUs on all sockets except socket 0
  -n        Dry-run: print actions without writing sysfs state
  -h        Show this help
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

DRYRUN=0

cpu_dirs() { echo /sys/devices/system/cpu/{cpu[0-9]*,unplugged/cpu[0-9]*}; }
cid()   { basename "$1" | tr -dc 0-9; }
sid()   { cat "$1/topology/physical_package_id"; }
ofile() { echo "$1/online"; }
is_up() { [[ $(cid "$1") -eq 0 ]] && return 0; [[ -f $(ofile "$1") && $(<"$(ofile "$1")") -eq 1 ]]; }

set_state() {                      # $1 dir  $2 0|1
    local d tgt id
    d=$1
    tgt=$2
    id=$(cid "$1")
    [[ $id -eq 0 && $tgt -eq 0 ]] && return
    if [[ -f $(ofile "$d") ]]; then
      if (( DRYRUN == 1 )); then
        echo "DRY-RUN: cpu$id -> $tgt"
      else
        echo "$tgt" > "$(ofile "$d")"
      fi
    fi
}

dirs_by_socket() {
  local d sock=$1
  for d in $(cpu_dirs); do
    [[ -f $d/topology/physical_package_id && $(sid "$d") -eq $sock ]] && echo "$d"
  done | sort -V
}

socket_ids() {
  local d
  for d in $(cpu_dirs); do
    [[ -f $d/topology/physical_package_id ]] && sid "$d"
  done | sort -n -u
}

socket_exists() {
  local want=$1 s
  for s in $(socket_ids); do
    [[ $s -eq $want ]] && return 0
  done
  return 1
}

status() {
  mapfile -t sockets < <(socket_ids)
  for s in "${sockets[@]}"; do
    mapfile -t ds < <(dirs_by_socket "$s")
    up=() dn=(); for d in "${ds[@]}"; do is_up "$d" && up+=("$(cid "$d")") || dn+=("$(cid "$d")"); done
    printf "Socket %d : %d online, %d offline\n" "$s" "${#up[@]}" "${#dn[@]}"
    [[ ${up[*]} ]] && echo "  Online : ${up[*]}"
    [[ ${dn[*]} ]] && echo "  Offline: ${dn[*]}"
  done
}

socketoff() {               # offline all CPUs on a target socket
  local sock=${1:-1}
  socket_exists "$sock" || die "socket $sock was not detected"
  (( DRYRUN == 1 )) && echo "DRY-RUN: offline socket $sock"
  for d in $(dirs_by_socket "$sock"); do set_state "$d" 0; done
}

socketoff_nonzero() {       # offline all sockets except socket 0
  local s
  local -a nonzero=()
  for s in $(socket_ids); do
    (( s == 0 )) && continue
    nonzero+=("$s")
  done
  if (( DRYRUN == 1 )); then
    if (( ${#nonzero[@]} == 0 )); then
      echo "DRY-RUN: no non-zero sockets detected"
    else
      echo "DRY-RUN: offline all non-zero sockets: ${nonzero[*]}"
    fi
  fi
  for s in "${nonzero[@]}"; do
    socketoff "$s"
  done
}

limit_socket() {                # keep $2 online on socket $1
  local sock=$1 keep=$2
  [[ $keep =~ ^[0-9]+$ ]] || die "CPU limit must be a non-negative integer"
  socket_exists "$sock" || die "socket $sock was not detected"
  (( DRYRUN == 1 )) && echo "DRY-RUN: limit socket $sock to $keep online CPUs"
  mapfile -t s0 < <(dirs_by_socket "$sock")
  (( keep <= ${#s0[@]} )) || die "limit $keep exceeds socket$sock CPU count (${#s0[@]})"
  local kept=0
  for d in "${s0[@]}"; do
    if (( kept < keep )); then
      set_state "$d" 1
      (( kept++ ))
    else
      set_state "$d" 0
    fi
  done
}

limit_all() {                 # keep $1 online on every detected socket
  local keep=$1 s
  [[ $keep =~ ^[0-9]+$ ]] || die "-a requires a non-negative integer"
  (( DRYRUN == 1 )) && echo "DRY-RUN: limit every detected socket to $keep online CPUs"
  for s in $(socket_ids); do
    limit_socket "$s" "$keep"
  done
}

limit_map() {                 # keep N online per socket from a mapping spec
  local spec=$1 pair sock keep
  local -a pairs
  [[ -n $spec ]] || die "-m requires a non-empty mapping"
  (( DRYRUN == 1 )) && echo "DRY-RUN: apply per-socket limits: $spec"
  IFS=',' read -r -a pairs <<< "$spec"
  (( ${#pairs[@]} > 0 )) || die "-m requires at least one socket:count entry"

  for pair in "${pairs[@]}"; do
    [[ $pair =~ ^[0-9]+:[0-9]+$ ]] || die "invalid -m entry '$pair' (expected socket:count)"
    sock=${pair%%:*}
    keep=${pair##*:}
    limit_socket "$sock" "$keep"
  done
}

restore() { for d in $(cpu_dirs); do set_state "$d" 1; done; }

[[ $# -eq 0 ]] && { status; exit; }
declare -a OFF_SOCKETS=()
while getopts ":l:a:m:S:rsnh" o; do
  case $o in
    l) L=$OPTARG ;;
    a) A=$OPTARG ;;
    m) M=$OPTARG ;;
    S)
      [[ $OPTARG =~ ^[0-9]+$ ]] || die "-S requires a numeric socket ID"
      OFF_SOCKETS+=("$OPTARG")
      ;;
    r) R=1 ;;
    s) OFF_NONZERO=1 ;;
    n) DRYRUN=1 ;;
    h) usage; exit 0 ;;
    :) die "option -$OPTARG requires an argument" ;;
    *) usage; die "invalid option: -$OPTARG" ;;
  esac
done

if [[ ${R:-0} -eq 1 && ( -n ${L:-} || -n ${A:-} || -n ${M:-} || -n ${OFF_NONZERO:-} || ${#OFF_SOCKETS[@]} -gt 0 ) ]]; then
  die "-r cannot be combined with -l, -a, -m, -s, or -S"
fi

if [[ -n ${L:-} && -n ${A:-} ]]; then
  die "-l cannot be combined with -a"
fi

if [[ -n ${M:-} && ( -n ${L:-} || -n ${A:-} ) ]]; then
  die "-m cannot be combined with -l or -a"
fi

if (( DRYRUN == 0 )) && [[ ${R:-0} -ne 0 || -n ${L:-} || -n ${A:-} || -n ${M:-} || -n ${OFF_NONZERO:-} || ${#OFF_SOCKETS[@]} -gt 0 ]]; then
  (( EUID == 0 )) || die "run as root (try: sudo sockt.sh ...)"
fi

(( DRYRUN == 1 )) && echo "DRY-RUN mode: no CPU states will be changed"

[[ ${R:-0} -eq 1 ]] && restore
[[ ${L:-} ]] && limit_socket 0 "$L"
[[ ${A:-} ]] && limit_all "$A"
[[ ${M:-} ]] && limit_map "$M"
[[ ${OFF_NONZERO:-0} -eq 1 ]] && socketoff_nonzero
for s in "${OFF_SOCKETS[@]}"; do
  socketoff "$s"
done
status
