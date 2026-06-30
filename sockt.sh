#!/usr/bin/env bash
# sockt.sh - offline socket1 and limit socket0 on a multi-socket Linux system
# Usage: sockt.sh [-l <N>] [-r] [-s]
#   -l <N>    Limit socket 0 to <N> online CPUs
#   -r        Restore all CPUs to online state
#   -s        Offline all CPUs on socket 1

set -euo pipefail
shopt -s nullglob

usage() {
  cat <<'EOF'
Usage: sockt.sh [-l <N>] [-r] [-s] [-h]
  -l <N>    Limit socket 0 to <N> online CPUs
  -r        Restore all CPUs to online state
  -s        Offline all CPUs on socket 1
  -h        Show this help
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

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
      echo "$tgt" > "$(ofile "$d")"
    fi
}

dirs_by_socket() {
  local d sock=$1
  for d in $(cpu_dirs); do
    [[ -f $d/topology/physical_package_id && $(sid "$d") -eq $sock ]] && echo "$d"
  done | sort -V
}

status() {
  for s in 0 1; do
    mapfile -t ds < <(dirs_by_socket "$s")
    up=() dn=(); for d in "${ds[@]}"; do is_up "$d" && up+=("$(cid "$d")") || dn+=("$(cid "$d")"); done
    printf "Socket %d : %d online, %d offline\n" "$s" "${#up[@]}" "${#dn[@]}"
    [[ ${up[*]} ]] && echo "  Online : ${up[*]}"
    [[ ${dn[*]} ]] && echo "  Offline: ${dn[*]}"
  done
}

socketoff() {               # offline all CPUs on socket 1
  for d in $(dirs_by_socket 1); do set_state "$d" 0; done
}

limit() {                       # keep $1 online on socket 0
  local keep=$1
  [[ $keep =~ ^[0-9]+$ ]] || die "-l requires a non-negative integer"
  # try off-lining socket 1 : MOVED to socketoff()
  #for d in $(dirs_by_socket 1); do set_state "$d" 0; done
  # trim socket 0
  mapfile -t s0 < <(dirs_by_socket 0)
  (( keep <= ${#s0[@]} )) || die "-l value $keep exceeds socket0 CPU count (${#s0[@]})"
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

restore() { for d in $(cpu_dirs); do set_state "$d" 1; done; }

[[ $# -eq 0 ]] && { status; exit; }
while getopts ":l:rsh" o; do
  case $o in
    l) L=$OPTARG ;;
    r) R=1 ;;
    s) R=2 ;;
    h) usage; exit 0 ;;
    :) die "option -$OPTARG requires an argument" ;;
    *) usage; die "invalid option: -$OPTARG" ;;
  esac
done

if [[ ${R:-0} -ne 0 || -n ${L:-} ]]; then
  (( EUID == 0 )) || die "run as root (try: sudo sockt.sh ...)"
fi

[[ ${R:-0} -eq 1 ]] && restore
[[ ${R:-0} -eq 2 ]] && socketoff
[[ ${L:-} ]] && limit "$L"
status
