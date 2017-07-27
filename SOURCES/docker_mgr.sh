#!/bin/bash
#set -x

################################################################################
#                      S C R I P T    D E F I N I T I O N
################################################################################
#

#-------------------------------------------------------------------------------
# Revision History
#-------------------------------------------------------------------------------
# 20150121     Jason W. Plummer          Original: A script to answer remote
#                                        docker requests
# 20150129     Jason W. Plummer          Added improved security during argument
#                                        read in at the suggestion of D. Todd
# 20150722     Jason W. Plummer          Added echo of any error messages.  
#                                        Added this style template
# 20150722     Jason W. Plummer          Fixed grammar issues
# 20151022     Jason W. Plummer          Added support to restart containers
#                                        after a reboot
# 20151116     Jason W. Plummer          Created docker-constart init script
# 20151223     Jason W. Plummer          Added TMOUT variable to runtime args
# 20160321     Jason W. Plummer          Added log_driver and restart params
# 20160322     Jason W. Plummer          Added /etc/localtime mapping at runtime
# 20160519     Jason W. Plummer          Added docker version checker to handle
#                                        log tagging syntax
# 20160616     Jason W. Plummer          Added code to remove stopped named
#                                        containers.  Added logging statement
#                                        for same
# 20160617     Jason W. Plummer          Code optimization for stop/rm ops
# 20160707     Jason W. Plummer          Change syslog logging to use UDP
# 20160727     Jason W. Plummer          Added support for adding ethernet
#                                        aliases, docker inspect, and docker
#                                        stats
# 20160801     Jason W. Plummer          Added support for detecting and 
#                                        removing named containers prior to
#                                        running
# 20160801     Jason W. Plummer          Added support for container_id tracking
#                                        for console registration reconfigure
#                                        during docker-constart execution after
#                                        reboot
# 20160802     Jason W. Plummer          Added support for dynamic labeling
# 20161003     Jason W. Plummer          Turned ingramcontent.com base label
#                                        into a variable
# 20161107     Jason W. Plummer          Fixed /etc/localtime overlay.  Started
#                                        adding swarm support
# 20161110     Jason W. Plummer          Added support for missing output on
#                                        rm, rmi, and swarm commands
# 20170104     Jason W. Plummer          Fixed issues with docker service create
# 20170613     Jason W. Plummer          Fixed issues with docker version 
#                                        checking to support the new versioning
#                                        schema
# 20170613     Jason W. Plummer          Fixed issues with logging docker
#                                        service commands
# 20170727     Jason W. Plummer          Added DOCKER_RUNTIME_HOST variable and
#                                        bind mount for /etc/localtime for swarm
#                                        operations.  Added better remote 
#                                        command line obvuscation in transport

################################################################################
# DESCRIPTION
################################################################################
#

# NAME: docker_mgr
# 
# This script is meant to be invoked by xinetd, after which it processes
# whatever string it was sent and matches the parsing with allowed operations
# which are then executed.  Anything else produces an error.
#

################################################################################
# CONSTANTS
################################################################################
#

PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin
TERM=vt100
export TERM PATH

SUCCESS=0
ERROR=1

LOGFILE="/var/log/docker-mgr.log"
SYSCONFIG_FILE="/etc/sysconfig/docker-constart"

TMOUT=1800

################################################################################
# VARIABLES
################################################################################
#

exit_code=${ERROR}

syslog_port="514"
syslog_server="log.ingramcontent.com"
syslog_transport="udp"

docker_base_label="com.ingramcontent"

################################################################################
# SUBROUTINES
################################################################################
#

