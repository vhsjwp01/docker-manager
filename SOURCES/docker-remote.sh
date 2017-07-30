#!/bin/bash
#set -x

################################################################################
#                      S C R I P T    D E F I N I T I O N
################################################################################
#

#-------------------------------------------------------------------------------
# Revision History
#-------------------------------------------------------------------------------
# 20150121     Jason W. Plummer          Original: A script to allow remote
#                                        sanitized interaction with a docker
#                                        runtime host
# 20150127     Jason W. Plummer          Added command injection protection and
#                                        fixed sed syntax error
# 20150129     Jason W. Plummer          Added improved security during argument
#                                        read in at the suggestion of D. Todd
# 20150303     Jason W. Plummer          Added support for ICG docker 
#                                        environment awareness (i.e. hardcoded 
#                                        hostnames).  Added better error 
#                                        feedback
#                                        errors
# 20150521     Jason W. Plummer          Was sending ${command} rather than 
#                                        ${sanitized_command}.  Removed 2 
#                                        argument restriction.  Fixed bad return
#                                        code syntax
# 20150722     Jason W. Plummer          Added capture of any remote error
#                                        messages.  Added this style template
# 20150723     Jason W. Plummer          Added check to ensure return_code is
#                                        set numerically
# 20150908     Jason W. Plummer          Refactored backtick ops to $()
# 20160616     Jason W. Plummer          Set return_code comparison as string
# 20160727     Jason W. Plummer          Added netcat TIMEOUT variable
# 20161108     Jason W. Plummer          Added swarm support
# 20161117     Jason W. Plummer          Added additional command injection 
#                                        protection regexes
# 20170104     Jason W. Plummer          Fixed issues with docker service create
# 20170727     Jason W. Plummer          New command transmission obvuscation
# 20170730     Jason W. Plummer          Added command and command_arg "version"

################################################################################
# DESCRIPTION
################################################################################
#

# NAME: docker-remote
# 
# This script performs remote docker operations against a docker container
# host.  This program is the client component, a daemon component called
# docker_mgr must be listening on the docker container host.
#
# OPTIONS:
#
# docker-remote <remote_host>:<remote_port> <command> <command_arg>
#
# WHERE
# 
# <remote_host>   - The FQDN or IP address of a docker runtime host
# <remote_port>   - The port to communicate with on <remote_host> *OPTIONAL*
# <command>       - What to do.  Valid commands are:
#    images   <List resident images on remote host>                                                       
#    inspect  <Instructs remote host to inspect a container instance>                                     
#                 NOTE: <command_arg> is *REQUIRED*:                                                      
#                 - <command_arg> *MUST* be a single argument that can be resolved as a valid container ID
#    list     <List running containers on remote host>                                                    
#    listall  <List all containers on remote host, running or otherwise>                                  
#    pull     <Instucts remote host to pull an image>                                                     
#                 NOTE: <command_arg> is *REQUIRED*:                                                      
#                 - <command_arg> *MUST* be a valid container registry target                             
#    rm       <Instructs remote host to delete a container instance>                                      
#                 NOTE: <command_arg> is *REQUIRED*:                                                      
#                 - <command_arg> *MUST* be a single argument that can be resolved as a valid container ID
#    rmi      <Instructs remote host to delete an image>                                                  
#                 NOTE: <command_arg> is *REQUIRED*:                                                      
#                 - <command_arg> *MUST* be a single argument that can be resolved as a valid image ID    
#    run      <Instructs remote host to start a container instance>                                       
#                 NOTE: <command_arg> is *REQUIRED*:                                                      
#                 - <command_arg> *MUST* be a single argument.  Encapsulate in quotes to glob             
#    stats    <Instructs remote host report the status of a container instance>                           
#                 NOTE: <command_arg> is *REQUIRED*:                                                      
#                 - <command_arg> *MUST* be a single argument that can be resolved as a valid container ID
#    stop     <Instructs remote host to start a container instance>                                       
#                 NOTE: <command_arg> is *REQUIRED*:                                                      
#                 - <command_arg> *MUST* be a single argument that can be resolved as a valid container ID
#    service  <Instructs remote host to start a container instance via SWARM>                                       
#                 NOTE: <command_arg> is *REQUIRED*:                                                      
#                 - <command_arg> *MUST* be a single argument.  Encapsulate in quotes to glob             
#    network  <Instructs remote host to start a container network instance via SWARM>                                       
#                 NOTE: <command_arg> is *REQUIRED*:                                                      
#                 - <command_arg> *MUST* be a single argument.  Encapsulate in quotes to glob             
#    version  <Reports local version of docker-remote and docker (if installed)>
#                 NOTE: Can also be used as a <command_arg> to report remote versions of docker and
#                       docker-remote
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

DOCKER_MGR_PORT=42000

