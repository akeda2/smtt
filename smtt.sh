#!/bin/bash
# SMT-toggle

CONTROL=/sys/devices/system/cpu/smt/control

check_state() { SMT_STATE=$(cat /sys/devices/system/cpu/smt/active); echo $SMT_STATE ;}
set_state() { echo "$1" | sudo tee "$CONTROL" > /dev/null && return || false ;}
we_failed() { echo "FAIL"; exit 1 ;}

[[ $(check_state) -eq 1 ]] \
	&& { echo "From on..."; set_state 'off' || we_failed ;} \
	|| { echo "From off...!"; set_state 'on' || we_failed ;}
[[ $(check_state) -eq 1 ]] \
	&& { echo "...to on!" ;} \
	|| { echo "...to off!" ;}