check_command_payload() {
    TEMP_DIR="/tmp/docker_mgr/$$"
    rm -rf "${TEMP_DIR}" > /dev/null 2>&1
    mkdir -p "${TEMP_DIR}"
    chmod -R 700 "${TEMP_DIR}"

    prefix_value=$(echo "${input}" | awk -F':' '/\.:/ {print $1}' | sed -e 's?\.$??g')
    suffix_value=$(echo "${input}" | awk -F':' '/:\./ {print $NF}' | sed -e 's?^\.??g')
    remote_command_payload=$(echo "${input}" | sed -e "s/${prefix_value}\.://g" -e "s/:\.${suffix_value}//g")
    echo "${remote_command_payload}" | base64 -d > "${TEMP_DIR}"/post_transport.gz
    gunzip "${TEMP_DIR}"/post_transport.gz
    remote_command=$(awk '{print $0}' "${TEMP_DIR}"/post_transport)
    remote_command_payload_cksum=$(echo "${prefix_value}/${suffix_value}" | bc)
    payload_cksum=$(echo "${remote_command_payload}" | cksum | awk '{print $1}')
    rm -f "${TEMP_DIR}"/post_transport* > /dev/null 2>&1
    
    if [ ${payload_cksum} -ne ${remote_command_payload_cksum} ]; then
        input=""
    else
        input="${remote_command}"
    fi
}

################################################################################
# MAIN
################################################################################
#

err_file="/tmp/docker.$$.err"
rm -f "${err_file}" > /dev/null 2>&1

read input
check_command_payload

let input_wc=$(echo "${input}" | wc -w | awk '{print $1}')

