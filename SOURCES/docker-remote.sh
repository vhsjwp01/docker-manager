#!/bin/bash
#set -x

PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin
TERM=vt100
export TERM PATH

SUCCESS=0
ERROR=1

DOCKER_MGR_PORT=42000

exit_code=${SUCCESS}

docker_mgr_port=${DOCKER_MGR_PORT}

# The "Process":
# 1. Tell the docker runtime server to pull the new image name
# 2. Look for related container(s) already running:
#    docker ps -a | egrep "lvicdockregp01.ingramcontent.com:8080/prodstat:latest" | egrep -iv "exited" | awk '{print $1 ":" $2}'
#        - yields a list of matching container ID and image name pairs
# 3. Tell the docker runtime server to stop the relevant container ID(s)
# 4. Tell the docker runtime server to run the new container process

# Make sure ${1} is a resolvable hostname
if [ ${exit_code} -eq ${SUCCESS} ]; then

    if [ "${1}" != "" ]; then
        remote_host=`echo "${1}" | sed -e 's?:?\ ?g' | awk '{print $1}' | sed -e 's?\`??g'`
        remote_port=`echo "${1}" | sed -e 's?:?\ ?g' | awk '{print $2}' | sed -e 's?[^0-9]??g' -e 's?\`??g'`
        shift
    
        # Make sure host is resolvable
        let valid_host=`host ${remote_host} 2> /dev/null | egrep -ic "domain name pointer|has address"`
    
        if [ ${valid_host} -eq 0 ]; then
            exit_code=${ERROR}
        else
    
            if [ "${remote_port}" != "" ]; then
                let docker_mgr_port=${remote_port}
    
                if [ ${docker_mgr_port} -gt 65535 -o ${docker_mgr_port} -lt 1 ]; then
                    exit_code=${ERROR}
                fi
    
            fi
    
        fi
    
    fi

fi

# Make sure we have at least one command
if [ ${exit_code} -eq ${SUCCESS} ]; then

    if [ "${1}" != "" ]; then
    
        # Rip through commands and assign them
        while (( "${#}" )); do
            command=""
            key=`echo "${1}" | sed -e 's?\`??g'`
    
            case "${key}" in
    
                list)
                    command="${key}"
                    shift
                ;;
    
                pull|run|stop)
                    value=`echo "${2}" | sed -e 's?\`??g'`
    
                    if [ "${value}" = "" ]; then
                        exit_code=${ERROR}
                    else
                        command="${key}=\"${value}\""
                        shift
                        shift
                    fi
    
                ;;

                *)
                    # Exit ... quietly, peacefully, and enjoy it
                    exit
                ;;
    
            esac
    
            # Execute commands if possible
            if [ "${command}" != "" ]; then

                case ${command} in

                    list)
                        echo "${command}" | nc ${remote_host} ${docker_mgr_port}
                    ;;

                    *)
                        # Replace spaces with spaceholders
                        sanitized_command=`echo "${command}" | sed -e 's?\ ?:ZZqC:?g' | sed -e 's?\`??g'`
                        #echo "My command is: ${sanitized_command}"
                        echo "${sanitized_command}" | nc ${remote_host} ${docker_mgr_port}
                        return_code=`echo "${command}" | nc ${remote_host} ${docker_mgr_port}`

                        if [ ${return_code} -ne ${SUCCESS} ]; then
                            exit_code=${ERROR}
                        fi

                    ;;

                esac
 
            fi
    
        done
    
    fi

fi

exit ${exit_code}
