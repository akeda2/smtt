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

set_epp_if_available() {
	local target="$1"
	local policy

	for policy in /sys/devices/system/cpu/cpufreq/policy*; do
		[[ -d "$policy" ]] || continue
		if [[ -w "$policy/energy_performance_preference" ]]; then
			echo "$target" | sudo tee "$policy/energy_performance_preference" >/dev/null 2>&1 || true
		fi
	done
}

governor_exists_any_policy() {
	local wanted="$1"
	local policy

	for policy in /sys/devices/system/cpu/cpufreq/policy*; do
		[[ -d "$policy" ]] || continue
		if [[ -r "$policy/scaling_available_governors" ]] && grep -qw "$wanted" "$policy/scaling_available_governors"; then
			return 0
		fi
	done

	return 1
}

preferred_governor_for_mode() {
	case "$1" in
		performance)
			echo "performance"
			;;
		powersave)
			echo "powersave"
			;;
		ondemand)
			if governor_exists_any_policy "ondemand"; then
				echo "ondemand"
			else
				echo "powersave"
			fi
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
	grep . /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference 2>/dev/null || true
}

show_supported_settings() {
	local policy

	echo " - supported cpufreq settings:"
	for policy in /sys/devices/system/cpu/cpufreq/policy*; do
		[[ -d "$policy" ]] || continue
		echo "   ${policy##*/}:"
		if [[ -r "$policy/scaling_available_governors" ]]; then
			echo "     governors: $(cat "$policy/scaling_available_governors")"
		fi
		if [[ -r "$policy/energy_performance_available_preferences" ]]; then
			echo "     epp: $(cat "$policy/energy_performance_available_preferences")"
		fi
	done
}

apply_with_sysfs() {
	local gov="$1"
	local wrote=0
	local policy

	echo "Using cpufreq sysfs (mode=$MODE governor=$gov)..."
	if ! confirm; then
		return 0
	fi

	for policy in /sys/devices/system/cpu/cpufreq/policy*; do
		[[ -d "$policy" ]] || continue
		wrote=1
		echo "$gov" | sudo tee "$policy/scaling_governor" >/dev/null
	done

	if (( wrote == 0 )); then
		echo "No cpufreq policies found under /sys/devices/system/cpu/cpufreq/"
		return 1
	fi

	case "$MODE" in
		performance)
			set_epp_if_available "performance"
			;;
		powersave)
			set_epp_if_available "power"
			;;
		ondemand)
			set_epp_if_available "balance_performance"
			;;
	esac

	if [[ "$MODE" == "ondemand" && "$gov" != "ondemand" ]]; then
		echo "Note: ondemand governor unavailable; applied powersave governor as closest kernel-native fallback."
	fi
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
	echo "Current settings:"
	show_status
	echo
	show_supported_settings
	echo
	usage
	exit 0
fi

MODE="$(normalize_mode "$1")" || {
	echo "Invalid argument: $1"
	usage
	exit 1
}

echo "Setting CPU governor mode to $MODE"

TARGET_GOV="$(preferred_governor_for_mode "$MODE")" || {
	echo "Failed to resolve governor for mode $MODE"
	exit 1
}

apply_with_sysfs "$TARGET_GOV"

show_status