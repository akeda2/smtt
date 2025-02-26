#!/bin/bash
# Toggle turbo on/off
# Exits True (0) if turbo is ON

TURBO_OFFSTATE="$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)"

turbo_on(){ echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo > /dev/null;}
turbo_off(){ echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo > /dev/null;}
get_status() { local TURBO_OFFSTATE="$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)" ; echo $TURBO_OFFSTATE ;}

if [[ ! -z $1 ]]; then
	if [[ $1 == off ]]; then
		turbo_off
	elif [[ $1 == on ]]; then
		turbo_on
	elif [[ $1 == t ]]; then
		TOGGLE_STATUS=$(get_status); [[ $TOGGLE_STATUS == 1 ]] && turbo_on || turbo_off
	else
		echo "Usage: seturbo 'on|off', 't' for toggle. Leave empty for status: 0=off, 1=on"
	fi
fi

RETURN_STATE=$(get_status); [[ $RETURN_STATE == 0 ]] && { echo "Turbo on"; exit 0 ;} || { echo "Turbo off" ; exit 1 ;}
