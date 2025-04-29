#!/bin/bash

#######################################
# evaluate supercollider code in the crone REPL on a norns accessible via SSH
#
# args:
#   1. the hostname of the norns (ex. just "norns" for the stock hostname, no .local)
#   2. supercollider code to evaluate on the target norns
#######################################
function eval_on_norns() {
    printf "%s\x1b\n" "$2" | websocat --protocol bus.sp.nanomsg.org "ws://$1:5556"
}

function find_norns() {
    local hosts=("norns.local" "norns-shield.local" "norns-grey.local")
    local reachable=()

    for host in "${hosts[@]}"; do
        if timeout 0.3 ping -c 1 "$host" > /dev/null 2>&1; then
            reachable+=("$host")
        fi
    done

    if [ "${#reachable[@]}" -eq 1 ]; then
        echo "${reachable[0]}"
    elif [ "${#reachable[@]}" -gt 1 ]; then
        echo "multiple norns found, choose one:"
        select host in "${reachable[@]}"; do
            if [ -n "$host" ]; then
                echo "$host"
                break
            fi
        done
    else
        echo "norns.local"
    fi
}

openeditor=
openrepl=
plain=
while getopts 'erphH:n:' OPTION
do
    case $OPTION in
        e)
            openeditor=1
            temp_file=$(mktemp)
            mv "$temp_file" "$temp_file.lua"
            temp_file="$temp_file.lua"
            trap 'rm -f "$temp_file"' EXIT
            ;;
        r)
            openrepl=1
            ;;
        p)
            plain=1
            ;;
        H)
            hostname="$OPTARG"
            ;;
        n)
            hostname="norns-$OPTARG"
            ;;
        h)
            printf "Usage: %s: [-re] [-H hostname] [-n name] [luacode]

options:
    -H hostname: connection will go to <hostname>.local
        - ex. -H some-norns will connect to some-norns.local
        - if not specified, uses \"norns.local\"
    -n name: connection will go to norns-<name>.local
        - simply a shorter form of -H if your norns has a certain hostname convention,
          like \"norns-something\"
        - ex. -n shield will connect to to norns-shield.local
        - if used along with -H, whichever option comes last takes precedence
    -r: enter the maiden REPL after evaluating the provided lua code (either via arg or -e)
        - the REPL is automatically entered if no lua code is provided
    -e: open \$EDITOR for entering the code to execute
        - if luacode is provided as an arg, \$EDITOR will be populated with it
    -p: \"plain\" mode, don't set the terminal title or do anything else fancy/experimental that may be implemented in the future

examples:

crone.sh -r

    opens the sclang REPL on norns.local

crone.sh -H norns-shield 'norns.script.load(\"code/awake/awake.lua\")'

    loads the awake script on norns-shield.local

crone.sh -re -n grey

    opens \$EDITOR to input code to evaluatee on norns-grey.local, and then after that code is evaluated, enter the sclang REPL on that norns

\n" "${0##*/}"
           exit
           ;;
        ?)
           printf "Usage: %s: [-re] [-H hostname] [-n name] luacode\n" "${0##*/}" >&2
           exit 2
           ;;
    esac
done
shift $(($OPTIND - 1))

if [ "$hostname" ]
then
    hostname="${hostname:-norns}.local"
else
    hostname="$(find_norns)"
fi

if [[ -n "${1+x}" ]]; then
    sc_code="$1"
fi

if [[ $openeditor ]]
then
    printf "%s" "$sc_code"  > "$temp_file"
    ${EDITOR:-vi} "$temp_file"
    eval_on_norns "$hostname" "$(cat $temp_file)"
elif [[ $sc_code ]]
then
    eval_on_norns "$hostname" "$sc_code"
fi

if [[ $openrepl || ( ! $sc_code && ! $openeditor ) ]]
then
    if [[ ! $plain ]]
    then
        echo -ne '\033[22;0t'  # save title on stack
        trap "echo -ne '\033[23;0t'" EXIT # restore title on exit
        if [[ $NERD_FONT ]];
        then
            echo -ne "\033]0;󰹻  $(basename $0) - $hostname\007"
        else
            echo -ne "\033]0;$(basename $0) - $hostname\007"

        fi
    fi

    # rlwrap websocat --protocol bus.sp.nanomsg.org "ws://$hostname:5556" | stdbuf -i0 -o0 ssh "${hostname%.local}" "journalctl --output=cat -fu norns-sclang"
    rlwrap sh -c 'while IFS= read -r line; do printf "%s\033\n" "$line"; done | websocat --protocol bus.sp.nanomsg.org "ws://'"$hostname"':5556"' | stdbuf -i0 -o0 ssh "${hostname%.local}" "journalctl --output=cat -fu norns-sclang"
fi
