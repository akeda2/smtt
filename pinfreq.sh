#!/usr/bin/env bash
# Pin all cores to a specific frequency
# Usage: ./pinfreq.sh [-y] <frequency-mhz> [<upper-mhz>]

usage() {
    echo "Usage: $0 [-y] <frequency in MHz>|<lower MHz> [<upper MHz>]"
    echo "  -y  Apply without confirmation prompt"
}

mhz_to_khz() {
    echo $(( $1 * 1000 ))
}

print_sysfs_status() {
    local policy
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [[ -d "$policy" ]] || continue
        local name cur min max gov
        name="${policy##*/}"
        cur="$(cat "$policy/scaling_cur_freq" 2>/dev/null || echo "?")"
        min="$(cat "$policy/scaling_min_freq" 2>/dev/null || echo "?")"
        max="$(cat "$policy/scaling_max_freq" 2>/dev/null || echo "?")"
        gov="$(cat "$policy/scaling_governor" 2>/dev/null || echo "?")"
        echo "${name}: cur=${cur}kHz min=${min}kHz max=${max}kHz governor=${gov}"
    done
}

warn_if_outside_cpuinfo_range() {
    local lower_khz="$1"
    local upper_khz="$2"
    local policy

    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [[ -d "$policy" ]] || continue
        local hw_min hw_max
        hw_min="$(cat "$policy/cpuinfo_min_freq" 2>/dev/null || echo "")"
        hw_max="$(cat "$policy/cpuinfo_max_freq" 2>/dev/null || echo "")"
        if [[ -z "$hw_min" || -z "$hw_max" ]]; then
            continue
        fi

        if (( lower_khz < hw_min || upper_khz > hw_max )); then
            echo "Warning: Requested range ${lower_khz}-${upper_khz} kHz is outside ${policy##*/} cpuinfo range ${hw_min}-${hw_max} kHz; trying anyway."
        fi
    done
}

print_effective_policy_ranges() {
    local policy
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [[ -d "$policy" ]] || continue
        local name min max
        name="${policy##*/}"
        min="$(cat "$policy/scaling_min_freq" 2>/dev/null || echo "?")"
        max="$(cat "$policy/scaling_max_freq" 2>/dev/null || echo "?")"
        echo "${name}: applied min=${min}kHz max=${max}kHz"
    done
}

apply_with_sysfs() {
    local lower_khz="$1"
    local upper_khz="$2"
    local policy
    local wrote=0

    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [[ -d "$policy" ]] || continue
        wrote=1

        local cur_min cur_max
        cur_min="$(cat "$policy/scaling_min_freq")"
        cur_max="$(cat "$policy/scaling_max_freq")"

        # Keep transitions valid by choosing write order from current bounds.
        if (( upper_khz < cur_min )); then
            echo "$lower_khz" | sudo tee "$policy/scaling_min_freq" >/dev/null
            echo "$upper_khz" | sudo tee "$policy/scaling_max_freq" >/dev/null
        elif (( lower_khz > cur_max )); then
            echo "$upper_khz" | sudo tee "$policy/scaling_max_freq" >/dev/null
            echo "$lower_khz" | sudo tee "$policy/scaling_min_freq" >/dev/null
        else
            echo "$upper_khz" | sudo tee "$policy/scaling_max_freq" >/dev/null
            echo "$lower_khz" | sudo tee "$policy/scaling_min_freq" >/dev/null
        fi
    done

    if (( wrote == 0 )); then
        echo "Error: No cpufreq policy directories found under /sys/devices/system/cpu/cpufreq/."
        return 1
    fi

    return 0
}

confirm() {
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        return 0
    fi

    read -r -p "Continue? (y/n): " -n 1 reply
    echo
    [[ "$reply" =~ ^[Yy]$ ]]
}

ASSUME_YES=0
while getopts ":yh" opt; do
    case "$opt" in
        y)
            ASSUME_YES=1
            ;;
        h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

if [[ -z "$1" ]]; then
    usage
    exit 1
fi

LOWER="$1"
UPPER="${2:-$1}"

if ! [[ "$LOWER" =~ ^[0-9]+$ ]]; then
    echo "Error: Lower frequency must be a number in MHz."
    exit 1
fi

if ! [[ "$UPPER" =~ ^[0-9]+$ ]]; then
    echo "Error: Upper frequency must be a number in MHz."
    exit 1
fi

if (( LOWER > UPPER )); then
    echo "Error: Lower frequency (${LOWER} MHz) cannot be greater than upper frequency (${UPPER} MHz)."
    exit 1
fi

LOWER_KHZ="$(mhz_to_khz "$LOWER")"
UPPER_KHZ="$(mhz_to_khz "$UPPER")"

warn_if_outside_cpuinfo_range "$LOWER_KHZ" "$UPPER_KHZ"

echo "Pinning CPU frequency range to ${LOWER}-${UPPER} MHz"
if confirm && apply_with_sysfs "$LOWER_KHZ" "$UPPER_KHZ"; then
    echo "Success: CPU frequency pinned to ${LOWER}-${UPPER} MHz"
    print_effective_policy_ranges
    if command -v cpupower >/dev/null 2>&1; then
        sudo cpupower frequency-info
    else
        print_sysfs_status
    fi
else
    echo "Failed to pin CPU frequency range to ${LOWER}-${UPPER} MHz"
    exit 1
fi