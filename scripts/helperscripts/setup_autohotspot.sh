#!/usr/bin/env bash

JUKEBOX_HOME_DIR="$1"
AUTOHOTSPOTconfig="$2"
AUTOHOTSPOTssid="$3"
AUTOHOTSPOTcountryCode="$4"
AUTOHOTSPOTpass="$5"
AUTOHOTSPOTip="$6"
if [[ "$#" -lt 2 || ( "${AUTOHOTSPOTconfig}" != "NO" && "${AUTOHOTSPOTconfig}" != "YES") || ( "${AUTOHOTSPOTconfig}" == "YES" && "$#" -ne 6 ) ]] ; then
    echo "error: missing paramter"
    echo "usage: ./setup_autohotspot.sh <jukeboxDir> <activation=YES> <ssid> <countryCode (e.g. DE, GB, CZ, ...)> <password (8..63 characters)> <ipAdress>"
    echo "or"
    echo "usage: ./setup_autohotspot.sh <jukeboxDir> <activation=NO>"
    exit 1
fi

_get_last_ip_segment() {
    local ip="$1"
    echo $ip | cut -d'.' -f1-3
}

# create flag file if files does no exist (*.remove) or copy present conf to backup file (*.orig)
# to correctly handling de-/activation of corresponding feature
config_file_backup() {
    local config_file="$1"
    local config_flag_file="${config_file}.remove"
    local config_orig_file="${config_file}.orig"
    if [ ! -f "${config_file}" ]; then
        sudo touch "${config_flag_file}"
    elif [ ! -f "${config_orig_file}" ] && [ ! -f "${config_flag_file}" ]; then
        sudo cp "${config_file}" "${config_orig_file}"
    fi
}

# revert config files backed up with `config_file_backup`
config_file_revert() {
    local config_file="$1"
    local config_flag_file="${config_file}.remove"
    local config_orig_file="${config_file}.orig"
    if [ -f "${config_flag_file}" ]; then
        sudo rm "${config_flag_file}" "${config_file}"
    elif [ -f "${config_orig_file}" ]; then
        sudo mv "${config_orig_file}" "${config_file}"
    fi
}

apt_get="sudo apt-get -qq --yes"

systemd_dir="/etc/systemd/system"

autohotspot_script="/usr/bin/autohotspot"
autohotspot_service_daemon="autohotspot-daemon.service"
autohotspot_service_daemon_path="${systemd_dir}/${autohotspot_service_daemon}"
autohotspot_service="autohotspot.service"
autohotspot_service_path="${systemd_dir}/${autohotspot_service}"
autohotspot_timer="autohotspot.timer"
autohotspot_timer_path="${systemd_dir}/${autohotspot_timer}"

interfaces_conf_file="/etc/network/interfaces"
dnsmasq_conf=/etc/dnsmasq.conf
hostapd_conf=/etc/hostapd/hostapd.conf
hostapd_deamon=/etc/default/hostapd
dhcpcd_conf=/etc/dhcpcd.conf
dhcpcd_conf_nohook_wpa_supplicant="nohook wpa_supplicant"
networkManager_connections_path="/etc/NetworkManager/system-connections"

wifi_interface=wlan0
ip_without_last_segment=$(_get_last_ip_segment $AUTOHOTSPOTip)
autohotspot_profile="Phoniebox_Hotspot"

source "${JUKEBOX_HOME_DIR}"/scripts/helperscripts/inc.helper.sh
source "${JUKEBOX_HOME_DIR}"/scripts/helperscripts/inc.networkHelper.sh

