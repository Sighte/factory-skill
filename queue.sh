#!/usr/bin/env bash
# Schwerer Job (volle Python-Suite, docker build) über die Warteschlange aller Factory-Läufe.
# Aufruf (mit run_in_background starten, dann auf die Benachrichtigung warten):
#   bash queue.sh <L> <slug>-<job> <ausgabedatei> <befehl …>
# Wartet, bis das eigene Ticket vorne ist, hält es per Herzschlag frisch, räumt Tickets ohne
# Lebenszeichen seit 5 min weg, führt den Befehl aus, gibt das Ticket immer zurück und zeigt
# die letzten Zeilen der Ausgabe. Exit-Code = der des Befehls.
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
