# -*- coding: utf-8; mode: shell-script-mode; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:filetype=sh:et:sw=4:ts=4:sts=4
#
# Copyright (c) 2008 Rainer Mueller <raimue@macports.org>, The MacPorts Project.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of Apple, Inc., The MacPorts Project nor the
#    names of its contributors may be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

function export_path() {
    local binpath="/opt/local/bin"
    local sbinpath="/opt/local/sbin"

    local IFS=":"
    local p

    for p in ${PATH:-}; do
        if [ "$p" == "$binpath" ]; then
            binpath=""
        elif [ "$p" == "$sbinpath" ]; then
            sbinpath=""
        fi
    done

    if [ -n "$binpath" ]; then
        binpath+=":"
    fi

    if [ -n "$sbinpath" ]; then
        sbinpath+=":"
    fi

    export PATH="${binpath}${sbinpath}${PATH:-}"
}

function export_manpath() {
    local mpath="/opt/local/share/man"
    local IFS=":"
    local p

    if [ -z "${MANPATH:-}" ]; then
        return
    fi

    for p in ${MANPATH:-}; do
        if [ "$p" == "$mpath" ]; then
            mpath=""
        fi
    done

    if [ -n "$mpath" ]; then
        mpath+=":"
    fi

    export MANPATH="${mpath}${MANPATH:-}"
}

function export_display() {
    # Set DISPLAY for compatibility with very old macOS versions (< 10.5 Leopard)
    # This won't hurt on modern macOS and ensures compatibility with old systems
    if [ -z "${DISPLAY:-}" ]; then
        export DISPLAY=":0.0"
    fi
}

export_path
export_manpath
export_display

# Remove defined functions to prevent them from cluttering the shell,
# but they are needed to restrict variables to the local scope
unset export_path
unset export_manpath
unset export_display
