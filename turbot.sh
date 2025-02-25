#!/bin/bash
# Toggle turbo on/off
TURBO_OFFSTATE="$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)"

turbo_on(){
	echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo > /dev/null
}
turbo_off(){
	echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo > /dev/null
}
print_status(){
	TURBO_OFFSTATE="$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)"
	[[ $TURBO_OFFSTATE == 1 ]] && echo "Turbo off" || echo "Turbo on"
}

if [[ ! -z $1 ]]; then
	if [[ $1 == off ]]; then
		turbo_off
		print_status
	elif [[ $1 == on ]]; then
		turbo_on
		print_status
	elif [[ $1 == t ]]; then
		[[ $TURBO_OFFSTATE == 1 ]] && turbo_on || turbo_off
		print_status
	else
		echo "Usage: seturbo 'on|off', 't' for toggle. Leave empty for status: 0=off, 1=on"
	fi
else
	[[ $TURBO_OFFSTATE == 0 ]] && { echo "Turbo on"; exit 1 ;} || { echo "Turbo off" ; exit 0 ;}
fi