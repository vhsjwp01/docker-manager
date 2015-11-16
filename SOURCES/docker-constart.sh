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
COMMAND_FILE="/etc/sysconfig/docker-constart"

# See how we were called.
case "$1" in

    start)
        echo "Starting persistent docker containers ... "

        if [ -e "${COMMAND_FILE}" ]; then
            docker_commands=$(awk '{print $0}' "${COMMAND_FILE}" | sed -e 's?\ ?:zzQc:?g')

            for docker_command in ${docker_commands} ; do
                this_docker_command=$(echo "${docker_command}" | sed -e 's?:zzQc:?\ ?g')
                echo "  INFO:  Running docker command:"
                echo "         ${this_docker_command}"
                echo -ne "         ... "
                eval "${this_docker_command}" > /dev/null 2>&1

                if [ ${?} -eq 0 ]; then
                    success
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
  
    status)
        echo "Currently running containers:"
        echo "============================="
        docker ps -f status=running
        echo -ne "============================="
        success
        echo
    ;;

esac
