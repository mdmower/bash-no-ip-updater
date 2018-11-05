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

USERAGENT="Bash No-IP Updater/0.9 $USERNAME"

USERNAME=$(echo -ne "$USERNAME" | od -A n -t x1 | tr -d '\n' | sed 's/ /%/g')
PASSWORD=$(echo -ne "$PASSWORD" | od -A n -t x1 | tr -d '\n' | sed 's/ /%/g')

if [ ! -d "$LOGDIR" ]; then
    mkdir -p "$LOGDIR"
    if [ $? -ne 0 ]; then
        echo "Log directory could not be created or accessed."
        exit 1
    fi
fi

LOGFILE=${LOGDIR%/}/noip.log
IPFILE=${LOGDIR%/}/last_ip
if [ ! -e "$LOGFILE" ] || [ ! -e "$IPFILE" ]; then
    touch "$LOGFILE" "$IPFILE"
    if [ $? -ne 0 ]; then
        echo "Log files could not be created. Is the log directory writable?"
        exit 1
    fi
elif [ ! -w "$LOGFILE" ] || [ ! -w "$IPFILE" ]; then
    echo "Log files not writable."
    exit 1
fi

# Functions

# IP Validator
# http://www.linuxjournal.com/content/validating-ip-address-bash-script
function valid_ip() {
    local ip=$1
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi

    return $stat
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

GET_IP_URLS[0]="https://ipv4.icanhazip.com"
GET_IP_URLS[1]="https://ipv4.wtfismyip.com/text"
GET_IP_URLS[2]="https://v4.ident.me"
GET_IP_URLS[3]="https://api.ipify.org"

GIP_INDEX=0
while [ -n ${GET_IP_URLS[$GIP_INDEX]} ] && ! valid_ip "$NEWIP"; do
    NEWIP=$(curl -s ${GET_IP_URLS[$GIP_INDEX]} | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
    let GIP_INDEX++
done

if ! valid_ip "$NEWIP"; then
    LOGDATE="[$(date +'%Y-%m-%d %H:%M:%S')]"
    LOGLINE="Could not find current IP"
    echo "$LOGLINE"
    echo "$LOGDATE $LOGLINE" >> "$LOGFILE"
    exit 1
fi

ENCODED_HOST=${HOST//,/%2C}
RESPONSE=$(curl -s -k --user-agent "$USERAGENT" "https://$USERNAME:$PASSWORD@dynupdate.no-ip.com/nic/update?hostname=$ENCODED_HOST&myip=$NEWIP")
OIFS=$IFS
IFS=$'\n'
SPLIT_RESPONSE=( $(echo "$RESPONSE" | grep -o '[0-9a-z!]\+\( [0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\)\?') )
IFS=','
SPLIT_HOST=( $(echo "$HOST") )
IFS=$OIFS

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

echo "IP: $NEWIP"
echo -n "$NEWIP" > "$IPFILE"

LOGDATE="[$(date +'%Y-%m-%d %H:%M:%S')]"

for index in "${!SPLIT_HOST[@]}"; do
    get_logline "${SPLIT_HOST[index]}" "${SPLIT_RESPONSE[index]}"
    echo "$LOGLINE"
    echo "$LOGDATE $LOGLINE" >> "$LOGFILE"
done

exit 0
