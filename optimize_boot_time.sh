#!/usr/bin/env bash

# Reference: https://panther.software/configuration-code/raspberry-pi-3-4-faster-boot-time-in-few-easy-steps/

OPTIMIZE_DHCP_CONF="/etc/dhcpcd.conf"
OPTIMIZE_BOOT_CMDLINE_OPTIONS="consoleblank=1 logo.nologo quiet loglevel=0 plymouth.enable=0 vt.global_cursor_default=0 plymouth.ignore-serial-consoles splash fastboot noatime nodiratime noram"
OPTIMIZE_BOOT_CMDLINE_OPTIONS_IPV6="ipv6.disable=1"
OPTIMIZE_DHCP_CONF_HEADER="## Jukebox DHCP Config"
OPTIMIZE_BOOT_CONF_HEADER="## Jukebox Boot Config"

DISABLE_BLUETOOTH="true"
DISABLE_IPv6="false"
ENABLE_STATIC_IP="true"
DISABLE_BOOT_LOGS_PRINT="true"

CURRENT_ROUTE=$(ip route get 8.8.8.8)
CURRENT_GATEWAY=$(echo "${CURRENT_ROUTE}" | awk '{ print $3; exit }')
CURRENT_INTERFACE=$(echo "${CURRENT_ROUTE}" | awk '{ print $5; exit }')
CURRENT_IP_ADDRESS=$(echo "${CURRENT_ROUTE}" | awk '{ print $7; exit }')

log() {
  local message="$1"
  echo -e "$message"
}

print_lc() {
  local message="$1"
  echo -e "$message"
}

calc_runtime_and_print() {
  runtime=$(($2-$1))
  ((h=runtime/3600))
  ((m=(runtime%3600)/60))
  ((s=runtime%60))

  echo "Done in ${h}h ${m}m ${s}s"
}

run_with_log_frame() {
    local time_start=$(date +%s);
    local description="$2"
    log "\n\n"
    log "#########################################################"
    print_lc "${description}"

    $1; # Executes the function passed as an argument

    local done_in=$(calc_runtime_and_print "$time_start" "$(date +%s)")
    log "\n${done_in} - ${description}"
    log "#########################################################"
}

is_raspbian() {
    if [[ $( . /etc/os-release; printf '%s\n' "$ID"; ) == *"raspbian"* ]]; then
        echo true
    else
        echo false
    fi
}

get_debian_version_number() {
    source /etc/os-release
    echo "$VERSION_ID"
}

