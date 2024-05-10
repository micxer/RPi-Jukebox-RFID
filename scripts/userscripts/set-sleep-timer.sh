#!/bin/bash

shutdownvolumereductionvalue="$(sudo atq -q q | awk '{print $5}')" # get the time of the next scheduled shutdown
if [ -z "$shutdownvolumereductionvalue" ]; then
    current_time=$(date +%H:%M) # get the current time in HH:MM format
    if [[ "$current_time" > "19:00" || "$current_time" < "06:00" ]]; then
        echo "Current time is between 19:00 and 6:00 and no shutdown timer set. Setting shutdown..."
        script_path="$(dirname "$(readlink -f "$0")")" # get the path of the current script
        /usr/bin/sudo $script_path/../playout_controls.sh -c=shutdownvolumereduction -v=60
    fi
fi
