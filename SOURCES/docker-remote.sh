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
#                                        sanitized nteraction with a docker
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
#    list             - List running containers on <remote_host>
#    pull             - Instucts <remote_host> to pull an image.
#                       NOTE: <command_arg> is *REQUIRED*:
#                       - <command_arg> *MUST* be a valid container registry
#                                       target
#    run              - Instructs <remote_host> to start a container instance.
#                       NOTE: <command_arg> is *REQUIRED*:
#                       - <command_arg> *MUST* be a single argument.
#                                       Encapsulate in quotes to glob
#    stop             - Instructs <remote_host> to stop a container instance.
#                       NOTE: <command_arg> is *REQUIRED*:
#                       - <command_arg> *MUST* be a single argument that can be
#                                       resolved as a valid container ID
#                                       
# test_env        - Built-in <command> that sets the host to be the TEST boxen
# qa_env          - Built-in <command> that sets the host to be the QA boxen
# prod_env        - Built-in <command> that sets the host to be the PROD boxen

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

USAGE_ENDLINE="\n${STDOUT_OFFSET}${STDOUT_OFFSET}${STDOUT_OFFSET}${STDOUT_OFFSET}"
USAGE="${SCRIPT_NAME} <remote_host>:[<remote_port> <command> <command_arg> ${USAGE_ENDLINE}"
USAGE="${USAGE}[ <remote_host>:[<remote_port> *OPTIONAL*] <The FQDN or IP address of a docker runtime host and optional port> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ <command>    <What to do.  Valid commands are [list|pull|run|stop]>                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     list     <List running containers on remote host>                                                        ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     pull     <Instucts remote host to pull an image>                                                         ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  NOTE: <command_arg> is *REQUIRED*:                                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  - <command_arg> *MUST* be a valid container registry target                                 ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     run      <Instructs remote host to start a container instance>                                           ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  NOTE: <command_arg> is *REQUIRED*:                                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  - <command_arg> *MUST* be a single argument.  Encapsulate in quotes to glob                 ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     stop     <Instructs remote host to start a container instance>                                           ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  NOTE: <command_arg> is *REQUIRED*:                                                          ]${USAGE_ENDLINE}"
USAGE="${USAGE}[                  - <command_arg> *MUST* be a single argument that can be resolved as a valid container ID    ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     test_env <Built-in <command> that sets the host to be the TEST boxen>                                    ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     qa_env   <Built-in <command> that sets the host to be the QA boxen>                                      ]${USAGE_ENDLINE}"
USAGE="${USAGE}[     prod_env <Built-in <command> that sets the host to be the PROD boxen>                                    ]"

################################################################################
# VARIABLES
################################################################################
#

err_msg=""
exit_code=${SUCCESS}

docker_mgr_port=${DOCKER_MGR_PORT}

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

## Make sure we have only two arguments
#if [ ${exit_code} -eq ${SUCCESS} ]; then
#
#    if [ ${#} -ne 2 ]; then
#        err_msg="${0} accepts two arguments and two arguments only"
#        exit_code=${ERROR}
#    fi
#
#fi

# WHAT: Make sure ${1} is a valid target
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    if [ "${1}" != "" ]; then

        case "${1}" in

            test_env)
                remote_host="lvicdockert01.ingramcontent.com lvicdockert02.ingramcontent.com"
                shift
            ;;

            qa_env)
                remote_host="lvicdockerq01.ingramcontent.com lvicdockerq02.ingramcontent.com"
                shift
            ;;

            prod_env)
                remote_host="lvicdockerp01.ingramcontent.com lvicdockerp02.ingramcontent.com"
                shift
            ;;
  
            *)
                remote_host=$(echo "${1}" | sed -e 's?:?\ ?g' | awk '{print $1}' | sed -e 's?\`??g')
                remote_port=$(echo "${1}" | sed -e 's?:?\ ?g' | awk '{print $2}' | sed -e 's?[^0-9]??g' -e 's?\`??g')
                shift
    
                # Make sure host is resolvable
                let valid_host=$(host "${remote_host}" 2> /dev/null | egrep -ic "domain name pointer|has address")
    
                if [ ${valid_host} -eq 0 ]; then
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
            key=$(echo "${1}" | sed -e 's?\`??g')
    
            case "${key}" in
    
                list)
                    command="${key}"
                    shift
                ;;
    
                pull|run|stop)
                    value=$(echo "${2}" | sed -e 's?\`??g')
    
                    if [ "${value}" = "" ]; then
                        err_msg="Remote command cannot be blank"
                        exit_code=${ERROR}
                    else
                        command="${key}=\"${value}\""
                        shift
                        shift
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

                    list)

                        for docker_host in ${remote_host} ; do
                            echo "Docker images present on host: ${docker_host}"
                            echo "============================================="
                            echo "${command}" | nc "${docker_host}" "${docker_mgr_port}"
                            echo
                        done

                    ;;

                    *)
                        # Replace spaces with spaceholders
                        sanitized_command=$(echo "${command}" | sed -e 's?\ ?:ZZqC:?g' | sed -e 's?\`??g')

                        for docker_host in ${remote_host} ; do

                            if [ ${exit_code} -eq ${SUCCESS} ]; then
                                #echo "${sanitized_command}" | nc "${docker_host}" "${docker_mgr_port}"
                                #return_code=$(echo "${sanitized_command}" | nc "${docker_host}" "${docker_mgr_port}")
                                cmd_output=$(echo "${sanitized_command}" | nc "${docker_host}" "${docker_mgr_port}")
                                return_code=$(echo -ne "${cmd_output}\n" | head -1 | awk -F'::' '{print $1}')
                                return_msg=$(echo "${cmd_output}" | sed -e "s/^${return_code}:://g")

                                if [ "${return_code}" = "" ]; then
                                    echo "${STDOUT_OFFSET}INFO:  No return code received from docker container host \"${docker_host}\":"
                                    return_code=${ERROR}
                                fi

                                if [ "${return_msg}" != "" ]; then
                                    echo "${STDOUT_OFFSET}INFO:  Response from docker container host \"${docker_host}\":"
                                    echo -ne "           - '${return_msg}'\n"
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
