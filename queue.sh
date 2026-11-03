#!/usr/bin/env bash
# Heavy job (full Python suite, docker build) via the queue shared by all factory runs.
# Usage (start with run_in_background, then wait for the notification):
#   bash queue.sh <L> <slug>-<job> <output-file> <command …>
# Waits until its own ticket is at the front, keeps it fresh via heartbeat, clears away tickets with
# no sign of life for 5 min, runs the command, always releases the ticket and shows
# the last lines of the output. Exit code = that of the command.
set -u
L=$1 NAME=$2 OUT=$3; shift 3
Q="$L/queue"; mkdir -p "$Q"
T=$(date +%s%N)-$NAME; touch "$Q/$T"
trap 'rm -f "${Q:?}/${T:?}"' EXIT
until touch "$Q/$T"; find "$Q" -type f -mmin +5 -delete; [ "$(ls "$Q" | sort | head -1)" = "$T" ]; do sleep 10; done
( while sleep 60; do touch "$Q/$T" 2>/dev/null || break; done ) & HB=$!
"$@" > "$OUT" 2>&1; RC=$?
kill $HB 2>/dev/null
tail -15 "$OUT"
exit $RC
