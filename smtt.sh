#!/bin/bash
# SMT-toggle
CONTROL=/sys/devices/system/cpu/smt/control
check_state() {
	SMT_STATE=$(cat /sys/devices/system/cpu/smt/active)
	echo $SMT_STATE
}
[[ $(check_state) -eq 1 ]] && \
	{ echo "SMT is on!"; echo 'off' | sudo tee $CONTROL ;} || { echo "SMT is off!"; echo 'on' | sudo tee $CONTROL ;}
echo "SMT is $(check_state)"