STDOUT_OFFSET="    "

SCRIPT_NAME="${0}"

# Default timeout interval is 8 hours (in seconds)
TIMEOUT="28800"

USAGE_ENDLINE="\n${STDOUT_OFFSET}${STDOUT_OFFSET}${STDOUT_OFFSET}${STDOUT_OFFSET}"
USAGE="${SCRIPT_NAME} <remote_host>:[<remote_port> <command> <command_arg> ${USAGE_ENDLINE}"
USAGE="${USAGE}[ <remote_host>:[<remote_port> *OPTIONAL*] <The FQDN or IP address of a docker runtime host and optional port> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ <command>    <What to do.  Valid commands are [list|pull|run|stop]>                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     images   <List resident images on remote host>                                                           ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     inspect  <Instructs remote host to inspect a container instance>                                         ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  NOTE: <command_arg> is *REQUIRED*:                                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  - <command_arg> *MUST* be a single argument that can be resolved as a valid container ID    ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     list     <List running containers on remote host>                                                        ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     listall  <List all containers on remote host, running or otherwise>                                      ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     pull     <Instucts remote host to pull an image>                                                         ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  NOTE: <command_arg> is *REQUIRED*:                                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  - <command_arg> *MUST* be a valid container registry target                                 ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     rm       <Instructs remote host to delete a container instance>                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  NOTE: <command_arg> is *REQUIRED*:                                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  - <command_arg> *MUST* be a single argument that can be resolved as a valid container ID    ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     rmi      <Instructs remote host to delete an image>                                                      ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  NOTE: <command_arg> is *REQUIRED*:                                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  - <command_arg> *MUST* be a single argument that can be resolved as a valid image ID        ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     run      <Instructs remote host to start a container instance>                                           ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  NOTE: <command_arg> is *REQUIRED*:                                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  - <command_arg> *MUST* be a single argument.  Encapsulate in quotes to glob                 ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     stats    <Instructs remote host report the status of a container instance>                               ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  NOTE: <command_arg> is *REQUIRED*:                                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  - <command_arg> *MUST* be a single argument that can be resolved as a valid container ID    ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     stop     <Instructs remote host to start a container instance>                                           ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  NOTE: <command_arg> is *REQUIRED*:                                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  - <command_arg> *MUST* be a single argument that can be resolved as a valid container ID    ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     service  <Instructs remote host to start a container instance via SWARM>                                 ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  NOTE: <command_arg> is *REQUIRED*:                                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  - <command_arg> *MUST* be a single argument.  Encapsulate in quotes to glob                 ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     network  <Instructs remote host to start a container network instance via SWARM>                         ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  NOTE: <command_arg> is *REQUIRED*:                                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  - <command_arg> *MUST* be a single argument.  Encapsulate in quotes to glob                 ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     version  <Reports local version of docker-remote and docker (if installed)>                              ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  NOTE: Can also be used as a <command_arg> to report remote versions of docker and           ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                        docker-remote                                                                         ]"

################################################################################
# VARIABLES
################################################################################
#

err_msg=""
exit_code=${SUCCESS}

docker_mgr_port=${DOCKER_MGR_PORT}

################################################################################
# SUBROUTINES
################################################################################
#

sanitize_command() {
    TEMP_DIR="/tmp/docker_mgr/$$"
    rm -rf "${TEMP_DIR}" > /dev/null 2>&1
    mkdir -p "${TEMP_DIR}" 
    chmod -R 700 "${TEMP_DIR}"

    sanitized_command=$(echo "${command}" | sed -e 's?\`??g' -e 's?&&??g')
    echo "${sanitized_command}" > "${TEMP_DIR}"/pre_transport
    gzip "${TEMP_DIR}"/pre_transport &&
    remote_command_payload=$(base64 "${TEMP_DIR}"/pre_transport.gz)
    
    randomnum=$((RANDOM%100))
    remote_command_cksum=$(echo "${remote_command_payload}" | cksum | awk '{print $1}')
    new_sum=$(echo "${remote_command_cksum}*${randomnum}" | bc)
    remote_command_flight="${new_sum}.:${remote_command_payload}:.${randomnum}"
    rm -f "${TEMP_DIR}"/pre_transport*
}

################################################################################
# MAIN
################################################################################
#

# The "Process":
# 1. Tell the docker container host to pull the new image name
# 2. Look for related container(s) already running:
#    docker ps -a | egrep "lvicdockregp01.ingramcontent.com:8080/prodstat:latest" | egrep -iv "exited" | awk '{print $1 ":" $2}'
#        - yields a list of matching container ID and image name pairs
# 3. Tell the docker container host to stop the relevant container ID(s)
# 4. Tell the docker container host to run the new container process

