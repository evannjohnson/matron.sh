#!/bin/bash

#######################################
# evaluate lua code in the matron REPL on a norns accessible via SSH
# to evaluate a multiline string, requires that a base64 decoding function be
# accessible from matron via require('base64').dec(b64_string)
# recommend putting the library at /home/we/norns/lua/lib/base64.lua
#
# args:
#   1. the hostname of the norns (ex. just "norns" for the stock hostname, no .local)
#   2. lua code to evaluate on the target norns
#######################################
function eval_on_norns() {
    if [[ $(echo "$2" | wc -l) -gt 1 ]]
    then
        code_b64=$(printf "%s" "$2" | base64)
        printf "load(require('base64').dec('%s'))()\n" "$code_b64" | websocat --one-message --protocol bus.sp.nanomsg.org "ws://$1:5555"
    else
        echo "$2" | websocat --one-message --protocol bus.sp.nanomsg.org "ws://$1:5555"
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

matron.sh -r

    opens a REPL to norns.local

matron.sh -H norns-shield 'norns.script.load(\"code/awake/awake.lua\")'

    loads the awake script on norns-shield.local

matron.sh -re -n grey

    opens \$EDITOR to input code to evaluatee on norns-grey.local, and then after that code is evaluated, enter the matron REPL on that norns

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

hostname="${hostname:-norns}.local"

if [[ -n "${1+x}" ]]; then
    luacode="$1"
fi

if [[ $openeditor ]]
then
    printf "%s" "$luacode"  > "$temp_file"
    ${EDITOR:-vi} "$temp_file"
    eval_on_norns "$hostname" "$(cat $temp_file)"
elif [[ $luacode ]]
then
    eval_on_norns "$hostname" "$luacode"
fi

if [[ $openrepl || ( ! $luacode && ! $openeditor ) ]]
then
    if [[ ! $plain ]]
    then
        echo -ne '\033[22;0t'  # save title on stack
        trap "echo -ne '\033[23;0t'" EXIT # restore title on exit
        if [[ $NERD_FONT ]];
        then
            echo -ne "\033]0;󱁷  $(basename $0) - $hostname\007"
        else
            echo -ne "\033]0;$(basename $0) - $hostname\007"

        fi
    fi

    rlwrap websocat --protocol bus.sp.nanomsg.org "ws://$hostname:5555" | stdbuf -i0 -o0 ssh "${hostname%.local}" "journalctl --output=cat -fu norns-matron"
fi
