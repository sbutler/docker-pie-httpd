#!/bin/bash
set -e

ccopts=('-p/var/cache/apache2/mod_cache_disk')
cchascmd=n
while getopts ':l:L:aA' opt; do
    if [[ $cchascmd == 'y' ]]; then
        echo "Only one command allowed"
        echo "Usage: $0 [-l LIMIT | -L LIMIT | -a | -A] | [URL] [URL] [...]"
        exit 2
    fi

    case "$opt" in
        l)      ccopts+=("-l$OPTARG") ;;
        L)      ccopts+=("-L$OPTARG") ;;
        a)      ccopts+=("-a") ;;
        A)      ccopts+=("-A") ;;

        \? )
            echo "Invalid option: $opt"
            echo "Usage: $0 [-l LIMIT | -L LIMIT | -a | -A] | [URL] [URL] [...]"
            exit 2
            ;;

        : )
            echo "Invalid option: $opt requires an argument"
            exit 2
            ;;
    esac
    cchascmd=y
done

shift $((OPTIND - 1))
if [[ $cchascmd == 'y' && $# -gt 0 ]]; then
    echo "URL arguments not allowed"
    exit 2
elif [[ $cchascmd == 'n' && $# -eq 0 ]]; then
    echo "URL arguments required if no command"
    exit 2
fi

exec /usr/bin/htcacheclean "${ccopts[@]}" "$@"