# WHAT: See if netcat requires units for timeout:
# WHY:  Matters later
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    let timeout_unit_check=$(nc -w ${TIMEOUT}s 2>&1 | egrep -c "timeout cannot be negative")

    if [ ${timeout_unit_check} -eq 0 ]; then
        TIMEOUT="${TIMEOUT}s"
    fi

fi

# WHAT: Make sure ${1} is a valid target
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    if [ "${1}" != "" ]; then

        case "${1}" in

            version)
                echo "Docker-Remote version: ::DRVERSION::"
                my_docker=$(which docker 2> /dev/null)

                if [ "${my_docker}" != "" ]; then
                    echo -ne "Local Docker version:\n$(docker version)"
                fi

                exit ${exit_code}
            ;;

            *)
                remote_host=$(echo "${1}" | sed -e 's?:?\ ?g' | awk '{print $1}' | sed -e 's?\`??g' -e 's?&&??')
                remote_port=$(echo "${1}" | sed -e 's?:?\ ?g' | awk '{print $2}' | sed -e 's?[^0-9]??g' -e 's?\`??g' -e 's?&&??g')
                shift
    
                # Make sure host is online
                ping -c 2 "${remote_host}" > /dev/null 2>&1
                let valid_host=${?}
                #let valid_host=$(host "${remote_host}" 2> /dev/null | egrep -ic "domain name pointer|has address")
    
                if [ ${valid_host} -gt 0 ]; then
                    err_msg="Supplied docker container host \"${remote_host}\" is invalid"
                    exit_code=${ERROR}
                else
    
                    if [ "${remote_port}" != "" ]; then
                        let docker_mgr_port=${remote_port}
    
                        if [ ${docker_mgr_port} -gt 65535 -o ${docker_mgr_port} -lt 1 ]; then
                            err_msg="Supplied docker container host port \"${docker_mgr_port}\" is invalid"
                            exit_code=${ERROR}
                        fi
    
                    fi
    
                fi

            ;;

        esac
    
    fi

fi

