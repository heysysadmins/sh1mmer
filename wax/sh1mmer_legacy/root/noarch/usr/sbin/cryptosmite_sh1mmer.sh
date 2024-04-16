#!/bin/bash

set -eE

DEST_PATH=/opt/cryptosmite
EXE="$DEST_PATH"/cryptosmite.sh

if ! [ -f "$EXE" ]; then
	echo "$EXE not found!"
	exit 1
fi

chmod +x "$EXE"
cd "$DEST_PATH"
"$EXE" "$@"
