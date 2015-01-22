#!/bin/bash
#set -x

PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin
TERM=vt100
export TERM PATH

SUCCESS=0
ERROR=1

LOGFILE="/var/log/docker-mgr.log"

exit_code=${ERROR}

read input

if [ "${input}" != "" ]; then
    key=`echo "${input}" | awk -F'=' '{print $1}'`
    value=`echo "${input}" | sed -e "s?^${key}=??g" -e 's/:ZZqC:/\ /g' -e 's/\"//g'`

    case ${key} in

        list)
            docker ps -a
            echo "`date`: Running command \"docker ps -a\"" >> "${LOGFILE}"
        ;;

        pull|run|stop)

            if [ "${value}" != "" ]; then
                echo "`date`: Running command \"docker ${key} ${value}\"" >> "${LOGFILE}"
                eval docker ${key} ${value} > /dev/null 2>&1
                return_code=${?}
                echo "${return_code}"
            fi

        ;;

        *)
            # Exit ... quietly, peacefully, and enjoy it
            exit
        ;;
            
    esac

fi
