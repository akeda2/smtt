#!/usr/bin/env bash
# Toggle turbo on/off
# Exits True (0) if turbo is ON

set -u

NO_TURBO=/sys/devices/system/cpu/intel_pstate/no_turbo

usage() {
	echo "Usage: turbot [on|off|t|h]"
	echo "When run with no args, prints state and exits 0 if on, 1 if off."
}

die() { echo "ERROR: $*" >&2; exit 1; }

require_supported() {
	[[ -f $NO_TURBO ]] || die "intel_pstate no_turbo interface not found: $NO_TURBO"
}

require_root() {
	(( EUID == 0 )) || die "run as root (try: sudo turbot ...)"
}

turbo_on(){ echo 0 > "$NO_TURBO"; }
turbo_off(){ echo 1 > "$NO_TURBO"; }

get_status() {
	local turbo_offstate
	turbo_offstate=$(<"$NO_TURBO")
	echo "$turbo_offstate"
}

case "${1:-}" in
	h|-h|--help)
		usage
		exit 0
		;;
esac

require_supported

case "${1:-}" in
	"") ;;
	off)
		require_root
		turbo_off
		;;
	on)
		require_root
		turbo_on
		;;
	t)
		require_root
		toggle_status=$(get_status)
		if [[ $toggle_status == 1 ]]; then
			turbo_on
		else
			turbo_off
		fi
		;;
	*)
		usage
		die "invalid argument: $1"
		;;
esac

return_state=$(get_status)
if [[ $return_state == 0 ]]; then
	echo "Turbo on"
	exit 0
else
	echo "Turbo off"
	exit 1
fi
