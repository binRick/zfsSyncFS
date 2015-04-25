#!/bin/sh
SEND_ARGS=""
RECV_ARGS="-Fduv"
ZPOOL_ok=0
ZFS_ok=0
ZPOOL=`echo $1 | cut -d"/" -f1`
ZFS=`echo $1 | cut -d"/" -f2-20`
today=`date +"%Y-%m-%d"`
yesterday=`date -d "-1 day" +"%Y-%m-%d"`
remote=$2
SNAPCOMMAND="zfs-auto-snapshot -k 2 -p Snapshots $ZPOOL/$ZFS"
remote_pool=$3
prefix=$4
FULL_LOCAL=$ZPOOL/$ZFS
local=`hostname -s`
for last; do true; done
lastArg=$last
#clear

#echo "last Argument == $lastArg"

test $lastArg == "--snap" && echo "Creating new snapshot on $FULL_LOCAL" && zfs-auto-snapshot -k 2 -p SnapSyncSpecified -v $FULL_LOCAL

destination="$remote_pool"
ssh $remote zfs list $destination >/dev/null 2>&1 && echo "$destination exists on $remote " || ( echo "cannot find \"$destination\" on $remote" && exit 1 )


#if [ -z "$prefix" -a "${prefix+xxx}" = "xxx" ]; then echo prefix is set but empty; fi
#if [ -z "${prefix+xxx}" ]; then echo prefix is not set at all; fi
#if [ -z "$prefix" ] && [ "${prefix+xxx}" = "xxx" ]; then echo prefix is set but empty; fi

if [ -z "$prefix" ] ; then
    destination="$remote_pool/Snapshots"
else
    RECV_ARGS="-Fv"
    destination="$prefix"
fi
ssh $remote zfs list $destination >/dev/null 2>&1 && echo "$destination exists on $remote " || ( echo "Creating $destination on $remote " && ssh $remote zfs create $destination || exit 1 )

if [ -z "$prefix" ] ; then
    destination="$destination/$local"
    ssh $remote zfs list $destination >/dev/null 2>&1 && echo $(tput sgr0) && echo $(tput setaf 154) && echo "$destination exists on $remote " || ( echo "Creating $destination on $remote " && ssh $remote zfs create $destination || exit 1 )
    FULL_REMOTE_NO_POOL=$destination
fi

#echo $(tput sgr0) && echo $(tput setaf 154) 
#echo zpool = $ZPOOL
#echo destination = $destination
#echo $(tput sgr0)

if [ -z "$prefix" ] ; then
    destination="$destination/$ZPOOL"
fi
ssh $remote zfs list $destination >/dev/null 2>&1 && echo "$destination exists on $remote " || ( echo "Creating $destination on $remote " && ssh $remote zfs create $destination || exit 1 )
FULL_REMOTE=$destination

#echo "Full Remote = $FULL_REMOTE"

ssh $remote zfs list -H -o name $FULL_REMOTE >/dev/null 2>&1 || ( ssh $remote zfs create $FULL_REMOTE >/dev/null 2>&1 || ( echo "Cannot connect to host $remote and list $FULL_REMOTE" && exit 1 ) )


#echo ""
#echo ""
#echo "ZPOOL = \"$ZPOOL\"   ZFS = \"$ZFS\"   "

zpool list -H -o name | grep "^$ZPOOL$" >/dev/null 2>&1 && ZPOOL_ok=1 || ( echo "cannot list local pool \"$ZPOOL\". Quantity of Possible pools:" &&  zpool list -H -o name | wc -l && echo "First 5: " && zpool list -H -o name | head -n 5 )
test $ZPOOL_ok == "1" || exit 1
#echo "	Zpool OK"

#snapshot_today_remote="$destination/$zfs@$today"
zfs list -H -o name | grep "^$FULL_LOCAL$" >/dev/null  && ZFS_ok=1 || ( echo "cannot list zfs \"$FULL_LOCAL\". Quantity of Possible zfs: " && zfs list -H -o name | wc -l && echo "First 5: " && zfs list -H -o name | head -n 5 )
test $ZFS_ok == "1" || exit 1
#echo "	ZFS OK"
#echo ""
#echo "Checking Today's Snapshot"
#zfs list -t snap $FULL_LOCAL@$today >/dev/null 2>&1 || ( echo "Todays Snapshots detected. Creating Todays" && zfs snapshot $FULL_LOCAL@$today >/dev/null 2>&1 && echo "Created Snapshot $FULL_LOCAL@$today" || ( echo "Unable to create Snapshot of $FULL_LOCAL@$today" && exit 1) )

zfs list -H -o name -t snap | grep "^${FULL_LOCAL}@" >/dev/null 2>&1 || ( echo "No Local Snapshots for $FULL_LOCAL found. Creating snapshot.   " && $SNAPCOMMAND  || exit 1 )
#( echo "No Local Snapshots for $FULL_LOCAL found. Failure" && exit 1 )

let "COUNT=0"

for SNAPSHOT in `zfs list -H -o name -t snap |  grep "^${FULL_LOCAL}@"`; do
	echo "Working on Snap $SNAPSHOT  :: $COUNT"
	test "$COUNT" == "0" && {
		zSendArgs=""
		zRecvArgs=""
	} || {
		zSendArgs="-i $prevSnapshot"
		zRecvArgs=""
	}
    CMD="zfs send $SEND_ARGS ${zSendArgs} ${SNAPSHOT} | ssh $remote zfs recv $RECV_ARGS ${zRecvArgs} $FULL_REMOTE"
#    echo "Checking if this exists on $remote" && echo "Remote Snapshots:"
#    echo "Looking for matches to $SNAPSHOT in ZFS $ZFS"
	ccMD="zfs list -H -t snap | grep \"$remote_pool/Snapshots/$local/$SNAPSHOT\""
#echo "ccMD =    $ccMD     "
#echo "end ccMD"
#	ssh $remote $ccMD
#echo "end ccMD out"

    ssh $remote $ccMD >/dev/null || ( echo "Does not exist remotely." \
        && echo $(tput setaf 4) && echo "Syncing snapshot $SNAPSHOT to $FULL_REMOTE" && echo $(tput sgr0) && echo $(tput setaf 154) && \
        zfs send $SEND_ARGS ${zSendArgs} ${SNAPSHOT} | pv | ssh $remote zfs recv $RECV_ARGS ${zRecvArgs} $FULL_REMOTE ) 
        echo $(tput sgr0)
	prevSnapshot=$SNAPSHOT
	let "COUNT++"
done


exit 0
