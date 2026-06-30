#!/usr/bin/env bash
# SMT-toggle

set -u

CONTROL=/sys/devices/system/cpu/smt/control
ACTIVE=/sys/devices/system/cpu/smt/active

usage() {
	echo "Usage: smtt [on|off|t|get|h]"
	echo "When run with no args, prints state and exits 0 if on, 1 if off."
}

die() { echo "ERROR: $*" >&2; exit 1; }

get_state() {
	local smt_state
	smt_state=$(<"$ACTIVE")
	echo "$smt_state"
}

require_root() {
	(( EUID == 0 )) || die "run as root (try: sudo smtt ...)"
}

set_state() {
	local target=$1
	echo "$target" > "$CONTROL"
}

case "${1:-}" in
	"") ;;
	on|off)
		require_root
		set_state "$1"
		get_state
		exit 0
		;;
	get)
		get_state
		exit 0
		;;
	t)
		require_root
		if [[ $(get_state) -eq 1 ]]; then
			echo "From on..."
			set_state off
		else
			echo "From off...!"
			set_state on
		fi
		if [[ $(get_state) -eq 1 ]]; then
			echo "...to on!"
		else
			echo "...to off!"
		fi
		;;
	h|-h|--help)
		usage
		exit 0
		;;
	*)
		usage
		die "invalid argument: $1"
		;;
esac

return_state=$(get_state)
if [[ $return_state == 1 ]]; then
	echo "SMT on"
	exit 0
else
	echo "SMT off"
	exit 1
fi