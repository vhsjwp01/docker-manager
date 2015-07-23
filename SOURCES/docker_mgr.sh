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

################################################################################
# DESCRIPTION
################################################################################
#

# NAME: docker_mgr
# 
# This script is meant to be invoked by xinetd, after which it processes
# whatever string is was sent and matches the parsing with allowed operations
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

################################################################################
# VARIABLES
################################################################################
#

exit_code=${ERROR}

################################################################################
# MAIN
################################################################################
#

read input
let input_wc=`echo "${input}" | wc -w | awk '{print $1}'`

if [ "${input}" != "" -a ${input_wc} -eq 1 ]; then
    key=`echo "${input}" | awk -F'=' '{print $1}' | sed -e 's?\`??g'`
    value=`echo "${input}" | sed -e "s?^${key}=??g" -e 's?:ZZqC:?\ ?g' -e 's?\"??g' -e 's?\`??g'`

    case ${key} in

        list)
            echo "`date`: Running command \"docker ps -f status=running\"" >> "${LOGFILE}"
            docker ps -f status=running
        ;;

        pull|run|stop)

            if [ "${value}" != "" ]; then
                echo "`date`: Running command \"docker ${key} ${value}\"" >> "${LOGFILE}"
                #eval docker ${key} ${value} > /dev/null 2>&1
                eval docker ${key} ${value} > /tmp/docker.$$.err 2>&1
                return_code=${?}
                cmd_output=""

                if [ -e "/tmp/docker.$$.err" ]; then 
                    raw_output=`awk '{print $0}' /tmp/docker.$$.err | strings | sed -e 's/\[.*\]//g' -e 's/\ /:ZZqC:/g' | egrep -i "error"`

                    for raw_line in ${raw_output} ; do
                        real_line=`echo "${raw_line}" | sed -e 's/:ZZqC:/\ /g'`

                        if [ "${cmd_output}" = "" ]; then
                            cmd_output="${real_line}"
                        else
                            cmd_output="${cmd_output}\n${real_line}"
                        fi

                    done

                    rm /tmp/docker.$$.err
                fi

                echo "${return_code}::${cmd_output}"
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
