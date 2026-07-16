#!/usr/bin/env bash
# ppws.sh – show or set Intel RAPL package power limits (Sandy‑Bridge → Meteor‑Lake)
#
# Usage
#   sudo ./ppws.sh [--lock] [-p <package_idx>] [<PL1_W> [PL2_W]]
#
#   • No wattage             → show current PL1/PL2 and firmware ceilings
#   • One wattage            → set PL1 = PL2 = that value
#   • Two wattages           → set PL1 and PL2 individually
#
# Options
#   -p <idx>    Restrict action to one package (socket). Default = all.
#   --lock      Write both limits + the MSR lock bit (bit 63) in one atomic
#               wrmsr.  A locked MSR cannot be overridden by firmware/ME/BMC
#               until the next reboot.  Use this when firmware keeps resetting
#               your limits.  Requires msr-tools (apt install msr-tools).
#
# Notes
#   • Must run as root.
#   • Never writes above the firmware‑reported ceiling.
#   • Without --lock, on post‑Skylake CPUs the MCHBAR shadow register
#     (offset 0x59A0) is synced when rdmsr + devmem/devmem2 + setpci are
#     available, which helps against some firmware claw‑back scenarios.
#
# Optional dependencies:
#   msr‑tools (rdmsr, wrmsr), devmem or devmem2, pciutils (setpci, lspci)

set -euo pipefail
shopt -s nullglob

# ─── root check ───────────────────────────────────────────────────────
(( EUID == 0 )) || { echo "Must run as root." >&2; exit 1; }

# ─── tool detection ───────────────────────────────────────────────────
DEVMEM=$(command -v devmem 2>/dev/null || command -v devmem2 2>/dev/null || echo "")
# HAS_MSR_TOOLS: rdmsr+wrmsr available (needed for MSR fallback write and MCHBAR)
HAS_MSR_TOOLS=false
if command -v rdmsr &>/dev/null && command -v wrmsr &>/dev/null; then
  HAS_MSR_TOOLS=true
  modprobe msr 2>/dev/null || true
fi
# HAS_MCHBAR: full MCHBAR shadow sync (also needs devmem and setpci)
HAS_MCHBAR=false
if $HAS_MSR_TOOLS && [[ -n $DEVMEM ]] && command -v setpci &>/dev/null; then
  HAS_MCHBAR=true
fi

# ─── CLI parsing ───────────────────────────────────────────────────────
LOCK_MSR=false
PKG_FILTER=""

# Pre-scan for long flags; leave positional args and -p in place.
_args=()
for _a in "$@"; do
  case $_a in
    --lock) LOCK_MSR=true ;;
    *)      _args+=("$_a") ;;
  esac
done
set -- "${_args[@]+"${_args[@]}"}"  # safe even when _args is empty
unset _args _a

