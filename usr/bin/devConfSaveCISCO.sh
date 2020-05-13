#!/bin/sh
#
# devConfSaveCisco.sh - Save runing configs
# devConfSaveCisco.sh -i <ip> [-n <name>] [<text>]
#
###########################################################################

# Variables
# read variables from config file
. /etc/devConfVars.conf
# snmpCommunity="****"
# tftpRoot="****"
# tftpServer="****"
# tftpWait="****"
# dirRunning="****"
# dirStartup="****"
# logFile="****"
# diffOpt="-iubEB"
# lookWait=n

Y=`date +%Y`
M=`date +%m`
D=`date +%d`
thisFN=`basename $0`

# SNMP CISCO
# ConfigCopyProtocol
tftp=1; ftp=2; rcp=3; scp=4; sftp=5
# ConfigFileType
networkFile=1; iosFile=2; startupConfig=3; runningConfig=4; terminal=5; fabricStartupConfig=6
# ConfigCopyState
waiting=1; running=2; successful=3; failed=4
# RowStatus
active=1; notInService=2; notReady=3; createAndGo=4; createAndWait=5; destroy=6
# Get Parameters

if [ $# -lt 1 ]; then
  echo "$thisFN: No options found! [$@]"
  exit 1
fi

devIP="noip"
while getopts "i:n:" opt; do
  case $opt in
    i) devIP=$OPTARG;;
    n) devNAME=$OPTARG;;
#    l) devLOG=$OPTARG;;
    *) echo "$thisFN: Specify IP address" >> $logFile; exit 1;;
  esac
done
shift $((OPTIND-1))
devLog=$@

if [ $devIP == "noip" ]; then
  echo "$thisFN: Specify IP address" >> $logFile
  echo "Specify IP address"
  exit 1
fi

r=$RANDOM
saveIFS=$IFS
IFS='.'
devID=$(printf "%03d.%03d.%03d.%03d" $devIP)
IFS=$saveIFS

#devID="${devIP}"
#if [ "$devNAME" != "" -a "$devNAME" != "$devIP" ]; then
#  devID="${devIP}-${devNAME}"
#fi