_install_autohotspot_dhcpcd() {
    # adapted from https://www.raspberryconnect.com/projects/65-raspberrypi-hotspot-accesspoints/158-raspberry-pi-auto-wifi-hotspot-switch-direct-connection

    # required packages
    call_with_args_from_file "${JUKEBOX_HOME_DIR}"/packages-autohotspot_dhcpcd.txt ${apt_get} install
    sudo systemctl unmask hostapd
    sudo systemctl disable hostapd
    sudo systemctl stop hostapd
    sudo systemctl unmask dnsmasq
    sudo systemctl disable dnsmasq
    sudo systemctl stop dnsmasq

    # configure interface conf
    config_file_backup "${interfaces_conf_file}"
    sudo rm "${interfaces_conf_file}"
    sudo touch "${interfaces_conf_file}"

    # configure DNS
    config_file_backup "${dnsmasq_conf}"

    sudo cp "${JUKEBOX_HOME_DIR}"/misc/sampleconfigs/autohotspot/dhcpcd/dnsmasq.conf "${dnsmasq_conf}"
    sudo sed -i "s|%WIFI_INTERFACE%|$(escape_for_sed "${wifi_interface}")|g" "${dnsmasq_conf}"
    sudo sed -i "s|%IP_WITHOUT_LAST_SEGMENT%|$(escape_for_sed "${ip_without_last_segment}")|g" "${dnsmasq_conf}"
    sudo chown root:root "${dnsmasq_conf}"
    sudo chmod 644 "${dnsmasq_conf}"

    # configure hostapd conf
    config_file_backup "${hostapd_conf}"

    sudo cp "${JUKEBOX_HOME_DIR}"/misc/sampleconfigs/autohotspot/dhcpcd/hostapd.conf "${hostapd_conf}"
    sudo sed -i "s|%WIFI_INTERFACE%|$(escape_for_sed "${wifi_interface}")|g" "${hostapd_conf}"
    sudo sed -i "s|%AUTOHOTSPOTssid%|$(escape_for_sed "${AUTOHOTSPOTssid}")|g" "${hostapd_conf}"
    sudo sed -i "s|%AUTOHOTSPOTpass%|$(escape_for_sed "${AUTOHOTSPOTpass}")|g" "${hostapd_conf}"
    sudo sed -i "s|%AUTOHOTSPOTcountryCode%|$(escape_for_sed "${AUTOHOTSPOTcountryCode}")|g" "${hostapd_conf}"
    sudo chown root:root "${hostapd_conf}"
    sudo chmod 644 "${hostapd_conf}"

    # configure hostapd daemon
    config_file_backup "${hostapd_deamon}"

    sudo cp "${JUKEBOX_HOME_DIR}"/misc/sampleconfigs/autohotspot/dhcpcd/hostapd "${hostapd_deamon}"
    sudo sed -i "s|%HOSTAPD_CONF%|$(escape_for_sed "${hostapd_conf}")|g" "${hostapd_deamon}"
    sudo chown root:root "${hostapd_deamon}"
    sudo chmod 644 "${hostapd_deamon}"

    # configure dhcpcd conf
    config_file_backup "${dhcpcd_conf}"
    if [ ! -f "${dhcpcd_conf}" ]; then
        sudo touch "${dhcpcd_conf}"
        sudo chown root:netdev "${dhcpcd_conf}"
        sudo chmod 664 "${dhcpcd_conf}"
    fi

    if [[ ! $(grep -w "${dhcpcd_conf_nohook_wpa_supplicant}" ${dhcpcd_conf}) ]]; then
        echo "${dhcpcd_conf_nohook_wpa_supplicant}" | sudo tee -a "${dhcpcd_conf}" > /dev/null
    fi

    # create service to trigger hotspot
    sudo cp "${JUKEBOX_HOME_DIR}"/misc/sampleconfigs/autohotspot/dhcpcd/autohotspot "${autohotspot_script}"
    sudo sed -i "s|%WIFI_INTERFACE%|$(escape_for_sed "${wifi_interface}")|g" "${autohotspot_script}"
    sudo sed -i "s|%AUTOHOTSPOT_IP%|$(escape_for_sed "${AUTOHOTSPOTip}")|g" "${autohotspot_script}"
    sudo sed -i "s|%AUTOHOTSPOT_SERVICE_DAEMON%|$(escape_for_sed "${autohotspot_service_daemon}")|g" "${autohotspot_script}"
    sudo chmod +x "${autohotspot_script}"

    sudo cp "${JUKEBOX_HOME_DIR}"/misc/sampleconfigs/autohotspot/dhcpcd/autohotspot-daemon.service "${autohotspot_service_daemon_path}"
    sudo sed -i "s|%WIFI_INTERFACE%|$(escape_for_sed "${wifi_interface}")|g" "${autohotspot_service_daemon_path}"
    sudo chown root:root "${autohotspot_service_daemon_path}"
    sudo chmod 644 "${autohotspot_service_daemon_path}"

    sudo cp "${JUKEBOX_HOME_DIR}"/misc/sampleconfigs/autohotspot/dhcpcd/autohotspot.service "${autohotspot_service_path}"
    sudo sed -i "s|%AUTOHOTSPOT_SCRIPT%|$(escape_for_sed "${autohotspot_script}")|g" "${autohotspot_service_path}"
    sudo chown root:root "${autohotspot_service_path}"
    sudo chmod 644 "${autohotspot_service_path}"

    sudo cp "${JUKEBOX_HOME_DIR}"/misc/sampleconfigs/autohotspot/dhcpcd/autohotspot.timer "${autohotspot_timer_path}"
    sudo sed -i "s|%AUTOHOTSPOT_SERVICE%|$(escape_for_sed "${autohotspot_service}")|g" "${autohotspot_timer_path}"
    sudo chown root:root "${autohotspot_timer_path}"
    sudo chmod 644 "${autohotspot_timer_path}"

    sudo systemctl enable "${autohotspot_service_daemon}"
    sudo systemctl disable "${autohotspot_service}"
    sudo systemctl enable "${autohotspot_timer}"
}

