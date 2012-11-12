#!/bin/sh
#
# devConfSaveCisco.sh - Save runing configs
# devConfSaveCisco.sh <ip> <name> <text>
#
###########################################################################

# Variables
# read variables from config file
. /etc/devConfArchive.conf
# tftpRoot="*****"
# tftpServer="****"
# snmpRW="****"

Y=`date +%Y`
M=`date +%m`
D=`date +%d`

tftpDevRunRoot="${tftpRoot}/devConf/running/${Y}/${Y}-${M}/${Y}-${M}-${D}"
logFile="/var/log/devices/devConfSave.log"

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
if [ $# = 3 ]; then
  devIP=$1
  devNAME=$2
  devLog=$3
else
  devIP=`echo $1 | cut -d'|' -f1`
  devNAME=`echo $1 | cut -d'|' -f2`
  devLog=`echo $1 | cut -d'|' -f3`
fi

r=$RANDOM
if [ $devIP != $devNAME ]; then
  devID="${devIP}-${devNAME}"
else
  devID="${devIP}"
fi

n=1
fn="${devID}_${n}.txt"
while [ -f ${tftpDevRunRoot}/${fn} ]; do
  echo "Check File: $fn"
  n=$(($n+1));
  fn="${devID}_${n}.txt";
done

echo "CONFIG IP: $devIP, NAME: $devNAME, TEXT: $devLog, FileName: $fn" >> $logFile
echo "Location: ${tftpDevRunRoot}" >> $logFile
r=1
snmpset -v 2c -O qv -t 5 -c $snmpRW $devIP CISCO-CONFIG-COPY-MIB::ccCopyProtocol.$r i $tftp >> $logFile
snmpset -v 2c -O qv -t 5 -c $snmpRW $devIP CISCO-CONFIG-COPY-MIB::ccCopySourceFileType.$r i $runningConfig
snmpset -v 2c -O qv -t 5 -c $snmpRW $devIP CISCO-CONFIG-COPY-MIB::ccCopyDestFileType.$r i $networkFile
snmpset -v 2c -O qv -t 5 -c $snmpRW $devIP CISCO-CONFIG-COPY-MIB::ccCopyServerAddress.$r a $tftpServer
snmpset -v 2c -O qv -t 5 -c $snmpRW $devIP CISCO-CONFIG-COPY-MIB::ccCopyFileName.$r s $fn >> $logFile
snmpset -v 2c -O qv -t 5 -c $snmpRW $devIP CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus.$r i $active

n=1
ccCopyState=$(snmpget -Oqv -v 2c -m ALL -c $snmpRW $devIP CISCO-CONFIG-COPY-MIB::ccCopyState.$r)
while [ "$ccCopyState" = "active" -o "$ccCopyState" = "running" ]; do
  sleep 1s
  ccCopyState=$(snmpget -Oqv -v 2c -m ALL -c $snmpRW $devIP CISCO-CONFIG-COPY-MIB::ccCopyState.$r)
  n=$(($n+1));
  if [ n -gt 10 ]; then
    echo " Too long process! Exit."
    break
  fi
done
snmpget -v 2c -m ALL -c $snmpRW $devIP CISCO-CONFIG-COPY-MIB::ccCopyState.$r >> $logFile
snmpset -v 2c -O qv -t 5 -c $snmpRW $devIP CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus.$r i $destroy

# TYPE: one of i, u, t, a, o, s, x, d, b, n
#        i: INTEGER, u: unsigned INTEGER, t: TIMETICKS, a: IPADDRESS
#        o: OBJID, s: STRING, x: HEX STRING, d: DECIMAL STRING, b: BITS
#        U: unsigned int64, I: signed int64, F: float, D: double

#Set date folder
mkdir -p $tftpDevRunRoot
chown -R tftpd:tftpd $tftpDevRunRoot
mv -f ${tftpRoot}/$fn ${tftpDevRunRoot}/${fn} >> $logFile
echo "" >> $logFile