_get_boot_file_path() {
    local filename="$1"
    if [ "$(is_raspbian)" = true ]; then
        local debian_version_number=$(get_debian_version_number)

        # Bullseye and lower
        if [ "$debian_version_number" -le 11 ]; then
            echo "/boot/${filename}"
        # Bookworm and higher
        elif [ "$debian_version_number" -ge 12 ]; then
            echo "/boot/firmware/${filename}"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

get_boot_config_path() {
    echo $(_get_boot_file_path "config.txt")
}

get_boot_cmdline_path() {
    echo $(_get_boot_file_path "cmdline.txt")
}

_add_options_to_cmdline() {
    local options="$1"

    local cmdlineFile=$(get_boot_cmdline_path)
    if [ ! -s "${cmdlineFile}" ];then
        sudo tee "${cmdlineFile}" <<-EOF
${options}
EOF
    else
        for option in $options
        do
            if ! grep -qiw "$option" "${cmdlineFile}" ; then
                sudo sed -i "s/$/ $option/" "${cmdlineFile}"
            fi
        done
    fi
}

# Generic emergency error handler that exits the script immediately
# Print additional custom message if passed as first argument
# Examples:
#   a command || exit_on_error
#   a command || exit_on_error "Execution of command failed"
exit_on_error () {
  print_lc "\n****************************************"
  print_lc "ERROR OCCURRED!
A non-recoverable error occurred.
Check install log for details:"
  print_lc "$INSTALLATION_LOGFILE"
  print_lc "****************************************"
  if [[ -n $1 ]]; then
    print_lc "$1"
    print_lc "****************************************"
  fi
  log "Abort!"
  exit 1
}

_get_service_enablement() {
    local service="$1"
    local option="${2:+$2 }" # optional, dont't quote in 'systemctl' call!

    if [[ -z "${service}" ]]; then
        exit_on_error "ERROR: at least one parameter value is missing!"
    fi

    local actual_enablement=$(systemctl is-enabled ${option}${service} 2>/dev/null)

    echo "$actual_enablement"
}

is_service_enabled() {
    local service="$1"
    local option="$2"
    local actual_enablement=$(_get_service_enablement $service $option)

    if [[ "$actual_enablement" == "enabled" ]]; then
        echo true
    else
        echo false
    fi
}

is_dhcpcd_enabled() {
    echo $(is_service_enabled "dhcpcd.service")
}

is_NetworkManager_enabled() {
    echo $(is_service_enabled "NetworkManager.service")
}

get_nm_active_profile()
{
	local active_profile=$(nmcli -g DEVICE,CONNECTION device status | grep "^${CURRENT_INTERFACE}" | cut -d':' -f2)
	echo "$active_profile"
}

### Verify helpers
print_verify_installation() {
    log "\n
  -------------------------------------------------------
  Check installation
"
}

verify_optional_service_enablement() {
    local service="$1"
    local desired_enablement="$2"
    local option="$3"
    log "  Verify service ${option}${service} is ${desired_enablement}"

    if [[ -z "${service}" || -z "${desired_enablement}" ]]; then
        exit_on_error "ERROR: at least one parameter value is missing!"
    fi

    local actual_enablement=$(_get_service_enablement $service $option)
    if [[ -z "${actual_enablement}" ]]; then
        log "  INFO: optional service ${option}${service} is not installed."
    elif [[ "${actual_enablement}" == "static" ]]; then
        log "  INFO: optional service ${option}${service} is set static."
    elif [[ ! "${actual_enablement}" == "${desired_enablement}" ]]; then
        exit_on_error "ERROR: service ${option}${service} is not ${desired_enablement} (state: ${actual_enablement})."
    fi
    log "  CHECK"
}

verify_file_contains_string() {
    local string="$1"
    local file="$2"
    log "  Verify '${string}' found in '${file}'"

    if [[ -z "${string}" || -z "${file}" ]]; then
        exit_on_error "ERROR: at least one parameter value is missing!"
    fi

    if [[ ! $(sudo grep -iw "${string}" "${file}") ]]; then
        exit_on_error "ERROR: '${string}' not found in '${file}'"
    fi
    log "  CHECK"
}

verify_file_does_not_contain_string() {
    local string="$1"
    local file="$2"
    log "  Verify '${string}' not found in '${file}'"

    if [[ -z "${string}" || -z "${file}" ]]; then
        exit_on_error "ERROR: at least one parameter value is missing!"
    fi

    if grep -iq "${string}" "${file}"; then
        exit_on_error "ERROR: '${string}' found in '${file}'"
    fi
    log "  CHECK"
}

verify_file_contains_string_once() {
    local string="$1"
    local file="$2"
    log "  Verify '${string}' found in '${file}'"

    if [[ -z "${string}" || -z "${file}" ]]; then
        exit_on_error "ERROR: at least one parameter value is missing!"
    fi

    local file_contains_string_count=$(sudo grep -oiw "${string}" "${file}" | wc -l)
    if [ "$file_contains_string_count" -lt 1 ]; then
        exit_on_error "ERROR: '${string}' not found in '${file}'"
    elif [ "$file_contains_string_count" -gt 1 ]; then
        exit_on_error "ERROR: '${string}' found more than once in '${file}'"
    fi
    log "  CHECK"
}


_optimize_disable_irrelevant_services() {
  log "  Disable keyboard-setup.service"
  sudo systemctl disable keyboard-setup.service

  log "  Disable triggerhappy.service"
  sudo systemctl disable triggerhappy.service
  sudo systemctl disable triggerhappy.socket

  log "  Disable raspi-config.service"
  sudo systemctl disable raspi-config.service

  log "  Disable apt-daily.service & apt-daily-upgrade.service"
  sudo systemctl disable apt-daily.service
  sudo systemctl disable apt-daily-upgrade.service
  sudo systemctl disable apt-daily.timer
  sudo systemctl disable apt-daily-upgrade.timer
}

_optimize_handle_bluetooth() {
  if [ "$DISABLE_BLUETOOTH" = true ] ; then
    print_lc "  Disable bluetooth"
    sudo systemctl disable hciuart.service
    sudo systemctl disable bluetooth.service
  fi
}

_optimize_static_ip() {
    # Static IP Address and DHCP optimizations
    if [[ $(is_dhcpcd_enabled) == true ]]; then
        if [ "$ENABLE_STATIC_IP" = true ] ; then
            print_lc "  Set static IP address"
            if grep -q "${OPTIMIZE_DHCP_CONF_HEADER}" "$OPTIMIZE_DHCP_CONF"; then
                log "    Skipping. Already set up!"
            else
                # DHCP has not been configured
                log "    ${CURRENT_INTERFACE} is the default network interface"
                log "    ${CURRENT_GATEWAY} is the Router Gateway address"
                log "    Using ${CURRENT_IP_ADDRESS} as the static IP for now"

                sudo tee -a $OPTIMIZE_DHCP_CONF <<-EOF

${OPTIMIZE_DHCP_CONF_HEADER}
interface ${CURRENT_INTERFACE}
static ip_address=${CURRENT_IP_ADDRESS}/24
static routers=${CURRENT_GATEWAY}
static domain_name_servers=${CURRENT_GATEWAY}
noarp

EOF

            fi
        fi
    fi
}

_optimize_ipv6_arp() {
    if [ "$DISABLE_IPv6" = true ] ; then
        print_lc "  Disabling IPV6"
        _add_options_to_cmdline "${OPTIMIZE_BOOT_CMDLINE_OPTIONS_IPV6}"
    fi
}

_optimize_handle_boot_screen() {
  local configFile=$(get_boot_config_path)
  if [ "$DISABLE_BOOT_SCREEN" = true ] ; then
    log "  Disable RPi rainbow screen"
    if grep -q "${OPTIMIZE_BOOT_CONF_HEADER}" "$configFile"; then
      log "    Skipping. Already set up!"
    else
      sudo tee -a $configFile <<-EOF

${OPTIMIZE_BOOT_CONF_HEADER}
disable_splash=1

EOF
    fi
  fi
}

_optimize_handle_boot_logs() {
  if [ "$DISABLE_BOOT_LOGS_PRINT" = true ] ; then
    log "  Disable boot logs"

    _add_options_to_cmdline "${OPTIMIZE_BOOT_CMDLINE_OPTIONS}"
  fi
}

_optimize_static_ip_NetworkManager() {
    if [[ $(is_NetworkManager_enabled) == true ]]; then
        if [ "$ENABLE_STATIC_IP" = true ] ; then
            print_lc "  Set static IP address"
            log "    ${CURRENT_INTERFACE} is the default network interface"
            log "    ${CURRENT_GATEWAY} is the Router Gateway address"
            log "    Using ${CURRENT_IP_ADDRESS} as the static IP for now"
            local active_profile=$(get_nm_active_profile)
            sudo nmcli connection modify "$active_profile" ipv4.method manual ipv4.address "${CURRENT_IP_ADDRESS}/24" ipv4.gateway "$CURRENT_GATEWAY" ipv4.dns "$CURRENT_GATEWAY"
        #else
            # for future deactivation
            #sudo nmcli connection modify "$active_profile" ipv4.method auto ipv4.address "" ipv4.gateway "" ipv4.dns ""
        fi
    fi
}

_optimize_check() {
    print_verify_installation

    local cmdlineFile=$(get_boot_cmdline_path)
    local configFile=$(get_boot_config_path)


    verify_optional_service_enablement keyboard-setup.service disabled
    verify_optional_service_enablement triggerhappy.service disabled
    verify_optional_service_enablement triggerhappy.socket disabled
    verify_optional_service_enablement raspi-config.service disabled
    verify_optional_service_enablement apt-daily.service disabled
    verify_optional_service_enablement apt-daily-upgrade.service disabled
    verify_optional_service_enablement apt-daily.timer disabled
    verify_optional_service_enablement apt-daily-upgrade.timer disabled

    if [ "$DISABLE_BLUETOOTH" = true ] ; then
        verify_optional_service_enablement hciuart.service disabled
        verify_optional_service_enablement bluetooth.service disabled
    fi

    if [ "$ENABLE_STATIC_IP" = true ] ; then
        if [[ $(is_dhcpcd_enabled) == true ]]; then
            verify_file_contains_string_once "${OPTIMIZE_DHCP_CONF_HEADER}" "${OPTIMIZE_DHCP_CONF}"
            verify_file_contains_string "${CURRENT_INTERFACE}" "${OPTIMIZE_DHCP_CONF}"
            verify_file_contains_string "${CURRENT_IP_ADDRESS}" "${OPTIMIZE_DHCP_CONF}"
            verify_file_contains_string "${CURRENT_GATEWAY}" "${OPTIMIZE_DHCP_CONF}"
        fi

        if [[ $(is_NetworkManager_enabled) == true ]]; then
            local active_profile=$(get_nm_active_profile)
            local active_profile_path="/etc/NetworkManager/system-connections/${active_profile}.nmconnection"
            verify_files_exists "${active_profile_path}"
            verify_file_contains_string "${CURRENT_IP_ADDRESS}" "${active_profile_path}"
            verify_file_contains_string "${CURRENT_GATEWAY}" "${active_profile_path}"
        fi
    fi
    if [ "$DISABLE_IPv6" = true ] ; then
        verify_file_contains_string_once "${OPTIMIZE_BOOT_CMDLINE_OPTIONS_IPV6}" "${cmdlineFile}"
    fi
    if [ "$DISABLE_BOOT_SCREEN" = true ] ; then
        verify_file_contains_string_once "${OPTIMIZE_BOOT_CONF_HEADER}" "${configFile}"
    fi

    if [ "$DISABLE_BOOT_LOGS_PRINT" = true ] ; then
        for option in $OPTIMIZE_BOOT_CMDLINE_OPTIONS
        do
            verify_file_contains_string_once $option "${cmdlineFile}"
        done
    fi
}

_run_optimize_boot_time() {
    _optimize_disable_irrelevant_services
    _optimize_handle_boot_screen
    _optimize_handle_boot_logs
    _optimize_handle_bluetooth
    _optimize_static_ip
    _optimize_static_ip_NetworkManager
    _optimize_ipv6_arp
    _optimize_check
}

optimize_boot_time() {
    run_with_log_frame _run_optimize_boot_time "Optimize boot time"
}

optimize_boot_time