# WHAT: Make sure we have at least one command
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    if [ "${1}" != "" ]; then
    
        # Rip through commands and assign them
        while (( "${#}" )); do
            command=""
            key=$(echo "${1}" | sed -e 's?\`??g' -e 's?&&??g')
    
            case "${key}" in
    
                images|list|listall|version)
                    command="${key}"
                    shift
                ;;
    
                inspect|pull|rm|rmi|run|stats|stop|service|network)
                    value=$(echo "${2}" | sed -e 's?\`??g' -e 's?&&??g')
    
                    if [ "${value}" = "" ]; then
                        err_msg="Remote command cannot be blank"
                        exit_code=${ERROR}
                    else
                        command="${key}=\"${value}\""
                        shift
                        shift
                    fi

                    # See if we have more in the stack
                    if [ "${*}" != "" ]; then
                        remainder=$(echo "${*}" | sed -e 's?\`??g' -e 's?&&??g')

                        if [ "${remainder}" != "" ]; then
                            value="${value} ${remainder}"
                            command="${key}=\"${value}\""

                            while (( "${#}" )); do
                                shift
                            done

                        fi

                    fi
    
                ;;

                *)
                    # Exit ... quietly, peacefully, and enjoy it
                    exit_code=${ERROR}
                    exit ${exit_code}
                ;;
    
            esac
    
            # Execute commands if possible
            if [ "${command}" != "" ]; then
                return_code=${SUCCESS}

                case ${command} in

                    images)
                        # Replace spaces with spaceholders
                        #sanitized_command=$(echo "${command}" | sed -e 's?\ ?:ZZqC:?g' | sed -e 's?\`??g' -e 's?&&??g')
                        sanitize_command

                        for docker_host in ${remote_host} ; do
                            echo "Docker images on host: ${docker_host}"
                            echo "============================================="
                            #echo "${sanitized_command}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}"
                            echo "${remote_command_flight}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}"
                            echo
                        done

                    ;;

                    inspect=*)
                        # Replace spaces with spaceholders
                        #sanitized_command=$(echo "${command}" | sed -e 's?\ ?:ZZqC:?g' | sed -e 's?\`??g' -e 's?&&??g')
                        sanitize_command

                        for docker_host in ${remote_host} ; do
                            echo "Inspection of docker container/image ${value} on host: ${docker_host}"
                            echo "============================================="
                            #echo "${sanitized_command}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}"
                            echo "${remote_command_flight}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}"
                            echo
                        done

                    ;;

                    list)
                        # Replace spaces with spaceholders
                        #sanitized_command=$(echo "${command}" | sed -e 's?\ ?:ZZqC:?g' | sed -e 's?\`??g' -e 's?&&??g')
                        sanitize_command

                        for docker_host in ${remote_host} ; do
                            echo "Docker containers running on host: ${docker_host}"
                            echo "============================================="
                            #echo "${sanitized_command}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}"
                            echo "${remote_command_flight}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}"
                            echo
                        done

                    ;;

                    listall)
                        # Replace spaces with spaceholders
                        #sanitized_command=$(echo "${command}" | sed -e 's?\ ?:ZZqC:?g' | sed -e 's?\`??g' -e 's?&&??g')
                        sanitize_command

                        for docker_host in ${remote_host} ; do
                            echo "Docker containers present on host: ${docker_host}"
                            echo "============================================="
                            #echo "${sanitized_command}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}"
                            echo "${remote_command_flight}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}"
                            echo
                        done

                    ;;

                    network=*)
                        # Replace spaces with spaceholders
                        #sanitized_command=$(echo "${command}" | sed -e 's?\ ?:ZZqC:?g' | sed -e 's?\`??g' -e 's?&&??g')
                        sanitize_command

                        for docker_host in ${remote_host} ; do
                            echo "Output of docker network command on host: ${docker_host}"
                            echo "============================================="
                            #echo "${sanitized_command}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}" | egrep -v "^${SUCCESS}::$" | sed -e 's?^[0-9]*::?    ERROR MSG: ?g'
                            echo "${remote_command_flight}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}" | egrep -v "^${SUCCESS}::$" | sed -e 's?^[0-9]*::?    ERROR MSG: ?g'
                            echo
                        done

                    ;;

                    service=*)
                        # Replace spaces with spaceholders
                        #sanitized_command=$(echo "${command}" | sed -e 's?\ ?:ZZqC:?g' | sed -e 's?\`??g' -e 's?&&??g')
                        sanitize_command

                        for docker_host in ${remote_host} ; do
                            echo "Output of docker service command on host: ${docker_host}"
                            echo "============================================="
                            #echo "${sanitized_command}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}" | egrep -v "^${SUCCESS}::$" | sed -e 's?^[0-9]*::?    ERROR MSG: ?g'
                            echo "${remote_command_flight}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}" | egrep -v "^${SUCCESS}::$" | sed -e 's?^[0-9]*::?    ERROR MSG: ?g'
                            echo
                        done

                    ;;

                    stats=*)
                        # Replace spaces with spaceholders
                        #sanitized_command=$(echo "${command}" | sed -e 's?\ ?:ZZqC:?g' | sed -e 's?\`??g' -e 's?&&??g')
                        sanitize_command

                        for docker_host in ${remote_host} ; do
                            echo "Status of docker container ${value} on host: ${docker_host}"
                            echo "============================================="
                            #echo "${sanitized_command}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}"
                            echo "${remote_command_flight}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}"
                            echo
                        done

                    ;;

                    *)
                        # Replace spaces with spaceholders
                        #sanitized_command=$(echo "${command}" | sed -e 's?\ ?:ZZqC:?g' | sed -e 's?\`??g' -e 's?&&??g')
                        sanitize_command

                        for docker_host in ${remote_host} ; do

                            if [ ${exit_code} -eq ${SUCCESS} ]; then
                                #echo "${sanitized_command}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}"
                                #return_code=$(echo "${sanitized_command}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}")
                                #cmd_output=$(echo "${sanitized_command}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}")
                                cmd_output=$(echo "${remote_command_flight}" | nc -w ${TIMEOUT} "${docker_host}" "${docker_mgr_port}")
                                return_code=$(echo -ne "${cmd_output}\n" | head -1 | awk -F'::' '{print $1}')

                                if [ "${return_code}" = "" ]; then
                                    echo "${STDOUT_OFFSET}INFO:  No return code received from docker container host \"${docker_host}\":"
                                    return_code=${ERROR}
                                else
                                    return_msg=$(echo "${cmd_output}" | sed -e "s/^${return_code}:://g")

                                    if [ "${return_msg}" != "" ]; then
                                        echo "${STDOUT_OFFSET}INFO:  Response from docker container host \"${docker_host}\":"
                                        echo -ne "           - '${return_msg}'\n"
                                    fi

                                fi

                                if [ "${return_code}" != "${SUCCESS}" ]; then
                                    err_msg="Remote command \"${command}\" failed on docker container host \"${docker_host}\""
                                    exit_code=${ERROR}
                                fi

                            fi

                        done

                    ;;

                esac
 
            fi
    
        done
    
    else
        err_msg="No arguments provided"
        exit_code=${ERROR}
    fi

fi

# WHAT: Complain if necessary and exit
# WHY:  Success or failure, either way we are through
#
if [ ${exit_code} -ne ${SUCCESS} ]; then

    if [ "${err_msg}" != "" ]; then
        echo
        echo -ne "${STDOUT_OFFSET}ERROR:  ${err_msg} ... processing halted\n"
        echo
    fi

    echo
    echo -ne "${STDOUT_OFFSET}USAGE:  ${USAGE}\n"
    echo
fi

exit ${exit_code}
