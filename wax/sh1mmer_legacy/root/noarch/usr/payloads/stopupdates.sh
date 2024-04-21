#!/bin/bash

set -e

get_largest_cros_blockdev() {
	local largest size dev_name tmp_size remo
	size=0
	for blockdev in /sys/block/*; do
		dev_name="${blockdev##*/}"
		echo "$dev_name" | grep -q '^\(loop\|ram\)' && continue
		tmp_size=$(cat "$blockdev"/size)
		remo=$(cat "$blockdev"/removable)
		if [ "$tmp_size" -gt "$size" ] && [ "${remo:-0}" -eq 0 ]; then
			case "$(sfdisk -l -o name "/dev/$dev_name" 2>/dev/null)" in
				*STATE*KERN-A*ROOT-A*KERN-B*ROOT-B*)
					largest="/dev/$dev_name"
					size="$tmp_size"
					;;
			esac
		fi
	done
	echo "$largest"
}

format_part_number() {
	echo -n "$1"
	echo "$1" | grep -q '[0-9]$' && echo -n p
	echo "$2"
}

cros_dev="$(get_largest_cros_blockdev)"
if [ -z "$cros_dev" ]; then
	echo "No CrOS SSD found on device!"
	exit 1
fi

echo "IMPORTANT!"
echo "THIS PAYLOAD WILL STOP YOUR CHROMEBOOK FROM UPDATING"
echo "IF YOU RECOVER YOUR CHROMEBOOK THESE CHANGES GO AWAY, MAKE SURE TO DO THIS AGAIN"
echo "Continue? (y/N)"
read -re action
case "$action" in
	[yY]) : ;;
	*) exit ;;
esac
local stateful=$(format_part_number "$cros_dev" 1)
local stateful_mnt=$(mktemp -d)
mount "$stateful" "$stateful_mnt"
mkdir -p "$stateful_mnt"/etc
printf "CHROMEOS_RELEASE_VERSION=9999.9999.9999.9999\nGOOGLE_RELEASE=9999.9999.9999.9999\n" >"$stateful_mnt"/etc/lsb-release
umount "$stateful_mnt"
rmdir "$stateful_mnt"
echo "Done."
