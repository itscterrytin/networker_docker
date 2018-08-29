#!/usr/bin/env bash

function wait_for_networker_startup {
while ! pgrep -x nsrmmd >/dev/null; do
   echo 'waiting for nsrmmd'
   sleep 30
done
}

# Function bootstrap
# Parameters: bootstrapinfo, a string with format: "ssid,file,record,volume"
#
# This function recovers the networker server from a bootstrap save set.
# It:
#   - defines the device that contains the bootstrap saveset using the
#     resource file /bootstrapdevice.  This resource file must define a
#     read-only resource.
#   - recovers the bootstrap with the given bootstrapid using the mmrecov command.
#     (the 'nsrdr' command is not used because mmrecov allows to recover 
#     a subset of resources, hence resources that are not
#     available or not needed in the DR test environment can be 'masked'.

function bootstrap {

BootStrapId=${1%,*}
Volume=${1#*,}
Device=$(sed -r -n -e  's/^\s*(.*)name:\s*([^;]+)\s*(.*)/\2/p' /bootstrapdevice )

# Create a networker resource for the device containing the
# backup filesets and bootstraps
nsradmin -i /bootstrapdevice
wait_for_networker_startup

#scan and mount $Device
scanner -m $Device
nsrmm -m $Volume -f $Device -r

TERM=xterm nsrdr -a -B $BootStrapId -d $Device -v

# Unmount all volumes
nsrmm -u -y

# Disable all workflows
nsrpolicy policy list |\
    while read -r pol; do
        nsrpolicy workflow list -p "$pol" |\
            while read -r wfl; do
                nsrpolicy workflow update -p "$pol" -w "$wfl" -u No -E No
            done
        done

# Disable devices and delete vproxies
nsradmin -i /mask_devices.nsradmin

# Re-enable and mount our Disaster Recovery Device (read only)
nsradmin <<EOF
. name:$Device
update enabled:Yes;read only:No
y
EOF

# Recover the client indexes
# Restrict recovery to indexes available on our disaster recovery volume
# use the -t option of nsrck to prevent it from trying
# to restore a more recent index that might be present on another volume 
mminfo -q volume=$Volume -r client | sort -u |\
    while read -r client; do
        SaveTime=$(mminfo -v -ot -N "index:$client" -q level=full -r 'savetime(22)' $Volume | tail -1)
        nsrck -L7 -t "$SaveTime" $client
    done

# run post nsrdr scripts
for i in `find /postdr -name '*.sh' | sort -n`; do $i ; done

# reset NMC administrator password
newPassword=$(grep EMC_LOCALADMIN_PASSWORD /authc_configure.resp | cut -d'=' -f2)
cp /opt/nsr/authc-server/scripts/authc-local-config.json.template /nsr/authc/conf/authc-local-config.json
sed -i 's/your_username/administrator/' /nsr/authc/conf/authc-local-config.json
sed -i 's/your_encoded_password/'$(echo -n $newPassword | base64)'/' /nsr/authc/conf/authc-local-config.json
chmod 755 /nsr/authc/conf/authc-local-config.json
/etc/init.d/gst stop; /etc/init.d/networker stop
sleep 3
/etc/init.d/networker start; /etc/init.d/gst start
}

########
#
# MAIN
#
########
# This script requires bootstrap info
# as a string with format: "ssid,file,record,volume"
[ -z "$1" ] && exit 1
set -x

BootStrapInfo=$1
Volume=${BootStrapInfo#*,}

echo "Bootstrap Info: $BootStrapInfo"

# run authc_configure.sh
if [ ! -f /nsr/authc/bin/authcrc ]; then 
 sed -i -r -e "s/_secret_/pW+$(date +%N)$RANDOM$$._k/" /authc_configure.resp
 /opt/nsr/authc-server/scripts/authc_configure.sh  -silent /authc_configure.resp
 sed -i -r -e 's/(TCUSER=).*/\1root/' /nsr/authc/bin/authcrc
fi

/etc/init.d/networker start
sleep 30

# run nmc_config
if [ -z $(grep postgres /etc/passwd) ]; then
 useradd postgres
 echo | echo | echo | echo | echo | /opt/lgtonmc/bin/nmc_config
else
 /etc/init.d/gst start
fi

#
# only perform bootstrap recovery if our volume is not mounted
# this allows to restart a stopped container without losing state
nsrmm | grep mounted | grep -q $Volume || bootstrap $BootStrapInfo

# Listen for incoming recover requests 
# use socat in stead of netcat casue the latter
# does not behave consistently between linux distributions
wait_for_networker_startup

#add trust to auth service
nsrauthtrust -H localhost -P 9090
nsraddadmin -H localhost -P 9090

# Find out to which pool our volume belongs
# Recovery will be restricted to filesets in this pool
Pool=$(mmpool $Volume | grep ^$Volume | cut -f2 -d ' ')

echo "$HOSTNAME is open for recovery"
echo "Listening on $(expr match "$RecoverySocket" '\([^,]\+\)')"
echo "Usage: echo <client> <path> <uid> | socat -,ignoreeof <socket>"

socat "$RecoverySocket"  EXEC:"/recover.sh $Pool"
