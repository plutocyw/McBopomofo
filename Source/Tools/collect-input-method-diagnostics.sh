#!/bin/bash

set -u

OUTPUT_DIR="${OUTPUT_DIR:-$PWD}"
LOG_WINDOW="${LOG_WINDOW:-30m}"
AFFECTED_APP="${AFFECTED_APP:-unknown}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_FILE="$OUTPUT_DIR/McBopomofo-input-diagnostics-$TIMESTAMP.log"
INSTALLED_APP="$HOME/Library/Input Methods/McBopomofo.app"
DIAGNOSTIC_REPORTS="$HOME/Library/Logs/DiagnosticReports"

mkdir -p "$OUTPUT_DIR"

{
    printf 'McBopomofo input method diagnostics\n'
    printf 'captured_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'affected_app=%s\n' "$AFFECTED_APP"
    printf 'log_window=%s\n' "$LOG_WINDOW"

    printf '\nSystem version\n'
    /usr/bin/sw_vers

    printf '\nRelevant processes\n'
    /bin/ps -axo pid=,ppid=,lstart=,etime=,stat=,command= \
        | /usr/bin/awk \
            '/McBopomofo|imklaunchagent|TextInputMenuAgent/ && !/awk/ { print }'

    printf '\nMcBopomofo process samples\n'
    while IFS= read -r process_id; do
        if [[ -n "$process_id" ]]; then
            /usr/bin/sample "$process_id" 1 1
        fi
    done < <(/usr/bin/pgrep -x McBopomofo 2>/dev/null)

    printf '\nInstalled input method\n'
    if [[ -d "$INSTALLED_APP" ]]; then
        /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
            "$INSTALLED_APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
            "$INSTALLED_APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
            "$INSTALLED_APP/Contents/Info.plist"
        /usr/bin/stat -f 'installed_mtime=%Sm' -t '%Y-%m-%dT%H:%M:%S%z' "$INSTALLED_APP"
    else
        printf 'not_installed=%s\n' "$INSTALLED_APP"
    fi

    printf '\nRelated diagnostic reports\n'
    if [[ -d "$DIAGNOSTIC_REPORTS" ]]; then
        /usr/bin/find "$DIAGNOSTIC_REPORTS" -maxdepth 1 -type f \
            \( -name 'McBopomofo*' -o -name 'imklaunchagent*' \
                -o -name 'TextInputMenuAgent*' \) -print
    fi

    printf '\nUnified log\n'
    /usr/bin/log show --last "$LOG_WINDOW" --style compact \
        --predicate \
        'subsystem == "org.openvanilla.inputmethod.McBopomofo" OR process == "McBopomofo" OR process == "imklaunchagent" OR process == "TextInputMenuAgent"' \
        --info --debug
} > "$OUTPUT_FILE" 2>&1

printf 'Diagnostic report: %s\n' "$OUTPUT_FILE"
