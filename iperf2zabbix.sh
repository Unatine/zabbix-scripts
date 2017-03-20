#!/usr/bin/env bash

#
# Author: pavel at marakhovsky dot com
#
# Description: Run iperf3 test to specific iperf3 server
# If return code is't 0, try check another ports from defined range.
# Also, timeout for iperf run set. If iperf3 don't exit after specified seconds, it will be killed.
#
# Depends: iperf3, zabbix_sender, gawk, timeout

set -o pipefail

#
# Define some parameters
#

# Use iperf3 server for tests
# IPERFS="ping.online.net"
IPERFS="62.210.18.40"

# Zabbix server for sending results
ZBX_SERVER=192.168.4.200

#Default port for first run
PORT=5209

# Start and end port range
SPORT=5201
EPORT=5210

# iperf parameters
IPERF_PARAMS="-u --time 10"

# Timeout for iperf (used to fix some strange iperf3 behavior)
TIMEOUT=15s



# Load last good port from file, or create new
if [ -f /tmp/.iperf-lastport ]
then
	PORT=$(cat /tmp/.iperf-lastport)
else
	# Create port file
	echo $PORT > /tmp/.iperf-lastport
fi

# 
function usage
{
        if [ -n "$1" ]; then echo $1; fi
        echo "Usage: $0 <hostname_in_zabbix>"
        exit 1
}

ARGS=(${@:$OPTIND})
SERVER=${ARGS[0]}

# Checking hostname parameter
if [ -z "$SERVER" ]; then usage "No hostname."; fi;

# Run iperf3 test
timeout -s KILL --preserve-status $TIMEOUT iperf3 -c $IPERFS -p $PORT $IPERF_PARAMS > /tmp/.iperf-results

# Check exit code
# If don't 0, try another ports from port range
if [ "$?" -ne "0" ]; then
    # try another port
    PORT=$SPORT

    while [ $PORT -le $EPORT ]; do
        timeout -s KILL --preserve-status $TIMEOUT iperf3 -c $IPERFS -p $PORT $IPERF_PARAMS > /tmp/.iperf-results

        if [ "$?" -ne "0" ]; then
	   let PORT+=1
        else
	   echo $PORT > /tmp/.iperf-lastport
	   break
        fi
    done

    # Do only one try for all ports
    exit 1
fi

# Parse results and send to Zabbix server
cat /tmp/.iperf-results | tail -n 4 | head -n 1 | gawk -F " " '{ jitter=$9; lost=substr($12,2,length($12)-3); if(match(lost,"nan")>0) {lost=0;}; printf("- iperf.udp.jitter %s\n- iperf.udp.lost_percent %s\n", jitter, lost)}' | zabbix_sender -z $ZBX_SERVER --host $SERVER -i -

exit 0

