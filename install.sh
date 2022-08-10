#! /bin/bash

set -e

RED="\e[31m"
GREEN="\e[32m"
NC="\e[0m"

# check if in UEFI mode
[[ ! $(ls /sys/firmware/efi/efivars 2> /dev/null) ]] && echo "Machine not booted in UEFI mode!" && exit
# check for internet connection
[[ ! $(ping -w 1 -c 1 8.8.8.8 2> /dev/null) ]] && echo "Machine is not connected to the internet, internet connection is required" && exit
	

function get_mountpoints () {
	for ((i = 0; i < ${#partitions[@]}; ++i))
	do
		DEVICES[${partitions[$i]}]=$(fdisk -l | grep "${partitions[$i]}" | awk -F '/| ' '{print $3}')
		if [[ ! ${DEVICES[${partitions[$i]}]} ]]; then
			if [[ $i -eq 2 ]]; then
				echo "No swap partition detected!"
			else
				echo "No ${partitions[$i]} partition found!"
				echo "Please create your partitions first!"
				exit
			fi
		else
			echo "${partitions[$i]}"
			lsblk -f | grep $(fdisk -l | grep "${partitions[$i]}" | awk -F '/| ' '{print $3}') | awk '{print "Device: " substr($1, 3)"\nFS: " $2"\nMountpoint: " $7}' | column -t
		fi
		echo ""
	done
}

function prompt_mountpoints () {
	echo -ne "Filesystems will be overwritten and devices will be remounted, procced with care! (press 'h' for more info)\nConfirm [y/N] "
	while true; do
		read input
		echo ""
		case $input in
			[yY]* ) break;;
			[nN]* ) echo -e "I am a dumb script, if these are not the desired partitions please press 'h'";; 
			[qQ]* ) exit;;
			[hH]* ) echo -e "If you do not wish for partitions to be formatted or remounted comment lines __ in the script and manually introduce devices path on lines __.\n\
The root partition will be formatted to ext4. Configuration for any other filesystems is not provided in the script nor accounted for.\n\nPress 'q' to quit";;
			*) echo "Invalid option"
		esac
	done
}

function format_partitions () {
	for(( i = 0; i < ${#DEVICES[@]}; ++i)); do
		case ${partitions[$i]} in
			EFI) 
				# check if efi partition is empty (check for dual boot)
				read -p "Do you wish to format EFI partition on /dev/${DEVICES[${partitions[$i]}]}? [y/N] " prompt
				if [[ "$prompt" =~ [Yy] ]]; then
					echo -e "\nFormatting /dev/${DEVICES[${partitions[$i]}]} to FAT32\n"
				else
					echo -e "\n${RED}Ignoring EFI partition${NC}\n"
				fi
			;;
			*[filesystem]) echo -e "Formatting /dev/${DEVICES[${partitions[$i]}]} to ext4\n" ;;
			*[swap])
				if [[ ! "${DEVICES[${partitions[$i]}]}" ]]; then
					echo -e "No swap partition, skipping\n"
					continue
				else
					echo -e "Selecting swap partition on /dev/${DEVICES[${partitions[$i]}]}\n"; 
				fi
			;;
			*) echo "Failed to format ${DEVICES[${partitions[$i]}]}"
		esac
	done
}

function mount_devices () {
	#echo "/dev/${DEVICES["Linux filesystem"]}"
	#echo "/dev/${DEVICES["EFI"]}"
	#[[ "${DEVICES["Linux swap"]}" ]] && echo "/dev/${DEVICES["Linux swap"]}"
	df -Th | head -n 1; df -Th | grep "${DEVICES["EFI"]}\|${DEVICES["Linux filesystem"]}"
	read -p "Confirm? [y/N] " prompt
	if [[ ! "$prompt" =~ [yY] ]]; then
		echo -e "\nUnmounting"
		exit
	fi
	echo ""
}

# configure system clock
#timedatectl set-ntp true

partitions=("EFI" "Linux filesystem" "Linux swap")
declare -A DEVICES=()

echo -e "${GREEN}Checking partitions${NC}" && get_mountpoints && prompt_mountpoints
echo -e "${GREEN}Formatting partitions${NC}" && format_partitions
echo -e "${GREEN}Mounting completed${NC}" && mount_devices
echo -e "${GREEN}ITS SHOWTIME BABY${NC}" && neofetch