# Lock process to prevent run two or more script on same device
(
  flock -w $lockWait 200
  if [ "$?" != "0" ]; then
    echo "$thisFN: Process for device: $devIP already started! Exit." >> $logFile
    echo "" >> $logFile
    exit 1
  fi
  echo $$>>/var/lock/$thisFN.$devID.lock #for backward lockdir compatibility

  tftpDevRoot="${tftpRoot}/${dirRunning}/${Y}/${devID}/${Y}-${M}"

  gfn="${devID//./\\.}.*_[0-9]*\.cfg"
  pfn=$(printf "%s-%s%s%s" $devID $Y $M $D)

  # Generate file name
  if [ -d $tftpDevRoot ]; then
    n=$(ls -1 --reverse $tftpDevRoot | grep $gfn | head -1 | cut -f2 -d_ | cut -f1 -d.)
    if [[ $n =~ ^[0-9]+$ ]]; then
      n=${n##0}
    else
      n=1
    fi
  else
    n=1
  fi
  j=1
  fn=$(printf "${pfn}_%02d.cfg" $n)
  while [ -f ${tftpDevRoot}/${fn} ]; do
    let n++
    let j++
    if [ $j -gt 199 ]; then
      echo "$thisFN: Error with filename generation !!!" >> $logFile
      echo "$thisFN: CONFIG IP: $devIP, NAME: $devNAME, FileName: $fn, TEXT: $devLog" >> $logFile
      echo "$thisFN: Location: ${tftpDevRoot}" >> $logFile
      echo "" >> $logFile
      exit 1
    fi
    if [ $n -gt 99 ]; then
      n=1
      ls --sort=time --reverse $tftpDevRoot | grep $gfn | head -1 | xargs -I {} -t rm -f $tftpDevRoot/{}
    fi
    fn=$(printf "${pfn}_%02d.cfg" $n)
  done

  echo "$thisFN: CONFIG IP: \"$devIP\", NAME: \"$devNAME\", FileName: \"$fn\", TEXT: \"$devLog\"" >> $logFile
  echo "$thisFN: Location: ${tftpDevRoot}" >> $logFile
  # r=1
  snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyProtocol.$r i $tftp
  RETVAL=$?
  if [ $RETVAL -eq 1 ]; then echo " SNMP operation ccCopyProtocol error!!!" >> $logFile; exit 1; fi
  snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopySourceFileType.$r i $runningConfig
  RETVAL=$?
  if [ $RETVAL -eq 1 ]; then echo " SNMP operation ccCopySourceFileType error!!!" >> $logFile; exit 1; fi
  snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyDestFileType.$r i $networkFile
  RETVAL=$?
  if [ $RETVAL -eq 1 ]; then echo " SNMP operation ccCopyDestFileType error!!!" >> $logFile; exit 1; fi
  snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyServerAddress.$r a $tftpServer
  RETVAL=$?
  if [ $RETVAL -eq 1 ]; then echo " SNMP operation ccCopyServerAddress error!!!" >> $logFile; exit 1; fi
  snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyFileName.$r s $fn
  RETVAL=$?
  if [ $RETVAL -eq 1 ]; then echo " SNMP operation ccCopyFileName error!!!" >> $logFile; exit 1; fi
  snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus.$r i $active
  RETVAL=$?
  # if [ $RETVAL -eq 1 ]; then echo " SNMP operation ccCopyEntryRowStatus error!!!" >> $logFile; exit 1; fi
  sleep 1s
  
  i=1
  ccCopyState=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyState.$r)
  RETVAL=$?
  if [ $RETVAL -eq 1 ]; then echo " SNMP operation ccCopyState error!!!" >> $logFile; exit 1; fi
  while [ "$ccCopyState" = "active" -o "$ccCopyState" = "running" ]; do
    sleep 1s
    ccCopyState=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyState.$r)
    RETVAL=$?
    if [ $RETVAL -eq 1 ]; then echo " SNMP operation ccCopyState error!!!" >> $logFile; exit 1; fi
    i=$(($i+1));
    if [ $i -gt $tftpWait ]; then
      echo " Too long process! Exit." >> $logFile
      echo "" >> $logFile
      break
    fi
  done
  snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus.$r i $destroy
  RETVAL=$?
  if [ $RETVAL -eq 1 ]; then echo " SNMP operation ccCopyEntryRowStatus error!!!" >> $logFile; exit 1; fi

  # Store file
  if [ $ccCopyState = "successful" ] && [ -f ${tftpRoot}/${fn} ]; then
    if [ -d $tftpDevRoot ]; then
      flist=$(ls -1 --sort=time --reverse $tftpDevRoot | grep $gfn)
      fcnt=$(echo "$flist" | wc -l)
      if [ $fcnt -ge 1 ]; then
        ff=$(echo "$flist" | head -1)
        lf=$(echo "$flist" | tail -1)
      else
        ff=0
        lf=0
      fi
    else
      fcnt=0
    fi
    if [ -f ${tftpDevRoot}/${lf} ]; then
      diffRes=`diff $diffOpt -qs --ignore-matching-lines='^!' ${tftpRoot}/${fn} ${tftpDevRoot}/${lf}`
      if [[ $diffRes == *identical ]]; then
        echo "$thisFN: New file same as previous." >> $logFile
        echo "" >> $logFile
        rm -f ${tftpRoot}/${fn}
        exit 0
      fi
    fi
    if [ ! -d $tftpDevRoot ]; then
      mkdir -p $tftpDevRoot
      chown -R tftpd:tftpd $tftpDevRoot
      chmod -R 755 $tftpDevRoot
    fi
    mv -f ${tftpRoot}/${fn} ${tftpDevRoot}/${fn}
    chmod 644 ${tftpDevRoot}/${fn}
    echo "" >> $logFile
  
    if [ $fcnt -ge 1 ]; then
      `diff $diffOpt --ignore-matching-lines='^!' ${tftpDevRoot}/${ff} ${tftpDevRoot}/${fn} > ${tftpDevRoot}/${devID}.diff`
    fi
  
  else
    echo "$thisFN: Fail to save [$fn] from [$devIP] with status ($ActionStatus) !!!" >> $logFile
    echo "" >> $logFile
    exit 1
  fi

) 200>/var/lock/$thisFN.$devID.lock
FLOCKEXIT=$?
exit $FLOCKEXIT
