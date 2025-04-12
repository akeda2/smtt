#!/bin/bash
# SMT-toggle

CONTROL=/sys/devices/system/cpu/smt/control

get_state() { local SMT_STATE=$(cat /sys/devices/system/cpu/smt/active); echo $SMT_STATE ;}
set_state() { echo "$1" | sudo tee "$CONTROL" > /dev/null && return || false ;}
we_failed() { echo "FAIL"; exit 1 ;}
if [[ ! -z "$1" ]]; then
	if [[ "$1" == "on" || "$1" == "off" ]]; then
		set_state "$1" && get_state && exit 0 || exit 1
	elif [[ "$1" == "get" ]]; then
		get_state && exit 0 || exit 1
	elif [[ "$1" == "t" ]]; then
		[[ $(get_state) -eq 1 ]] \
			&& { echo "From on..."; set_state 'off' || we_failed ;} \
			|| { echo "From off...!"; set_state 'on' || we_failed ;}
		[[ $(get_state) -eq 1 ]] \
	        	&& { echo "...to on!" ;} \
        		|| { echo "...to off!" ;}

	elif [[ "$1" == "h" ]]; then
		echo "Usage: smtt on|off|t, leave empty for status."; exit
	fi
fi
RETURN_STATE=$(get_state); [[ $RETURN_STATE == 1 ]] && { echo "SMT on"; exit 0;} || { echo "SMT off"; exit 1;}