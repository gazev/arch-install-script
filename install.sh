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
			[sS]* ) echo -e "Skipping\n"; NO_FORMAT=1; return;; 
			[hH]* ) echo -e "If you do not wish for partitions to be formatted, formatted them manually for your liking and press 's' to skip this part.\nThe root partition will be formatted to ext4. Configuration for any other filesystems is not provided in the script nor accounted for.\nPress 'q' to quit";;
			*) echo "Invalid option"
		esac
	done
}

function format_partitions () {
	for(( i = 0; i < ${#DEVICES[@]}; ++i)); do
		case ${partitions[$i]} in
			EFI) 
				read -p "Do you wish to format EFI partition on /dev/${DEVICES[${partitions[$i]}]}? [y/N] " prompt
				if [[ "$prompt" =~ [Yy] ]]; then
					echo -e "\nFormatting /dev/${DEVICES[${partitions[$i]}]} to FAT32\n"
					mkfs.fat -F 32 /dev/${DEVICES[${partitions[$i]}]}
				else
					echo -e "\n${RED}Ignoring EFI partition${NC}\n"
				fi
				;;
			*[filesystem]) 
				echo -e "\nFormatting /dev/${DEVICES[${partitions[$i]}]} to ext4\n"
				mkfs.ext4 /dev/${DEVICES[${partitions[$i]}]}
				;;
			*[swap])
				if [[ ! "${DEVICES[${partitions[$i]}]}" ]]; then
					echo -e "No swap partition, skipping"
					continue
				else
					echo -e "\nSelecting swap partition on /dev/${DEVICES[${partitions[$i]}]}\n"; 
					mkswap /dev/${DEVICES[${partitions[$i]}]}
				fi
				;;
			*) echo "\nFailed to format ${DEVICES[${partitions[$i]}]}\n"
		esac
		echo ""
	done
}

function mount_devices () {
	mount /dev/${DEVICES["Linux filesystem"]} /mnt
	mount --mkdir /dev/${DEVICES["EFI"]} /mnt/boot/efi
	[[ "${DEVICES["Linux swap"]}" ]] && swapon /dev/${DEVICES["Linux swap"]}
	df -Th | head -n 1; df -Th | grep "${DEVICES["EFI"]}\|${DEVICES["Linux filesystem"]}"
	echo ""
	read -p "Confirm? [y/N] " prompt
	if [[ ! "$prompt" =~ [yY] ]]; then
		umount -R /mnt
		[[ "${DEVICES["Linux swap"]}" ]] && swapoff /dev/${DEVICES["Linux swap"]}
		echo -e "Devices unmounted\n"
		exit
	fi
	echo ""
}


# configure system clock
timedatectl set-ntp true

partitions=("EFI" "Linux filesystem" "Linux swap")
declare -A DEVICES=()

echo -e "${GREEN}Checking partitions${NC}" && get_mountpoints && prompt_mountpoints
[[ ! "$NO_FORMAT" ]] && echo -e "${GREEN}Formatting partitions${NC}" && format_partitions
echo -e "${GREEN}Mounting devices${NC}" && mount_devices

# the end of the script will configure i3-gaps, zsh, neovim, polybar, conky and rofi launchers
# ill ditch picom because it's overrated
pkgs=(\
	base linux linux-firmware base-devel grub efibootmgr os-prober\
	xorg-server lightdm lightdm-slick-greeter i3-gaps\
	sudo man-db zsh neovim openssh git tree\
	neofetch rofi polybar conky dunst\
)
# nvim is usually removed for VMs
	
# install packages
echo -e "${GREEN}Installing packages${NC}"
pacstrap /mnt ${pkgs[@]}
echo ""

# generating fstab
echo -e "${GREEN}Generating fstab${NC}"
genfstab -U /mnt > /mnt/etc/fstab
cat /mnt/etc/fstab

cat > /mnt/root/install2.sh <<'EOF'
#! /bin/bash

set -e

RED="\e[31m"
GREEN="\e[32m"
NC="\e[0m"

function generate_locales () {
	valid_locales=()
	for el in "${locales[@]}"; do
		if [[ $(grep "^#"$el".UTF-8" /etc/locale.gen 2> /dev/null) ]]; then
			echo "Found locale: $el"
			valid_locales+=("$el")
		else
			echo "Couldn't find or is already selected locale: $el"
		fi
	done

	for el in "${valid_locales[@]}"; do
		sed -i '/^#'$el'.UTF-8/s/^#//' /etc/locale.gen
	done

	# generate valid locales
	locale-gen

	# my default locales
	cat > /etc/locale.conf <<-zxy
		LANG=en_US.UTF-8
		LC_TIME=pt_PT.UTF-8
	zxy

	echo ""
}

# generate and configure locales (don't remove these two, only add if needed)
locales=("en_US" "pt_PT")
echo -e "${GREEN}Generating and configuring locales${NC}" && generate_locales

# set console keyboard layout
echo "KEYMAP=pt-latin1" > /etc/vconsole.conf

# configure hostname
read -p "Choose your hostname: " hostname
echo "$hostname" > /etc/hostname
echo ""

# root passwd
echo "Choose system's root password"
passwd

echo -e "\n${GREEN}Installing GRUB${NC}"
# configuring bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
# enable os-prober
sed -i '/GRUB_DISABLE_OS_PROBER=false/s/^#//' /etc/default/grub
# rerun grub-mkconfig with os-prober
grub-mkconfig -o /boot/grub/grub.cfg
# this is probably overkill idk
os-prober

# create user with sudo priviledge
echo ""
read -p "Choose your username: " username
[[ $(grep zsh /etc/shells) ]] && shell="zsh" || shell="bash"
useradd -m -G wheel -s /bin/"$shell" "$username"
echo "Choose your password"
passwd "$username"
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > etc/sudoers.d/install_script

echo -e "${GREEN}Basic installation complete${NC}\n"
neofetch
echo -e "${GREEN}Run the second script to setup dotfiles${NC}\n"

echo -e "I am done! Reboot recommended!"
EOF

chmod 777 /mnt/root/install2.sh

# changing root into new system
arch-chroot /mnt /root/install2.sh

exit 0
