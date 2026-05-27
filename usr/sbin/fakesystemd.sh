#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -uo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: fakesystemd.sh <command> [args...]" >&2
    exit 1
fi

export NOTIFY_SOCKET=/tmp/fakesystemd.sock

pidfile="/tmp/fakesystemd.pid"
listener_pid=""

finish() {
    local rc="$1"
    local pidfile="$2"
    local listener_pid="$3"
    local daemon_pid="$4"

    rm -f "$NOTIFY_SOCKET" "$pidfile" "${pidfile}.tmp"
    [[ -n "$listener_pid" ]] && kill "$listener_pid" 2>/dev/null || true
    [[ -n "$daemon_pid" ]] && kill "$daemon_pid" 2>/dev/null || true
    wait 2>/dev/null || true
    exit "$rc"
}

cleanup() {
    local cleanup_timeout=30
    local daemon_pid=""
    local remaining

    if [[ -f "$pidfile" ]]; then
        daemon_pid="$(cat "$pidfile" 2>/dev/null || true)"
    fi

    if [[ -z "$daemon_pid" ]] || ! kill -0 "$daemon_pid" 2>/dev/null; then
        finish 0 "$pidfile" "$listener_pid" ""
    fi

    echo "fakesystemd: forwarding SIGTERM to PID $daemon_pid"
    kill -TERM "$daemon_pid" 2>/dev/null || true
    remaining="$cleanup_timeout"
    while kill -0 "$daemon_pid" 2>/dev/null; do
        if ((remaining <= 0)); then
            echo "fakesystemd: PID $daemon_pid did not exit, sending SIGKILL"
            kill -KILL "$daemon_pid" 2>/dev/null || true
            break
        fi
        sleep 1 &
        wait $! || true
        remaining=$((remaining - 1))
    done
    finish 0 "$pidfile" "$listener_pid" "$daemon_pid"
}

trap 'cleanup' SIGTERM SIGINT

notify_listener() {
    local pidfile="$1"

    socat -u UNIX-RECVFROM:"$NOTIFY_SOCKET",fork STDOUT | \
    while IFS= read -r line; do
        if [[ "$line" =~ MAINPID=([0-9]+) ]]; then
            echo "${BASH_REMATCH[1]}" > "${pidfile}.tmp"
            mv -f "${pidfile}.tmp" "$pidfile"
            echo "fakesystemd: MAINPID updated to ${BASH_REMATCH[1]}"
        fi
    done
}

main() {
    local grace_period=15
    local poll_interval=5
    local daemon_pid=""
    local daemon_rc
    local new_pid
    local timeout
    local grace_remaining

    rm -f "$NOTIFY_SOCKET"

    notify_listener "$pidfile" &
    listener_pid=$!

    timeout=50
    while [[ ! -S "$NOTIFY_SOCKET" ]] && ((timeout > 0)); do
        sleep 0.1
        timeout=$((timeout - 1))
    done
    if [[ ! -S "$NOTIFY_SOCKET" ]]; then
        echo "fakesystemd: timed out waiting for NOTIFY_SOCKET" >&2
        finish 1 "$pidfile" "$listener_pid" "$daemon_pid"
    fi

    "$@" &
    daemon_pid=$!
    echo "$daemon_pid" > "$pidfile"
    echo "fakesystemd: started $1 with PID $daemon_pid"

    while true; do
        sleep "$poll_interval" &
        wait $! || true

        if [[ -f "$pidfile" ]]; then
            daemon_pid="$(cat "$pidfile" 2>/dev/null || true)"
        fi

        if [[ -n "$daemon_pid" ]] && kill -0 "$daemon_pid" 2>/dev/null; then
            continue
        fi

        wait "$daemon_pid" 2>/dev/null
        daemon_rc=$?
        if ((daemon_rc == 0)); then
            echo "fakesystemd: daemon exited cleanly"
            finish 0 "$pidfile" "$listener_pid" "$daemon_pid"
        fi

        echo "fakesystemd: PID $daemon_pid died (rc=$daemon_rc), waiting grace period..."
        grace_remaining="$grace_period"
        while ((grace_remaining > 0)); do
            sleep 1 &
            wait $! || true
            grace_remaining=$((grace_remaining - 1))

            if [[ ! -f "$pidfile" ]]; then
                continue
            fi
            new_pid="$(cat "$pidfile" 2>/dev/null || true)"
            if [[ -z "$new_pid" || "$new_pid" == "$daemon_pid" ]]; then
                continue
            fi
            if ! kill -0 "$new_pid" 2>/dev/null; then
                continue
            fi

            daemon_pid="$new_pid"
            echo "fakesystemd: PID handoff to $daemon_pid"
            break
        done

        if ((grace_remaining <= 0)); then
            echo "fakesystemd: daemon did not recover, exiting"
            finish 1 "$pidfile" "$listener_pid" "$daemon_pid"
        fi
    done
}

main "$@"