if [[ ${1:-} == "-p" ]]; then
  [[ $# -ge 2 ]] || { echo "Need -p <idx>." >&2; exit 1; }
  PKG_FILTER="$2"; shift 2
fi

MODE="show"
PL1_W="" PL2_W=""
if [[ $# -ge 1 ]]; then
  PL1_W=$1; PL2_W=${2:-$PL1_W}; MODE="set"
  [[ $# -le 2 ]] || { echo "Too many wattage arguments." >&2; exit 1; }
  [[ $PL1_W =~ ^[1-9][0-9]*$ ]] || { echo "PL1 must be a positive integer (watts)." >&2; exit 1; }
  [[ $PL2_W =~ ^[1-9][0-9]*$ ]] || { echo "PL2 must be a positive integer (watts)." >&2; exit 1; }
fi

if $LOCK_MSR && [[ $MODE != "set" ]]; then
  echo "--lock only makes sense with wattage arguments." >&2; exit 1
fi

# ─── helper functions ──────────────────────────────────────────────────
to_uw()   { echo $(( $1 * 1000000 )); }                          # W  → µW (integer)
uw_to_w() { awk "BEGIN{printf \"%.1f\", $1/1000000}"; }          # µW → W  (1 decimal)
us_to_ms(){ echo $(( $1 / 1000 )); }                             # µs → ms

limit_file()      { echo "$1/constraint_${2}_power_limit_uw"; }
window_file()     { echo "$1/constraint_${2}_time_window_us"; }
window_max_file() { echo "$1/constraint_${2}_max_time_window_us"; }

choose_longest_window() {
  local base=$1 idx=$2
  if [[ -r $(window_max_file "$base" "$idx") ]]; then
    cat "$(window_max_file "$base" "$idx")"
  else
    cat "$(window_file     "$base" "$idx")"
  fi
}

read_limit() {                 # stdout: "<W_str> <ms>"
  local base=$1 idx=$2
  local pl tw
  pl=$(< "$(limit_file  "$base" "$idx")")
  tw=$(< "$(window_file "$base" "$idx")")
  echo "$(uw_to_w "$pl") $(us_to_ms "$tw")"
}

read_max_power() {             # $1 = base path, $2 = constraint idx → µW or ""
  local f="$1/constraint_${2}_max_power_uw"
  if [[ -r $f ]]; then
    local v; v=$(< "$f")
    (( v == 0 )) && echo "" || echo "$v"   # 0 → treat as unknown/unlimited
  else
    echo ""
  fi
}

# ─── power limit write (sysfs with MSR fallback) ─────────────────────
# Try the sysfs powercap file first.  If the kernel rejects the value
# (ENODATA — often a locked or range-constrained MSR), fall back to a
# direct read-modify-write of MSR 0x610 via wrmsr, which also clears
# the firmware lock bit (bit 63) so the value sticks.
#   $1=sysfs_base  $2=constraint_idx (0=PL1, 1=PL2)  $3=watts  $4=pkg_idx
write_power_limit() {
  local base=$1 idx=$2 watts=$3 pkg_idx=$4
  local pf; pf=$(limit_file "$base" "$idx")
  local uw; uw=$(to_uw "$watts")

  # Primary: sysfs
  if echo "$uw" > "$pf" 2>/dev/null; then
    return 0
  fi

  # Fallback: direct MSR 0x610 write
  printf '  (sysfs rejected; trying direct MSR write)\n' >&2
  if ! $HAS_MSR_TOOLS; then
    printf '  !! MSR fallback unavailable — install msr-tools: apt install msr-tools\n' >&2
    return 1
  fi

  local cpu; cpu=$(pkg_to_cpu "$pkg_idx")

  # Power unit exponent from MSR 0x606 bits[3:0]: unit = 2^(-exp) W
  # (typical: exp=3 → 0.125 W/LSB, so raw = watts * 8)
  local unit_raw shift
  unit_raw=$(rdmsr -p "$cpu" -0 0x606 2>/dev/null) || {
    printf '  !! rdmsr 0x606 failed\n' >&2; return 1
  }
  shift=$(( 16#${unit_raw:14:2} & 0xF ))

  local raw_pw=$(( watts * (1 << shift) ))
  (( raw_pw > 0x7FFF )) && raw_pw=0x7FFF

  # Read current MSR 0x610 and modify only the target constraint's bits.
  # MSR layout (lo = bits 31:0, hi = bits 63:32):
  #   PL1: lo[14:0]=power, lo[15]=enable, lo[16]=clamp, lo[23:17]=TW
  #   PL2: hi[14:0]=power, hi[15]=enable, hi[16]=clamp, hi[23:17]=TW
  #   Lock: hi[31] — clear this so the write sticks
  local cur_raw cur_hi cur_lo new_hi new_lo
  cur_raw=$(rdmsr -p "$cpu" -0 0x610 2>/dev/null) || {
    printf '  !! rdmsr 0x610 failed\n' >&2; return 1
  }
  cur_hi=$(( 16#${cur_raw:0:8} ))
  cur_lo=$(( 16#${cur_raw:8:8} ))

  if (( idx == 0 )); then
    new_lo=$(( (cur_lo & 0xFFFF0000) | (raw_pw & 0x7FFF) | 0x8000 ))  # set PL1+enable, preserve clamp/TW
    new_hi=$(( cur_hi & 0x7FFFFFFF ))                                   # clear lock bit only
  else
    new_lo=$cur_lo
    new_hi=$(( (cur_hi & 0x7FFF0000) | (raw_pw & 0x7FFF) | 0x8000 ))  # set PL2+enable, clear lock
  fi

  local new_val
  new_val=$(printf '0x%08x%08x' "$new_hi" "$new_lo")
  if wrmsr -p "$cpu" 0x610 "$new_val" 2>/dev/null; then
    printf '  ↳ Written to MSR 0x610 directly (cpu%s, lock cleared)\n' "$cpu"
    return 0
  else
    printf '  !! wrmsr failed — limit may be locked at platform level\n' >&2
    return 1
  fi
}

# Write PL1+PL2 to MSR 0x610 in one atomic wrmsr with the lock bit (bit 63) set.
# A locked MSR is read-only until next boot; firmware/ME/BMC cannot override it.
#   $1 = package index   $2 = PL1 watts   $3 = PL2 watts
write_rapl_msr_full() {
  local pkg_idx=$1 pl1_w=$2 pl2_w=$3

  if ! $HAS_MSR_TOOLS; then
    printf '  !! --lock requires msr-tools: apt install msr-tools\n' >&2
    return 1
  fi

  local cpu; cpu=$(pkg_to_cpu "$pkg_idx")

  # Power unit exponent from MSR 0x606 bits[3:0]: unit = 2^(-exp) W
  local unit_raw shift
  unit_raw=$(rdmsr -p "$cpu" -0 0x606 2>/dev/null) || {
    printf '  !! rdmsr 0x606 failed\n' >&2; return 1
  }
  shift=$(( 16#${unit_raw:14:2} & 0xF ))

  local raw_pl1=$(( pl1_w * (1 << shift) ))
  (( raw_pl1 > 0x7FFF )) && raw_pl1=0x7FFF
  local raw_pl2=$(( pl2_w * (1 << shift) ))
  (( raw_pl2 > 0x7FFF )) && raw_pl2=0x7FFF

  # Read current MSR to preserve time-window and clamp bits.
  # Layout: lo = MSR[31:0], hi = MSR[63:32]
  #   PL1: lo[14:0]=power, lo[15]=enable, lo[16]=clamp, lo[23:17]=TW
  #   PL2: hi[14:0]=power, hi[15]=enable, hi[16]=clamp, hi[23:17]=TW
  #   Lock: hi[31] (MSR bit 63)
  local cur_raw cur_hi cur_lo
  cur_raw=$(rdmsr -p "$cpu" -0 0x610 2>/dev/null) || {
    printf '  !! rdmsr 0x610 failed\n' >&2; return 1
  }
  cur_hi=$(( 16#${cur_raw:0:8} ))
  cur_lo=$(( 16#${cur_raw:8:8} ))

  local new_lo new_hi
  new_lo=$(( (cur_lo & 0xFFFF0000) | (raw_pl1 & 0x7FFF) | 0x8000 ))           # PL1+enable, preserve clamp/TW
  new_hi=$(( (cur_hi & 0x7FFF0000) | (raw_pl2 & 0x7FFF) | 0x8000 | 0x80000000 )) # PL2+enable+lock, preserve clamp/TW

  local new_val
  new_val=$(printf '0x%08x%08x' "$new_hi" "$new_lo")
  if wrmsr -p "$cpu" 0x610 "$new_val" 2>/dev/null; then
    printf '  ↳ MSR 0x610 written+locked (cpu%s) — limits fixed until next reboot\n' "$cpu"
    return 0
  else
    printf '  !! wrmsr failed\n' >&2
    return 1
  fi
}

# ─── MCHBAR sync ──────────────────────────────────────────────────────
# Return the first CPU number that belongs to a given package index.
pkg_to_cpu() {
  local pkg=$1
  for f in /sys/devices/system/cpu/cpu[0-9]*/topology/physical_package_id; do
    [[ -r $f ]] || continue
    [[ $(< "$f") == "$pkg" ]] || continue
    local cpu="${f%/topology/physical_package_id}"
    printf '%s\n' "${cpu##*/cpu}"
    return
  done
  echo "0"   # fallback
}

# Read MSR 0x610 for the given package and write its lo/hi 32-bit halves
# to the MCHBAR Package Power Limit shadow at MCHBAR_base+0x59A0.
# This prevents firmware ACPI methods from clawing the limit back.
#   $1 = package index   $2 = PCI BDF of matching host bridge
sync_mchbar() {
  local pkg_idx=$1 hb=$2
  local cpu; cpu=$(pkg_to_cpu "$pkg_idx")

  # rdmsr -0 zero-pads to full width; result is 16 lowercase hex chars, no 0x.
  local msr_val
  msr_val=$(rdmsr -p "$cpu" -0 0x610 2>/dev/null) || {
    echo "  (rdmsr failed on cpu${cpu}; MCHBAR sync skipped)" >&2; return
  }
  # Defensive: pad to 16 chars in case of unexpectedly short output.
  msr_val=$(printf '%016s' "$msr_val" | tr ' ' '0')

  # Split into lo (bits 31-0) and hi (bits 63-32).
  local lo hi
  lo=$(( 16#${msr_val:8:8} ))
  hi=$(( 16#${msr_val:0:8} ))

  # MCHBAR base: PCI config register 0x48, bits[31:14] = base, bit[0] = enable.
  local base_raw
  base_raw=$(setpci -s "$hb" 0x48.l 2>/dev/null) || {
    echo "  (setpci failed for $hb; MCHBAR sync skipped)" >&2; return
  }
  local mchbar_base pl_addr
  mchbar_base=$(( 16#${base_raw} & 0xffffc000 ))
  pl_addr=$(( mchbar_base + 0x59A0 ))

  "$DEVMEM" "$pl_addr"           32 "$lo" >/dev/null
  "$DEVMEM" $(( pl_addr + 4 ))   32 "$hi" >/dev/null
  printf '  ↳ MCHBAR synced (cpu%s, hb %s, addr 0x%X)\n' "$cpu" "$hb" "$pl_addr"
}

# ─── build host-bridge list (index ≈ socket/package order) ────────────
HOST_BRIDGES=()
if command -v lspci &>/dev/null; then
  mapfile -t HOST_BRIDGES < <(lspci -Dnn 2>/dev/null | awk '/Class 0600.*8086/ {print $1}')
fi

# ─── MAIN loop over packages ───────────────────────────────────────────
found=false
for BASE in /sys/class/powercap/intel-rapl:[0-9]*; do
  [[ "$BASE" == *:*:* ]] && continue   # skip :0:0 core/uncore sub-zones
  pkg_idx=${BASE##*:}
  [[ -n $PKG_FILTER && $pkg_idx != "$PKG_FILTER" ]] && continue
  [[ -d $BASE ]] || continue
  found=true

  echo "=== Package $pkg_idx ($BASE) ==="

  if [[ $MODE == "show" ]]; then
    read -r pl1 tw1 <<<"$(read_limit "$BASE" 0)"
    MAX1=$(read_max_power "$BASE" 0)
    max1_str=${MAX1:+"  [max $(uw_to_w "$MAX1") W]"}
    echo "  PL1: ${pl1} W  for ${tw1} ms${max1_str:-}"

    if [[ -e $(limit_file "$BASE" 1) ]]; then
      read -r pl2 tw2 <<<"$(read_limit "$BASE" 1)"
      MAX2=$(read_max_power "$BASE" 1)
      max2_str=${MAX2:+"  [max $(uw_to_w "$MAX2") W]"}
      echo "  PL2: ${pl2} W  for ${tw2} ms${max2_str:-}"
    else
      echo "  (Package exposes only one constraint)"
    fi
    continue
  fi

  # ── SET mode: compute effective limits (per-socket copies) ──────────
  cur_pl1_w=$PL1_W
  cur_pl2_w=$PL2_W
  has_pl2=false
  [[ -e $(limit_file "$BASE" 1) ]] && has_pl2=true

  MAX1=$(read_max_power "$BASE" 0)
  if [[ -n $MAX1 && $(to_uw "$cur_pl1_w") -gt $MAX1 ]]; then
    echo "  !! PL1=${cur_pl1_w} W exceeds firmware ceiling $(uw_to_w "$MAX1") W — skipping package"
    continue
  fi

  if $has_pl2; then
    MAX2=$(read_max_power "$BASE" 1)
    if [[ -n $MAX2 && $(to_uw "$cur_pl2_w") -gt $MAX2 ]]; then
      echo "  !! PL2=${cur_pl2_w} W exceeds firmware ceiling $(uw_to_w "$MAX2") W — skipping PL2"
      cur_pl2_w=""
    fi
  fi

  # ── SET mode: write ────────────────────────────────────────────────
  if $LOCK_MSR; then
    # Atomic locked write: PL1 + PL2 + MSR lock bit in one wrmsr.
    # Firmware/ME/BMC cannot override the limits until next reboot.
    effective_pl2=${cur_pl2_w:-$cur_pl1_w}
    echo "  -> PL1 ${cur_pl1_w} W  PL2 ${effective_pl2} W  [--lock]"
    write_rapl_msr_full "$pkg_idx" "$cur_pl1_w" "$effective_pl2"
  else
    TW1=$(choose_longest_window "$BASE" 0)
    echo "  -> PL1 ${cur_pl1_w} W / $(us_to_ms "$TW1") ms"
    write_power_limit "$BASE" 0 "$cur_pl1_w" "$pkg_idx"
    echo "$TW1" > "$(window_file "$BASE" 0)" 2>/dev/null || true

    if $has_pl2 && [[ -n $cur_pl2_w ]]; then
      TW2=$(choose_longest_window "$BASE" 1)
      echo "  -> PL2 ${cur_pl2_w} W / $(us_to_ms "$TW2") ms"
      write_power_limit "$BASE" 1 "$cur_pl2_w" "$pkg_idx"
      echo "$TW2" > "$(window_file "$BASE" 1)" 2>/dev/null || true
    fi

    # ── sync MCHBAR shadow register (post-Skylake) ──────────────────
    if $HAS_MCHBAR; then
      hb="${HOST_BRIDGES[$pkg_idx]:-${HOST_BRIDGES[0]:-}}"
      if [[ -n $hb ]]; then
        sync_mchbar "$pkg_idx" "$hb"
      else
        echo "  (no host bridge found; MCHBAR sync skipped)"
      fi
    fi
  fi
done

if ! $found; then
  echo "No intel_rapl packages found — is the intel_rapl driver loaded?" >&2
  exit 1
fi
