#!/bin/bash

# Define colors for a more visible theme
export NEWT_COLORS='
root=,black
border=white,black
window=,black
shadow=,black
title=white,black
button=white,black
actbutton=white,black
'

# Default image directory
default_image_dir="images"

# Fastboot command
fastboot=bin/fastboot

# Function to show a message
show_message() {
    whiptail --title "$1" --msgbox "$2" 10 60
}

# Function for input dialog
get_input() {
    whiptail --title "$1" --inputbox "$2" 10 60 "$3" 3>&1 1>&2 2>&3
}

# Function for confirmation dialog
confirm_action() {
    whiptail --title "$1" --yesno "$2" 10 60
    return $?
}

# Function to check if a command succeeded
check_success() {
    if [ $1 -ne 0 ]; then
        show_message "Error" "$2"
        exit 1
    fi
}

# Function to check if the image file exists
check_file() {
    if [ ! -f "$1/$2.img" ]; then
        show_message "Error" "Image file for $2 not found in directory $1!"
        exit 1
    fi
}

# Function to flash images
flash_images() {
    DIR=$1
    SLOT=$2
    IMAGES=$3
    for i in $IMAGES; do
        check_file $DIR $i
        $fastboot flash $SLOT $i $i.img
        check_success $? "Flashing $i failed!"
    done
}

# Ask user for the directory containing the image files
image_dir=$(get_input "Image Directory" "Enter the directory containing the image files:" $default_image_dir)
if [ -z "$image_dir" ]; then
    image_dir=$default_image_dir
fi

# Check for fastboot executable
if [ ! -f $fastboot ] || [ ! -x $fastboot ]; then
    show_message "Error" "Fastboot cannot be executed, exiting"
    exit 1
fi

# Initial message
show_message "Welcome" "Pong Fastboot ROM Flasher ALPHA"

# Change active slot
if confirm_action "Change Slot" "Change active slot to A?"; then
    $fastboot --set-active=a
    check_success $? "Setting active slot to A failed!"
fi

# Format data
if confirm_action "Format Data" "Wipe Data?"; then
    $fastboot erase userdata
    check_success $? "Erasing userdata failed!"
    $fastboot erase metadata
    check_success $? "Erasing metadata failed!"
fi

# Flash images on both slots
if confirm_action "Flash Slots" "Flash images on both slots?"; then
    SLOT="--slot=all"
else
    SLOT=""
fi

# Flash boot/recovery images
flash_images "$image_dir" "$SLOT" "boot vendor_boot dtbo recovery"

# Reboot to fastbootd
$fastboot reboot fastboot
check_success $? "Rebooting to fastbootd failed!"

# Flash firmware
flash_images "$image_dir" "$SLOT" "abl aop aop_config bluetooth cpucp devcfg dsp featenabler hyp imagefv keymaster modem multiimgoem multiimgqti qupfw qweslicstore shrm tz uefi uefisecapp xbl xbl_config xbl_ramdump"

# Flash vbmeta
if confirm_action "Flash VBMETA" "Disable android verified boot?"; then
    $fastboot flash $SLOT vbmeta --disable-verity --disable-verification vbmeta.img
else
    $fastboot flash $SLOT vbmeta vbmeta.img
fi
check_success $? "Flashing vbmeta failed!"

# Flash logical partitions
if confirm_action "Flash Logical" "Flash logical partition images?"; then
    for i in system system_ext product vendor vendor_dlkm odm; do
        for s in a b; do
            $fastboot delete-logical-partition ${i}_${s}-cow
            check_success $? "Deleting ${i}_${s}-cow failed!"
            $fastboot delete-logical-partition ${i}_${s}
            check_success $? "Deleting ${i}_${s} failed!"
            $fastboot create-logical-partition ${i}_${s} 1
            check_success $? "Creating ${i}_${s} failed!"
        done
        $fastboot flash $i $i.img
        check_success $? "Flashing $i failed!"
    done
fi

# Flash vbmeta system/vendor
flash_images "$image_dir" "$SLOT" "vbmeta_system vbmeta_vendor"

# Reboot
if confirm_action "Reboot" "Reboot to system?"; then
    $fastboot reboot
    check_success $? "Rebooting failed!"
fi

# Final message
show_message "Done" "Stock firmware restored. You may now optionally re-lock the bootloader if you haven't disabled android verified boot."
