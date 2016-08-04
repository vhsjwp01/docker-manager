#!/bin/bash
#set -x
#
# docker-constart    This shell script takes care of starting and stopping
#                    docker containers that were running at last shutdown
#
# chkconfig: 2345 99 01
# description: This script runs any docker commands in /etc/sysconfig/docker-constart
# probe: true
# config: /etc/sysconfig/docker-constart

### BEGIN INIT INFO
# Provides: docker-constart
# Default-Stop: 0 1 6
# Short-Description: Start up persistent docker containers
# Description: This script runs all docker commands for persistence
#              in file /etc/sysconfig/docker-constart
### END INIT INFO

# Source function library.
. /etc/rc.d/init.d/functions

# Command file
SYSCONFIG_FILE="/etc/sysconfig/docker-constart"

# Console Cred file
CONSOLE_CREDS="/etc/docker_console.creds"

# See how we were called.
case "$1" in

    start)
        echo "Starting persistent docker containers ... "

        if [ -e "${SYSCONFIG_FILE}" ]; then
            docker_commands=$(awk '{print $0}' "${SYSCONFIG_FILE}" | sed -e 's?\ ?:zzQc:?g')

            for docker_command in ${docker_commands} ; do
                old_container_hash=$(echo "${docker_command}" | sed -e 's?:zzQc:?\ ?g' | awk -F'#' '{print $2}')
                this_docker_command=$(echo "${docker_command}" | sed -e 's?:zzQc:?\ ?g' | awk -F'#' '{print $1}')

                # If --name was included, make sure that any previous containers of the same name
                # have been removed
                container_name=$(echo "${this_docker_command}" | awk -F'--name ' '{print $2}' | awk '{print $1}')
  
                if [ "${container_name}" != "" ]; then
                    named_container_id=$(docker ps -aqf name=${container_name} 2> /dev/null)
  
                    if [ "${named_container_id}" != "" ]; then
                        echo "  INFO:  Running docker command:"
                        echo "  docker rm ${named_container_id}"
                        eval docker rm ${container_id} > /dev/null 2>&1
                    fi
  
                fi

                #----------------------------------------
                # CUSTOM IPv4 BLOCK - START
                #----------------------------------------
                # ANY CHANGES TO THIS BLOCK OF CODE NEEDS
                # TO BE MIRRORED IN docker-constart.sh
                #----------------------------------------

                # Check for custom IPv4 interfaces
                # NOTE: "The Rules":
                #       - The custom IPv4 address does not match any of this node's IPv4 addresses
                #       - The custom IPv4 address can be resolved via DNS
                #       - The custom IPv4 address is not pingable by IP
                #       - The custom IPv4 address is not pingable by hostname
                #       - The custom IPv4 address matches this node's primary subnet
               
                modified_value=$(echo "${value}" | sed -e 's?-p ?-p_?g')
                let custom_ip_check=$(echo "${modified_value}" | egrep -c "\-p_[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*:")

                if [ ${custom_ip_check} -gt 0 ]; then
                    my_ipv4_address=$(host $(hostname) 2> /dev/null | egrep "has address" | awk '{print $NF}')

                    # Check /etc/hosts
                    if [ "${my_ipv4_address}" = "" ]; then
                        my_ipv4_address=$(egrep "$(hostname)" /etc/hosts | awk '{print $1}')
                    fi

                    my_ipv4_interfaces=$(ip addr show | egrep "^[0-9]*:" | awk '{print $2}' | sed -e 's?:$??g')
                    my_ipv4_interface=""
                    my_ipv4_netmask=""

                    for interface in ${my_ipv4_interfaces} ; do
                        let iface_ip_match=$(ip addr show dev ${interface} | egrep -v "127\.0\.0\.1" | egrep -c "inet ${my_ipv4_address}")

                        if [ ${iface_ip_match} -gt 0 ]; then
                            my_ipv4_interface=${interface}
                            my_ipv4_netmask=$(ip addr show dev ${interface} | egrep "inet ${my_ipv4_address}" | awk '{print $2}' | awk -F'/' '{print $NF}')
                            break
                        fi

                    done

                    for arg in ${modified_value}; do

                        # Ignore any references to our IPv4 address, loopback,  or the default of 0.0.0.0
                        let port_forward_check=$(echo "${arg}" | egrep -v "\-p_0\.0\.0\.0:|\-p_${my_ipv4_address}:\-p_127\.0\.0\.1:" | egrep -c "^\-p_")

                        if [ ${port_forward_check} -gt 0 ]; then
                            this_ipv4_address=$(echo "${arg}" | awk -F':' '{print $1}' | sed -e 's?^-p_??g')

                            # Make sure this IPv4 address isn't one of our interfaces
                            # A value of 0 == success
                            let local_ipv4_address_collision=1

                            if [ "${this_ipv4_address}" != "" ]; then
                                let local_ipv4_address_collision=$(ip addr show 2> /dev/null | egrep -c "${this_ipv4_address}")
                            fi

                            # Make sure this IPv4 address is on our subnet
                            # A value of 0 == success
                            let subnet_check_alignment=1

                            if [ "${this_ipv4_address}" != "" ]; then
                                my_broadcast=$(ipcalc -b ${my_ipv4_address}/${my_ipv4_netmask} 2> /dev/null)
                                let my_octet_check=${?}

                                this_broadcast=$(ipcalc -b ${this_ipv4_address}/${my_ipv4_netmask} 2> /dev/null)
                                let this_octet_check=${?}

                                if [ ${my_octet_check} -eq 0 -a ${this_octet_check} -eq 0 -a "${my_broadcast}" = "${this_broadcast}" ]; then
                                    let subnet_check_alignment=0
                                fi

                            fi

                            # Make sure this IPv4 address isn't out of bounds
                            # A value of 0 == success
                            let ipv4_address_out_of_bounds=1

                            if [ "${this_ipv4_address}" != "" ]; then
                                ipcalc -c ${this_ipv4_address}/${my_ipv4_netmask} > /dev/null 2>&1
                                let ipv4_address_out_of_bounds=${?}
                            fi

                            # Make sure this IPv4 address can be resolved
                            let hostname_in_dns=1
                            let ping_ipv4_test=0
                            let ping_hostname_test=0

                            if [ "${this_ipv4_address}" != "" ]; then
                                this_ipv4_hostname=$(host ${this_ipv4_address} 2> /dev/null | egrep "domain name pointer" | awk '{print $NF}' | sed -e 's?\.$??g')

                                if [ "${this_ipv4_hostname}" != "" ]; then
                                    # A value of 0 == success
                                    let hostname_in_dns=0

                                    # Make sure this IPv4 hostname is offline
                                    # A value of > 0 == success
                                    ping -c 3 ${this_ipv4_hostname} > /dev/null 2>&1
                                    let ping_hostname_test=${?}
                                
                                    # Make sure this IPv4 address is offline
                                    # A value of > 0 == success
                                    ping -c 3 ${this_ipv4_address} > /dev/null 2>&1
                                    let ping_ipv4_test=${?}
                                fi

                            fi

                            # Let's make this new IPv4 address a reality if we passed all the checks
                            if [ "${my_ipv4_interface}"           != "" -a \
                                 "${my_ipv4_netmask}"             != "" -a \
                                 "${this_ipv4_address}"           != "" -a \
                                  ${local_ipv4_address_collision} -eq 0 -a \
                                  ${subnet_check_alignment}       -eq 0 -a \
                                  ${ipv4_address_out_of_bounds}   -eq 0 -a \
                                  ${hostname_in_dns}              -eq 0 -a \
                                  ${ping_hostname_test}           -gt 0 -a \
                                  ${ping_ipv4_test}               -gt 0    \
                               ]; then
                               ip a add ${this_ipv4_address}/${my_ipv4_netmask} dev ${my_ipv4_interface} >> ${err_file} 2>&1
                            fi

                        fi

                    done

                fi

                #----------------------------------------
                # ANY CHANGES TO THIS BLOCK OF CODE NEEDS
                # TO BE MIRRORED IN docker-constart.sh
                #----------------------------------------
                # CUSTOM IPv4 BLOCK - END
                #----------------------------------------

                # Let's try to restart containers that were running before reboot
                echo "  INFO:  Running docker command:"
                echo "         ${this_docker_command}"
                eval "new_container_fullhash=\$(${this_docker_command})" > /dev/null 2>&1

                if [ ${?} -eq 0 ]; then
                    success

                    # Update container console access creds
                    if [ -e "${CONSOLE_CREDS}" ]; then
                        new_container_hash=$(echo -ne "${new_container_fullhash}" | cut -c 1-12)
                        sed -i -e "s/:${old_container_hash}\$/:${new_container_hash}/g" "${CONSOLE_CREDS}"
                    fi

                else
                    failure
                fi

            done

        else
            echo -ne "No persistent containers found"
            success
        fi

        echo
    ;;
  
    stop)
        echo -ne "This script only handles startup for persistent docker containers"
        success
        echo
    ;;
  
    populate)
        echo -ne "Populating \"${SYSCONFIG_FILE}\" ... "

        if [ -e "${SYSCONFIG_FILE}" ]; then
            rm -f "${SYSCONFIG_FILE}"
        fi
        
        currently_running_containers=$(docker ps -f status=running | egrep -v "^CONTAINER" | awk '{print $2 ":__:" $1}')
        
        if [ "${currently_running_containers}" != "" ]; then
            
            for currently_running_container in ${currently_running_containers} ; do
                container=$(echo "${currently_running_container}" | awk -F':__:' '{print $1}')
                container_hash=$(echo "${currently_running_container}" | awk -F':__:' '{print $2}')
                startup_command=$(egrep "docker run .* ${image_name}" /var/log/docker-mgr.log 2> /dev/null | tail -1 | sed -e 's?^.* Running command "docker?"docker?g' -e 's?^"??g' -e 's?"$??g')
            
                if [ "${startup_command}" != "" ]; then
                    echo "${startup_command}#${container_hash}" >> "${SYSCONFIG_FILE}"
                fi
            
            done
        
        fi

        success
        echo
    ;;

    status)
        echo
        echo "Currently running containers:"
        echo "============================="
        docker ps -f status=running
        echo "============================="
        success
        echo
    ;;

esac
