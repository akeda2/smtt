#!/usr/bin/env bash

set -u

failed=0

install_one() {
	local src=$1 dst=$2 name=$3
	if install -m 755 "$src" "$dst"; then
		echo "$name install SUCCESS!"
	else
		echo "$name install FAIL!" >&2
		failed=1
	fi
}

if (( EUID != 0 )); then
	echo "ERROR: run as root (try: sudo ./inst.sh)" >&2
	exit 1
fi

install_one smtt.sh /usr/local/bin/smtt smtt
install_one turbot.sh /usr/local/bin/turbot turbot
install_one sockt.sh /usr/local/bin/sockt sockt
install_one setperf.sh /usr/local/bin/setperf setperf
install_one pinfreq.sh /usr/local/bin/pinfreq pinfreq
install_one ppws.sh /usr/local/bin/ppws ppws

exit "$failed"