if [ "${input}" != "" -a ${input_wc} -eq 1 ]; then
    key=$(echo "${input}" | awk -F'=' '{print $1}' | sed -e 's?\`??g')
    value=$(echo "${input}" | sed -e "s?^${key}=??g" -e 's?:ZZqC:?\ ?g' -e 's?\"??g' -e 's?\`??g')

    case ${key} in

        images)
            report_status="no"
            echo "`date`: Running command \"docker images\"" >> "${LOGFILE}"
            docker images 2>> ${err_file}
            exit_code=${?}
        ;;

        inspect)

            if [ "${value}" != "" ]; then
                report_status="no"

                # Make sure ${value} is valid container OR image
                inspection_target=$(for i in $(docker ps -qa) $(docker images -q) ; do echo "${i}" ; done | egrep "^${value}$")

                if [ "${inspection_target}" != "" ]; then
                    echo "`date`: Running command \"docker ${key} ${value}\"" >> "${LOGFILE}"
                    eval docker ${key} ${value} 2>> ${err_file}
                else
                    echo "No such running container" >> ${err_file}
                    false > /dev/null 2>&1
                fi

                exit_code=${?}
            fi

        ;;

        list)
            report_status="no"
            echo "`date`: Running command \"docker ps -f status=running\"" >> "${LOGFILE}"
            docker ps -f status=running 2>> ${err_file}
            exit_code=${?}
        ;;

        listall)
            report_status="no"
            echo "`date`: Running command \"docker ps -f status=running\"" >> "${LOGFILE}"
            docker ps -a 2>> ${err_file}
            exit_code=${?}
        ;;

        pull)

            if [ "${value}" != "" ]; then
                echo "`date`: Running command \"docker ${key} ${value}\"" >> "${LOGFILE}"
                eval docker ${key} ${value} >> ${err_file} 2>&1
                exit_code=${?}
            fi

        ;;

        rm)

            if [ "${value}" != "" ]; then

                # Make sure ${value} is a stopped container ID
                let stopped_container_check=$(docker ps -f status=exited | awk '{print $1}' | egrep -c "^${value}$")

                if [ ${stopped_container_check} -gt 0 ]; then
                    echo "`date`: Running command \"docker ${key} ${value}\"" >> "${LOGFILE}"
                    eval docker ${key} ${value} 2>> ${err_file}
                else
                    echo "No such container" >> ${err_file}
                    false > /dev/null 2>&1
                fi

                exit_code=${?}
            fi

        ;;

        rmi)

            if [ "${value}" != "" ]; then

                # Make sure ${value} is valid image ID
                let image_check=$(docker images | awk '{print $3}' | egrep -c "^${value}$")

                if [ ${image_check} -gt 0 ]; then
                    echo "`date`: Running command \"docker ${key} ${value}\"" >> "${LOGFILE}"
                    eval docker ${key} ${value} 2>> ${err_file}
                else
                    echo "No such image" >> ${err_file}
                    false > /dev/null 2>&1
                fi

                exit_code=${?}
            fi

        ;;

        run)

            if [ "${value}" != "" ]; then

                # Setup some useful docker labels
                icg_docker_build_check=$(echo "${value}" | awk '{ for ( i = 1 ; i <= NF ; i++ ) { if ($i ~ /:[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]\./ ) print $i } }')

                if [ "${icg_docker_build_check}" != "" ]; then
                    docker_labels=""

                    label_container_name=$(echo "${icg_docker_build_check}" | awk -F'/' '{print $NF}' | awk -F':' '{print $1}')
                    label_container_tag=$(echo "${icg_docker_build_check}" | awk -F':' '{print $NF}')
                    label_container_namespace=$(echo "${icg_docker_build_check}" | awk -F'/' '{print $(NF-1)}' | egrep -v "lvicdockregp")
                    label_container_build_date=$(echo "${label_container_tag}" | awk -F'.' '{print $1}')
                    label_container_environment=$(echo "${label_container_tag}" | awk -F'.' '{print $2}')
                    label_container_commit_hash=$(echo "${label_container_tag}" | awk -F'.' '{print $3}')

                    # Add in container name if defined - this matches git project
                    if [ "${label_container_name}" != "" ]; then

                        if [ "${docker_labels}" = "" ]; then
                            docker_labels="--label ${docker_base_label}.container.name=${label_container_name}"
                        else
                            docker_labels="${docker_labels} --label ${docker_base_label}.container.name=${label_container_name}"
                        fi

                    fi

                    # Add in container environment if defined - this matches git branch
                    if [ "${label_container_environment}" != "" ]; then

                        if [ "${docker_labels}" = "" ]; then
                            docker_labels="--label ${docker_base_label}.container.environment=${label_container_environment}"
                        else
                            docker_labels="${docker_labels} --label ${docker_base_label}.container.environment=${label_container_environment}"
                        fi

                    fi

                    # Add in namespace if defined
                    if [ "${label_container_namespace}" != "" ]; then

                        if [ "${docker_labels}" = "" ]; then
                            docker_labels="--label ${docker_base_label}.container.namespace=${label_container_namespace}"
                        else
                            docker_labels="${docker_labels} --label ${docker_base_label}.container.namespace=${label_container_namespace}"
                        fi

                    fi

                    # Add in build date if defined
                    if [ "${label_container_build_date}" != "" ]; then

                        if [ "${docker_labels}" = "" ]; then
                            docker_labels="--label ${docker_base_label}.container.build_date=${label_container_build_date}"
                        else
                            docker_labels="${docker_labels} --label ${docker_base_label}.container.build_date=${label_container_build_date}"
                        fi

                    fi

                    # Add in commit hash if defined
                    if [ "${label_container_commit_hash}" != "" ]; then

                        if [ "${docker_labels}" = "" ]; then
                            docker_labels="--label ${docker_base_label}.container.commit_hash=${label_container_commit_hash}"
                        else
                            docker_labels="${docker_labels} --label ${docker_base_label}.container.commit_hash=${label_container_commit_hash}"
                        fi

                    fi

                fi

                # Add docker labels if defined
                if [ "${docker_labels}" != "" ]; then
                    value="${docker_labels} ${value}"
                fi

                # Add DOCKER_RUNTIME_HOST if not already set
                docker_runtime_host_check=$(echo "${value}" | egrep -c "\-e DOCKER_RUNTIME_HOST=")

                if [ ${docker_runtime_host_check} -eq 0 ]; then
                    DOCKER_RUNTIME_HOST=$(hostname) &&
                    value="-e 'DOCKER_RUNTIME_HOST=${DOCKER_RUNTIME_HOST}' ${value}"
                fi
                
                # Add TMOUT if not already set
                tmout_check=$(echo "${value}" | egrep -c "\-e TMOUT=")

                if [ ${tmout_check} -eq 0 ]; then
                    value="-e 'TMOUT=${TMOUT}' ${value}"
                fi

                # Add persistence if not already set
                persistence_check=$(echo "${value}" | egrep -c "\-\-restart=")

                if [ ${persistence_check} -eq 0 ]; then
                    value="--restart=on-failure:10 ${value}"
                fi

                # Add localtime if not already set
                localtime_check=$(echo "${value}" | egrep -c "/etc/localtime:/etc/localtime")

                if [ ${localtime_check} -eq 0 ]; then
                    value="-v /etc/localtime:/etc/localtime ${value}"
                fi

                # Add logging if not already set
                logging_check=$(echo "${value}" | egrep -c "\-\-log_driver=")

                if [ ${logging_check} -eq 0 ]; then
                    docker_major_ver=$(docker -v | awk -F',' '{print $1}' | awk '{print $NF}' | awk -F'-' '{print $1}' | awk -F'.' '{print $1}')
                    docker_minor_ver=$(docker -v | awk -F',' '{print $1}' | awk '{print $NF}' | awk -F'-' '{print $1}' | awk -F'.' '{print $2}')
                    let ver_check=$(echo "${docker_major_ver}${docker_minor_ver}>19" | bc)

                    if [ ${ver_check} -eq 1 ]; then

                        # New style log tagging supported after v1.9
                        value="--log-driver=syslog --log-opt syslog-address=${syslog_transport}://${syslog_server}:${syslog_port} --log-opt tag=\"$(hostname)/{{.ImageName}}/{{.Name}}/{{.ID}}\" ${value}"
                    else

                        # Old style log tagging supported up to v1.9
                        value="--log-driver=syslog --log-opt syslog-address=${syslog_transport}://${syslog_server}:${syslog_port} --log-opt syslog-tag=\"$(hostname)/docker-container-logs\" ${value}"
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
                            else
                                echo "Ethernet IP ${this_ipv4_address}/${my_ipv4_netmask} cannot be validated" >> ${err_file}

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

                # If --name was included, make sure that any previous containers of the same name
                # have been removed
                container_name=$(echo "${value}" | awk -F'--name ' '{print $2}' | awk '{print $1}')

                if [ "${container_name}" != "" ]; then
                    named_container_id=$(docker ps -aqf name=${container_name} 2> /dev/null)

                    if [ "${named_container_id}" != "" ]; then
                        echo "`date`: Running command \"docker rm ${named_container_id}\"" >> "${LOGFILE}"
                        eval docker rm ${container_id} >> ${err_file} 2>&1
                    fi

                fi

                echo "`date`: Running command \"docker ${key} ${value}\"" >> "${LOGFILE}"
                eval docker ${key} ${value} >> ${err_file} 2>&1
                exit_code=${?}
            fi
                
        ;;

        network)

            if [ "${value}" != "" ]; then

                # Figure out what SWARM action we have been asked to do
                network_action=$(echo "${value}" | awk '{print $1}')

                case ${network_action} in

                    connect|create|disconnect|inspect|ls|rm)
                        echo "`date`: Running command \"docker ${key} ${value}\"" >> "${LOGFILE}"
                        eval docker ${key} ${value} 2>> ${err_file}
                        exit_code=${?}
                    ;;

                esac 

            fi

        ;;

        service)

            if [ "${value}" != "" ]; then

                # Figure out what SWARM action we have been asked to do
                service_action=$(echo "${value}" | awk '{print $1}')

                case ${service_action} in

                    create)
                        value=$(echo "${value}" | sed -e 's/^create //g')

                        # Setup some useful docker labels
                        icg_docker_build_check=$(echo "${value}" | awk '{ for ( i = 1 ; i <= NF ; i++ ) { if ($i ~ /:[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]\./ ) print $i } }')

                        if [ "${icg_docker_build_check}" != "" ]; then
                            docker_labels=""

                            label_container_name=$(echo "${icg_docker_build_check}" | awk -F'/' '{print $NF}' | awk -F':' '{print $1}')
                            label_container_tag=$(echo "${icg_docker_build_check}" | awk -F':' '{print $NF}')
                            label_container_namespace=$(echo "${icg_docker_build_check}" | awk -F'/' '{print $(NF-1)}' | egrep -v "lvicdockregp")
                            label_container_build_date=$(echo "${label_container_tag}" | awk -F'.' '{print $1}')
                            label_container_environment=$(echo "${label_container_tag}" | awk -F'.' '{print $2}')
                            label_container_commit_hash=$(echo "${label_container_tag}" | awk -F'.' '{print $3}')

                            # Add in container name if defined - this matches git project
                            if [ "${label_container_name}" != "" ]; then

                                if [ "${docker_labels}" = "" ]; then
                                    docker_labels="--label ${docker_base_label}.container.name=${label_container_name}"
                                else
                                    docker_labels="${docker_labels} --label ${docker_base_label}.container.name=${label_container_name}"
                                fi

                            fi

                            # Add in container environment if defined - this matches git branch
                            if [ "${label_container_environment}" != "" ]; then

                                if [ "${docker_labels}" = "" ]; then
                                    docker_labels="--label ${docker_base_label}.container.environment=${label_container_environment}"
                                else
                                    docker_labels="${docker_labels} --label ${docker_base_label}.container.environment=${label_container_environment}"
                                fi

                            fi

                            # Add in namespace if defined
                            if [ "${label_container_namespace}" != "" ]; then

                                if [ "${docker_labels}" = "" ]; then
                                    docker_labels="--label ${docker_base_label}.container.namespace=${label_container_namespace}"
                                else
                                    docker_labels="${docker_labels} --label ${docker_base_label}.container.namespace=${label_container_namespace}"
                                fi

                            fi

                            # Add in build date if defined
                            if [ "${label_container_build_date}" != "" ]; then

                                if [ "${docker_labels}" = "" ]; then
                                    docker_labels="--label ${docker_base_label}.container.build_date=${label_container_build_date}"
                                else
                                    docker_labels="${docker_labels} --label ${docker_base_label}.container.build_date=${label_container_build_date}"
                                fi

                            fi

                            # Add in commit hash if defined
                            if [ "${label_container_commit_hash}" != "" ]; then

                                if [ "${docker_labels}" = "" ]; then
                                    docker_labels="--label ${docker_base_label}.container.commit_hash=${label_container_commit_hash}"
                                else
                                    docker_labels="${docker_labels} --label ${docker_base_label}.container.commit_hash=${label_container_commit_hash}"
                                fi

                            fi

                        fi

                        # Add docker labels if defined
                        if [ "${docker_labels}" != "" ]; then
                            value="${docker_labels} ${value}"
                        fi

                        # Add DOCKER_RUNTIME_HOST if not already set
                        docker_runtime_host_check=$(echo "${value}" | egrep -c "\-e DOCKER_RUNTIME_HOST=")

                        if [ ${docker_runtime_host_check} -eq 0 ]; then
                            DOCKER_RUNTIME_HOST=$(hostname) &&
                            value="-e 'DOCKER_RUNTIME_HOST=${DOCKER_RUNTIME_HOST}' ${value}"
                        fi

                        # Add TMOUT if not already set
                        tmout_check=$(echo "${value}" | egrep -c "\-e TMOUT=")

                        if [ ${tmout_check} -eq 0 ]; then
                            value="-e 'TMOUT=${TMOUT}' ${value}"
                        fi

                        # Add localtime if not already set
                        localtime_check=$(echo "${value}" | egrep -c "dst=/etc/localtime|src=/etc/localtime")


                        if [ ${localtime_check} -eq 0 ]; then
                            value="--mount type=bind,src=/etc/localtime,dst=/etc/localtime ${value}"
                        fi

                        # Add logging if not already set
                        logging_check=$(echo "${value}" | egrep -c "\-\-log_driver=")

                        if [ ${logging_check} -eq 0 ]; then
                            docker_major_ver=$(docker -v | awk -F',' '{print $1}' | awk '{print $NF}' | awk -F'-' '{print $1}' | awk -F'.' '{print $1}')
                            docker_minor_ver=$(docker -v | awk -F',' '{print $1}' | awk '{print $NF}' | awk -F'-' '{print $1}' | awk -F'.' '{print $2}')
                            let ver_check=$(echo "${docker_major_ver}${docker_minor_ver}>19" | bc)
  
                            if [ ${ver_check} -eq 1 ]; then
  
                                # New style log tagging supported after v1.9
                                value="--log-driver=syslog --log-opt syslog-address=${syslog_transport}://${syslog_server}:${syslog_port} --log-opt tag=\"$(hostname)/{{.ImageName}}/{{.Name}}/{{.ID}}\" ${value}"
                            else
  
                                # Old style log tagging supported up to v1.9
                                value="--log-driver=syslog --log-opt syslog-address=${syslog_transport}://${syslog_server}:${syslog_port} --log-opt syslog-tag=\"$(hostname)/docker-container-logs\" ${value}"
                            fi
  
                        fi

                        echo "`date`: Running command \"docker ${key} ${service_action} ${value}\"" >> "${LOGFILE}"
                        eval docker ${key} ${service_action} ${value} >> ${err_file} 2>&1
                        exit_code=${?}
                    ;;

                    inspect|ps|ls|rm|scale|update)
                        echo "`date`: Running command \"docker ${key} ${value}\"" >> "${LOGFILE}"
                        eval docker ${key} ${value} 2>> ${err_file}
                        exit_code=${?}
                    ;;

                esac

            fi

        ;;

        stats)

            if [ "${value}" != "" ]; then
                report_status="no"

                # Make sure ${value} is a running container
                let inspection_target=$(docker ps -f status=running | awk '{print $1}' | egrep -c "^${value}$")

                if [ ${inspection_target} -gt 0 ]; then
                    echo "`date`: Running command \"docker ${key} ${value}\"" >> "${LOGFILE}"
                    let counter=0

                    while [ ${counter} -lt 10 ] ; do

                        if [ ${counter} -eq 0 ]; then
                            docker ${key} --no-stream ${value}
                        else
                            docker ${key} --no-stream ${value} | egrep -v "^CONTAINER"
                        fi

                        sleep 1
                        let counter=${counter}+1
                    done

                fi

                exit_code=${?}
            fi

        ;;

        stop)

            if [ "${value}" != "" ]; then
                echo "`date`: Running command \"docker ${key} ${value}\"" >> "${LOGFILE}"
                eval docker ${key} ${value} >> ${err_file} 2>&1
                exit_code=${?}

                # Remove containers if it stopped successfully
                echo "`date`: Running command \"docker rm ${value}\"" >> "${LOGFILE}"
                eval docker rm ${value} >> ${err_file} 2>&1
                exit_code=${?}
            fi

        ;;

        *)
            # Exit ... quietly, peacefully, and enjoy it
            echo "`date`: Received foreign request: \"key=${key} value=${value}\"" >> "${LOGFILE}"
            echo "${ERROR}::Bad request"
            exit ${ERROR}
        ;;
            
    esac