_uninstall_autohotspot_dhcpcd() {
    # clear autohotspot configurations made from past installation

    # remove crontab entry and script from old version installations
    crontab_user=$(crontab -l 2>/dev/null)
    if [[ ! -z "${crontab_user}" && $(echo "${crontab_user}" | grep -w "${autohotspot_script}") ]]; then
        echo "${crontab_user}" | sed "s|^.*\s${autohotspot_script}\s.*$||g" | crontab -
    fi

    # stop services and clear services
    if systemctl list-unit-files "${autohotspot_service}" >/dev/null 2>&1 ; then
        sudo systemctl stop hostapd
        sudo systemctl stop dnsmasq
        sudo systemctl stop "${autohotspot_timer}"
        sudo systemctl disable "${autohotspot_timer}"
        sudo systemctl stop "${autohotspot_service}"
        sudo systemctl disable "${autohotspot_service}"
        sudo systemctl disable "${autohotspot_service_daemon}"
        sudo rm "${autohotspot_timer_path}"
        sudo rm "${autohotspot_service_path}"
        sudo rm "${autohotspot_service_daemon_path}"
    fi

    if [ -f "${autohotspot_script}" ]; then
        sudo rm "${autohotspot_script}"
    fi

    # remove config files
    config_file_revert "${dnsmasq_conf}"
    config_file_revert "${hostapd_conf}"
    config_file_revert "${hostapd_deamon}"
    config_file_revert "${dhcpcd_conf}"
    config_file_revert "${interfaces_conf_file}"
}

