#!/bin/bash
# SMT-toggle

CONTROL=/sys/devices/system/cpu/smt/control

get_state() { SMT_STATE=$(cat /sys/devices/system/cpu/smt/active); echo $SMT_STATE ;}
set_state() { echo "$1" | sudo tee "$CONTROL" > /dev/null && return || false ;}
we_failed() { echo "FAIL"; exit 1 ;}
[[ ! -z "$1" ]] && \
	[[ "$1" == "on" || "$1" == "off" ]] && { set_state "$1" && get_state && exit 0 || exit 1;}
	[[ "$1" == "get" ]] && { get_state && exit 0 || exit 1;} \
	|| [[ $(get_state) -eq 1 ]] \
			&& { echo "From on..."; set_state 'off' || we_failed ;} \
			|| { echo "From off...!"; set_state 'on' || we_failed ;}
[[ $(get_state) -eq 1 ]] \
	&& { echo "...to on!" ;} \
	|| { echo "...to off!" ;}
