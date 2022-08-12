# arch-install-script
Attempt at automating an Arch UEFI installation with ext4fs. Mostly used to setup VMs, never tested to dual-boot because the script formats EFI parittion if not careful.
If the script exits because of accidental user input just unmount root partition `umount -R /mnt' or 'umount -lR /mnt' and rerun (skip formatting this time), most stuff will be overwritten (except for sucessfully created users)
