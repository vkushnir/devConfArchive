#!/bin/bash
#
# devConfSave.sh - Save runing configs from rsyslog
#
###########################################################################

bin="/usr/bin"
. /etc/devConfVars.conf

thisFN=`basename $0`

while read -r line; do
  mode=${line%%::*}
  data=${line#*::}
  date='date +"%F %T"'
  echo "$thisFN: [$date] START, mode: $mode, data: $data" >> $logFile
 
  case $(echo $mode | cut -d: -f1,2) in
    CFG:CISCO) 
      case $(echo $mode | cut -d: -f3) in
        RUN) $bin/devConfSaveCISCO.sh $data ;;
      esac ;;
    CFG:ZyXEL)
      case $(echo $mode | cut -d: -f3) in
        RUN) $bin/devConfSaveZyXEL.sh -m RUN $data ;;
        STU) $bin/devConfSaveZyXEL.sh -m STU $data ;;
      esac ;;
  esac
done

