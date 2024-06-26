#!/usr/bin/env bash

HOME_DIR="/home/pi"
JUKEBOX_HOME_DIR="${HOME_DIR}/RPi-Jukebox-RFID"
BUTTONS_USB_ENCODER_DIR="${JUKEBOX_HOME_DIR}/components/controls/buttons_usb_encoder"

question() {
    local question=$1
    read -p "${question} (Y/n)? " choice
    case "$choice" in
      [nN][oO]|[nN]) exit 0;;
      * ) ;;
    esac
}

if [ "$PWD" != "$JUKEBOX_HOME_DIR" ]
then
    printf "Please execute script from %s directory\n" $JUKEBOX_HOME_DIR
    exit 0
fi

printf "Please make sure that the Buttons USB Encoder and the buttons are connected before continuing...\n"
question "Continue"

# make files executable
sudo chmod +x "${BUTTONS_USB_ENCODER_DIR}"/register_buttons_usb_encoder.py
sudo chmod +x "${BUTTONS_USB_ENCODER_DIR}"/buttons_usb_encoder.py
sudo chmod +x "${BUTTONS_USB_ENCODER_DIR}"/map_buttons_usb_encoder.py

# choose buttons usb encoder device
"${BUTTONS_USB_ENCODER_DIR}"/register_buttons_usb_encoder.py

# setup buttons
"${BUTTONS_USB_ENCODER_DIR}"/map_buttons_usb_encoder.py

printf "\nStart phoniebox-buttons-usb-encoder service...\n"
sudo cp -v "${BUTTONS_USB_ENCODER_DIR}"/phoniebox-buttons-usb-encoder.service.sample /etc/systemd/system/phoniebox-buttons-usb-encoder.service
sudo systemctl start phoniebox-buttons-usb-encoder.service
sudo systemctl enable phoniebox-buttons-usb-encoder.service

printf "Done.\n"
