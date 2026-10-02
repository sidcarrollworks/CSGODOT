#!/usr/bin/env bash
# Refuse partial texture DATA before cached images can hide missing resources.
# The impacts stage truncates this report each run, then appends Core's DATA.
set -euo pipefail

if [[ $# != 2 || ! -r "$1" || ! -r "$2" ]]; then
	echo "Usage: check_impact_texture_data.sh <textures.txt> <fresh textures_data.txt>" >&2
	exit 1
fi

expected="$(tr -d '\r' < "$1" | LC_ALL=C sort -u)"
if [[ -z "$expected" ]]; then
	echo "Impact texture manifest is empty." >&2
	exit 1
fi
decoded="$(tr -d '\r' < "$2" \
	| sed -nE 's/^\[[0-9]+\/[0-9]+\] ([^[:space:]]+\.vtex_c)$/\1/p' \
	| LC_ALL=C sort -u)"
missing="$(LC_ALL=C comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$decoded"))"
if [[ -n "$missing" ]]; then
	echo "Impact texture DATA is incomplete; cached images cannot satisfy these resources:" >&2
	printf '  %s\n' "$missing" >&2
	exit 1
fi
echo "impact texture DATA: $(printf '%s\n' "$expected" | wc -l | tr -d ' ') expected resources decoded"
