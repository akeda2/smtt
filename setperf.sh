#!/bin/bash

usage() {
	echo "Usage: $0 [-y] <perf|sav|pow|ond>"
	echo "  -y  Apply without confirmation prompt"
}

confirm() {
	if [[ "$ASSUME_YES" -eq 1 ]]; then
		return 0
	fi

	read -r -p "Continue? (y/n): " -n 1 reply
	echo
	[[ "$reply" =~ ^[Yy]$ ]]
}

normalize_mode() {
	case "$1" in
		perf*)
			echo "performance"
			;;
		sav*|pow*)
			echo "powersave"
			;;
		ond*)
			echo "ondemand"
			;;
		*)
			return 1
			;;
	esac
}

powerprofiles_mode() {
	case "$1" in
		performance)
			echo "performance"
			;;
		powersave)
			echo "power-saver"
			;;
		ondemand)
			echo "balanced"
			;;
		*)
			return 1
			;;
	esac
}

show_status() {
	if command -v powerprofilesctl >/dev/null 2>&1; then
		echo " - powerprofilesctl:"
		powerprofilesctl list
		powerprofilesctl get
	fi

	if command -v cpupower >/dev/null 2>&1; then
		echo " - cpupower:"
		sudo cpupower frequency-info
	fi

	echo " - cpufreq governors:"
	cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null
	grep . /sys/devices/system/cpu/cpufreq/policy*/scaling_driver 2>/dev/null
}

apply_with_powerprofilesctl() {
	local pp_mode
	pp_mode="$(powerprofiles_mode "$MODE")" || return 1

	echo "Using powerprofilesctl ($pp_mode)..."
	confirm && sudo powerprofilesctl set "$pp_mode"
}

apply_with_cpupower() {
	echo "Using cpupower ($MODE)..."
	if ! confirm; then
		return 0
	fi

	sudo cpupower frequency-set -g "$MODE"
	if [[ "$MODE" == "performance" ]]; then
		sudo cpupower set -b 0
	else
		sudo cpupower set -b 3
	fi
}

apply_with_sysfs() {
	echo "Using cpufreq sysfs ($MODE)..."
	confirm && echo "$MODE" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
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

MODE="$(normalize_mode "$1")" || {
	echo "Invalid argument: $1"
	usage
	exit 1
}

echo "Setting CPU governor mode to $MODE"

if command -v powerprofilesctl >/dev/null 2>&1; then
	apply_with_powerprofilesctl
elif command -v cpupower >/dev/null 2>&1; then
	apply_with_cpupower
else
	apply_with_sysfs
fi

show_status