fi

# Send command output (if any) back to the client along with the exit code
cmd_output=""

if [ -e "${err_file}" ]; then 
    raw_output=$(awk '{print $0}' /tmp/docker.$$.err | strings | sed -e 's/\[.*\]//g' -e 's/\ /:ZZqC:/g' | egrep -i "error")

    for raw_line in ${raw_output} ; do
        real_line=$(echo "${raw_line}" | sed -e 's/:ZZqC:/\ /g')

        if [ "${cmd_output}" = "" ]; then
            cmd_output="${real_line}"
        else
            cmd_output="${cmd_output}\n${real_line}"
        fi

    done

    rm -f "${err_file}" > /dev/null 2>&1
fi

# Report status unless told otherwise
if [ "${report_status}" != "no" ]; then
    echo "${exit_code}::${cmd_output}"
fi

# Now update the list of running containers so they can survive restart
if [ "${key}" != "service}" ]; then

    if [ -e "${SYSCONFIG_FILE}" ]; then
        rm -f "${SYSCONFIG_FILE}"
    fi
    
    currently_running_containers=$(docker ps -f status=running | egrep -v "^CONTAINER" | awk '{print $2 ":__:" $1}')
    
    if [ "${currently_running_containers}" != "" ]; then
        
        for running_container in ${currently_running_containers} ; do
            image_name=$(echo "${running_container}" | awk -F':__:' '{print $1}')
            container_id=$(echo "${running_container}" | awk -F':__:' '{print $2}')
            startup_command=$(egrep "docker run .* ${image_name}" /var/log/docker-mgr.log 2> /dev/null | tail -1 | sed -e 's?^.* Running command "docker?"docker?g' -e 's?^"??g' -e 's?"$??g')
        
            if [ "${startup_command}" != "" ]; then
                echo "${startup_command}#${container_id}" >> "${SYSCONFIG_FILE}"
            fi
        
        done
    
        if [ -e "${SYSCONFIG_FILE}" ]; then
            chmod 600 "${SYSCONFIG_FILE}"
        fi
    
    fi

fi

exit ${exit_code}
