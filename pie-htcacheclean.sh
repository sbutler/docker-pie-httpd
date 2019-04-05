#!/bin/bash
# Copyright (c) 2019 University of Illinois Board of Trustees
# All rights reserved.
#
# Developed by: 		Technology Services
#                      	University of Illinois at Urbana-Champaign
#                       https://techservices.illinois.edu/
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# with the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
#	* Redistributions of source code must retain the above copyright notice,
#	  this list of conditions and the following disclaimers.
#	* Redistributions in binary form must reproduce the above copyright notice,
#	  this list of conditions and the following disclaimers in the
#	  documentation and/or other materials provided with the distribution.
#	* Neither the names of Technology Services, University of Illinois at
#	  Urbana-Champaign, nor the names of its contributors may be used to
#	  endorse or promote products derived from this Software without specific
#	  prior written permission.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS WITH
# THE SOFTWARE.
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
