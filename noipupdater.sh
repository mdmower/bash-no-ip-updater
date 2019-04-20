#!/bin/bash

# Copyright (C) 2013 Matthew D. Mower
# Copyright (C) 2012 AntonioCS
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Defines

CONFIGFILE="$( cd "$( dirname "$0" )" && pwd )/config"

if [ -e "$CONFIGFILE" ]; then
    source "$CONFIGFILE"
else
    echo "Config file not found."
    exit 1
fi

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
   echo "USERNAME or PASSWORD has not been set in the config file."
   exit 1
fi

USERAGENT="Bash No-IP Updater/1.0 $USERNAME"

if [ ! -d "$LOGDIR" ]; then
    mkdir -p "$LOGDIR"
    if [ $? -ne 0 ]; then
        echo "Log directory could not be created or accessed."
        exit 1
    fi
fi

LOGFILE=${LOGDIR%/}/noip.log
if [ ! -e "$LOGFILE" ]; then
    touch "$LOGFILE"
    if [ $? -ne 0 ]; then
        echo "Log files could not be created. Is the log directory writable?"
        exit 1
    fi
elif [ ! -w "$LOGFILE" ]; then
    echo "Log file not writable."
    exit 1
fi

# Functions

function cmd_exists() {
    command -v "$1" > /dev/null 2>&1
}

function urlencode() {
    od -A n -t x1 | tr -d '\n' | sed 's/ /%/g'
}

function http_get() {
    if cmd_exists curl; then
        curl -s --user-agent "$USERAGENT" "$1"
    elif cmd_exists wget; then
        wget -q -O - --user-agent="$USERAGENT" "$1"
    else
        echo -n "No http tool found. Install curl or wget." >&2
        exit 1
    fi
}

function get_logline() {
    local host=$1
    local response=$(echo $2 | tr -cd "[:print:]")
    local response_a=$(echo $response | awk '{ print $1 }')
    local response_b

    case $response_a in
        "good")
            response_b=$(echo "$response" | awk '{ print $2 }')
            LOGLINE="(good) [$host] DNS hostname successfully updated to $response_b."
            ;;
        "nochg")
            response_b=$(echo "$response" | awk '{ print $2 }')
            LOGLINE="(nochg) [$host] IP address is current: $response_b; no update performed."
            ;;
        "nohost")
            LOGLINE="(nohost) [$host] Hostname supplied does not exist under specified account. Revise config file."
            ;;
        "badauth")
            LOGLINE="(badauth) [$host] Invalid username password combination."
            ;;
        "badagent")
            LOGLINE="(badagent) [$host] Client disabled - No-IP is no longer allowing requests from this update script."
            ;;
        '!donator')
            LOGLINE='(!donator)'" [$host] An update request was sent including a feature that is not available."
            ;;
        "abuse")
            LOGLINE="(abuse) [$host] Username is blocked due to abuse."
            ;;
        "911")
            LOGLINE="(911) [$host] A fatal error on our side such as a database outage. Retry the update in no sooner than 30 minutes."
            ;;
        *)
            LOGLINE="(error) [$host] Could not understand the response from No-IP. The DNS update server may be down."
            ;;
    esac

    return 0
}

# Program

NOW=$(date '+%s')

if [ -e "$LOGFILE" ] && tail -n1 "$LOGFILE" | grep -q -m1 '(abuse)'; then
    echo "This account has been flagged for abuse. You need to contact noip.com to resolve"
    echo "the issue. Once you have confirmed your account is in good standing, remove the"
    echo "log line containing (abuse) from:"
    echo "  $LOGFILE"
    echo "Then, re-run this script."
    exit 1
fi

if [ -e "$LOGFILE" ] && tac "$LOGFILE" | grep -q -m1 '(911)'; then
    NINELINE=$(tac "$LOGFILE" | grep -m1 '(911)')
    LASTNL=$([[ "$NINELINE" =~ \[([^\]]+?)\] ]] && echo "${BASH_REMATCH[1]}")
    LASTCONTACT=$(date -d "$LASTNL" '+%s')
    if [ `expr $NOW - $LASTCONTACT` -lt 1800 ]; then
        LOGDATE="[$(date +'%Y-%m-%d %H:%M:%S')]"
        LOGLINE="Response code 911 received less than 30 minutes ago; canceling request."
        echo "$LOGLINE"
        echo "$LOGDATE $LOGLINE" >> "$LOGFILE"
        exit 1
    fi
fi

if [ "$ROTATE_LOGS" = true ]; then
    LOGLENGTH=$(wc -l "$LOGFILE" | awk '{ print $1 }')
    if [ $LOGLENGTH -ge 10010 ]; then
        BACKUPDATE=$(date +'%Y-%m-%d_%H%M%S')
        BACKUPFILE="$LOGFILE-$BACKUPDATE.log"
        touch "$BACKUPFILE"
        if [ $? -eq 0 ]; then
            head -10000 "$LOGFILE" > "$BACKUPFILE"
            if cmd_exists gzip; then
                gzip "$BACKUPFILE"
            fi
            LASTLINES=$(tail -n +10001 "$LOGFILE")
            echo "$LASTLINES" > "$LOGFILE"
            echo "Log file rotated"
        else
            echo "Log file could not be rotated"
        fi
    fi
fi

USERNAME=$(echo -ne "$USERNAME" | urlencode)
PASSWORD=$(echo -ne "$PASSWORD" | urlencode)
HOST=$(echo -ne "$HOST" | urlencode)

RESPONSE=$(http_get "https://$USERNAME:$PASSWORD@dynupdate.no-ip.com/nic/update?hostname=$HOST")
OIFS=$IFS
IFS=$'\n'
SPLIT_RESPONSE=( $(echo "$RESPONSE" | grep -o '[0-9a-z!]\+\( [0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\)\?') )
IFS=','
SPLIT_HOST=( $(echo "$HOST") )
IFS=$OIFS

LOGDATE="[$(date +'%Y-%m-%d %H:%M:%S')]"

for index in "${!SPLIT_HOST[@]}"; do
    get_logline "${SPLIT_HOST[index]}" "${SPLIT_RESPONSE[index]}"
    echo "$LOGLINE"
    echo "$LOGDATE $LOGLINE" >> "$LOGFILE"
done

exit 0
