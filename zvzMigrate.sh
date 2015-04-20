#!/bin/bash
Rsync='/usr/local/rsync/bin/rsync --numeric-ids --info=progress2 -ar'
process=$3
x=`echo $1 | cut -d"/" -f2`
p=`echo $1 | cut -d"/" -f1`
d=`echo $2 | cut -d":" -f1`
rp=`echo $2 | cut -d":" -f2`
me=$(hostname -s)
ts=$(date +%s)
cmdFile=/root/.zvzMigrate____${ts}

GB=`zfs get used $p/$x -H -o value| head -n 1`
B=`zfs get used $p/$x -p -H -o value| head -n 1`
dFreeGB=`zfs get available $rp -H -o value| head -n 1`
dFreeB=`zfs get available $rp -p -H -o value| head -n 1`
diffBytes=`echo "${dFreeB}-${B}" | bc`
echo "" && echo "" && \
    echo -ne $COLOR_GREEN && echo "Copying FS $x of $GB GB to $d => $RP available: $dFreeGB " && echo ""  && echo "" && \
    echo "" && echo "" && \
        echo -ne "$COLOR_BLUE" && echo "   $x Used Bytes: $B" && \
        echo -ne "$COLOR_YELLOW" && echo "   $d => $rp Free Bytes: $dFreeB" && \
        echo "" && echo "" && \
        echo -ne "$COLOR_RED" && echo "      Bytes left on $d => $rp after transfer: $diffBytes" && \
    echo "" && echo "" && \
    echo -ne $COLOR_RESET

ps axfuw | grep SnapSync | grep grep -v | grep " $p/$x " && echo -ne $COLOR_RED && echo "Process already workign with this FS" && \
    echo "" && echo "" && \
    exit -1

echo -ne $COLOR_GREEN && \
    echo cat $cmdFile && echo -ne $COLOR_RESET

echo "#" && echo -ne $COLOR_GREEN && zfs list tank/$x && echo -ne $COLOG_RED &&  ssh $d zfs get available tank && \
    echo sleep 60 \
    && echo -ne $COLOR_RESET  &&  \
    cat << EOF > $cmdFile



vzlist -o private $x | grep "^/vz/private/$x" && ls /vz/private/$x/etc/passwd && \
	mkdir /tank/$x/root -p && \
	Rsync /vz/private/$x /tank/$x/private/ && vzctl stop $x && Rsync /vz/private/$x /tank/$x/private/ && vzctl set $x --diskquota no --private /tank/$x/private/$x --save --root /tank/$x/root --save && vzctl start $x && sleep 5 && vzctl exec $x ping 4.2.2.1 -c 1 | grep ' 0% loss'





vzlist -o private $x | grep "^/vztank/private/$x" && ls /vztank/private/$x/etc/passwd && \
mkdir /tank/$x/root -p && \
Rsync /vztank/private/$x /tank/$x/private/ && vzctl stop $x && Rsync /vztank/private/$x /tank/$x/private/ && vzctl set $x --diskquota no --private /tank/$x/private/$x --save --root /tank/$x/root --save && vzctl start $x && sleep 5 && vzctl exec $x ping 4.2.2.1 -c 1 | grep ' 0% loss'

vzlist $x >/dev/null && $Rsync /z/$x.conf $d:/z/ >/dev/null && \
 ssh $d zfs list $p/$x 2>/dev/null && exit -1 || \
 time zfs-auto-snapshot $p/$x && \
 time ( SnapSyncSpecified.sh $p/$x $d $rp >/dev/null ) && \
 time vzctl stop $x && \
 time zfs-auto-snapshot $p/$x && \
 time ( SnapSyncSpecified.sh $p/$x $d $rp >/dev/null ) && \
 time ssh $d zfs rename $rp/Snapshots/$me/$p/$x $rp/$x && 
 time ssh $d "zfs get mounted -H $rp/$x| grep yes >/dev/null || zfs mount $rp/$x" && \
 time ssh $d vzctl set $x --private /$rp/$x/private/$x --root /$rp/$x/root --save --diskquota no && \
 time sleep 5 && \
 time ssh $d vzctl start $x && \
 sleep 5 && \
 time ssh $d vzctl exec $x ping 4.2.2.1 -c 1 | grep " 0% packet loss" && \
 time vzctl set $x --ipdel all --disabled yes --save && \
 exit 0

echo -ne $COLOR_RED
echo vzctl start $x
echo ssh $d zfs rename $rp/$x $rp/Snapshots/$me/$p/$x 2>/dev/null >/dev/null
echo -ne $COLOR_RESET

EOF



if [ "$process" == "--migrate" ]; then
  echo -ne $COLOR_GREEN && echo "" && echo "" && echo "Migrating" && \
    echo "" && echo "" && \
    echo -ne $COLOR_RESET
    echo $cmdFile
    cat $cmdFile
    exit 0
fi
