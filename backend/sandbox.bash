#!/usr/bin/env bash
# This script is sourced by Bash within 'make sandbox'.

if [[ -z "$L" ]]; then
    echo "environment variable unset: \$L" >&2
    exit 1
fi

if [[ -z "$LANG_CONFIG" ]]; then
    echo "environment variable unset: \$LANG_CONFIG" >&2
    exit 1
fi

function get {
    jq -r ".$1" <<<"${LANG_CONFIG}"
}

function has {
    get "$@" | grep -vq '^null$'
}

function riju-exec {
    bash -c "set -euo pipefail; $1"
}

function daemon {
    if has daemon; then
        get daemon
        riju-exec "$(get daemon)"
    fi
}

function setup {
    if has setup; then
        get setup
        riju-exec "$(get setup)"
    fi
}

function repl {
    if has repl; then
        get repl
        riju-exec "$(get repl)"
    fi
}

function main {
    if get main | grep -q /; then
        mkdir -p "$(dirname "$(get main)")"
    fi
    : >"$(get main)"
    has prefix && get prefix >>"$(get main)"
    get template >>"$(get main)"
    has suffix && get suffix >>"$(get main)"
}

function compile {
    if has compile; then
        get compile
        riju-exec "$(get compile)"
    fi
}

function run-only {
    if has run; then
        get run
        riju-exec "$(get run)"
    fi
}

function run {
    compile && run-only
}

function format {
    if has format; then
        get format.run
        riju-exec "( $(get format.run) ) < $(get main)"
    fi
}

function lsp {
    if has lsp.setup; then
        get lsp.setup
        riju-exec "$(get lsp.setup)"
    fi
    if has lsp; then
        get lsp.start
        riju-exec "$(get lsp.start)"
    fi
}

if [[ -z "$NS" ]]; then
    main
    setup
fi