_install_autohotspot_NetworkManager() {
    # required packages
    call_with_args_from_file "${JUKEBOX_HOME_DIR}"/packages-autohotspot_NetworkManager.txt ${apt_get} install

    # configure interface conf
    config_file_backup "${interfaces_conf_file}"
    sudo rm "${interfaces_conf_file}"
    sudo touch "${interfaces_conf_file}"

    # create service to trigger hotspot
    sudo cp "${JUKEBOX_HOME_DIR}"/misc/sampleconfigs/autohotspot/NetworkManager/autohotspot "${autohotspot_script}"
    sudo sed -i "s|%WIFI_INTERFACE%|$(escape_for_sed "${wifi_interface}")|g" "${autohotspot_script}"
    sudo sed -i "s|%AUTOHOTSPOT_PROFILE%|$(escape_for_sed "${autohotspot_profile}")|g" "${autohotspot_script}"
    sudo sed -i "s|%AUTOHOTSPOT_SSID%|$(escape_for_sed "${AUTOHOTSPOTssid}")|g" "${autohotspot_script}"
    sudo sed -i "s|%AUTOHOTSPOT_PASSWORD%|$(escape_for_sed "${AUTOHOTSPOTpass}")|g" "${autohotspot_script}"
    sudo sed -i "s|%AUTOHOTSPOT_IP%|$(escape_for_sed "${AUTOHOTSPOTip}")|g" "${autohotspot_script}"
    sudo sed -i "s|%IP_WITHOUT_LAST_SEGMENT%|$(escape_for_sed "${ip_without_last_segment}")|g" "${autohotspot_script}"
    sudo sed -i "s|%AUTOHOTSPOT_TIMER_NAME%|$(escape_for_sed "${autohotspot_timer}")|g" "${autohotspot_script}"
    sudo chmod +x "${autohotspot_script}"

    sudo cp "${JUKEBOX_HOME_DIR}"/misc/sampleconfigs/autohotspot/NetworkManager/autohotspot.service "${autohotspot_service_path}"
    sudo sed -i "s|%AUTOHOTSPOT_SCRIPT%|$(escape_for_sed "${autohotspot_script}")|g" "${autohotspot_service_path}"
    sudo chown root:root "${autohotspot_service_path}"
    sudo chmod 644 "${autohotspot_service_path}"

    sudo cp "${JUKEBOX_HOME_DIR}"/misc/sampleconfigs/autohotspot/NetworkManager/autohotspot.timer "${autohotspot_timer_path}"
    sudo sed -i "s|%AUTOHOTSPOT_SERVICE%|$(escape_for_sed "${autohotspot_service}")|g" "${autohotspot_timer_path}"
    sudo chown root:root "${autohotspot_timer_path}"
    sudo chmod 644 "${autohotspot_timer_path}"


    sudo systemctl unmask "${autohotspot_service}"
    sudo systemctl unmask "${autohotspot_timer}"
    sudo systemctl disable "${autohotspot_service}"
    sudo systemctl enable "${autohotspot_timer}"
}

_uninstall_autohotspot_NetworkManager() {
    # clear autohotspot configurations made from past installation

    # stop services and clear services
    if systemctl list-unit-files "${autohotspot_service}" >/dev/null 2>&1 ; then
        sudo systemctl stop "${autohotspot_timer}"
        sudo systemctl disable "${autohotspot_timer}"
        sudo systemctl stop "${autohotspot_service}"
        sudo systemctl disable "${autohotspot_service}"
        sudo rm "${autohotspot_service_path}"
        sudo rm "${autohotspot_timer_path}"
    fi

    if [ -f "${autohotspot_script}" ]; then
        sudo rm "${autohotspot_script}"
    fi

    sudo rm -f "${networkManager_connections_path}/${autohotspot_profile}*"

    # remove config files
    config_file_revert "${interfaces_conf_file}"
}


if [ "${AUTOHOTSPOTconfig}" == "YES" ]; then
    if [[ $(is_dhcpcd_enabled) == true ]]; then
        _install_autohotspot_dhcpcd
    fi
    if [[ $(is_NetworkManager_enabled) == true ]]; then
         _install_autohotspot_NetworkManager
    fi
else
    if [[ $(is_dhcpcd_enabled) == true ]]; then
        _uninstall_autohotspot_dhcpcd
    fi
    if [[ $(is_NetworkManager_enabled) == true ]]; then
        _uninstall_autohotspot_NetworkManager
    fi
fi
