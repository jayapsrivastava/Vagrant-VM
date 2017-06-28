#!/bin/bash
set -x


function setup_zfs()
{
  ZPOOL=$1
  /usr/sbin/modprobe zfs
  [ $? -ne 0 ] && { echo -n  "modprobe zfs failed"; exit 1; }
  /usr/sbin/lsmod | grep zfs 
  [ $? -ne 0 ] && { echo "zfs not loaded"; exit 1; }

  if [ $ZPOOL == "cust-pool" ]
  then
    for i in 0 1; do dd if=/dev/zero of=/tmp/zfs-test-disk0${i}.img bs=1G count=1;  done;
    /usr/sbin/zpool create $ZPOOL /tmp/zfs-test-disk00.img /tmp/zfs-test-disk01.img >> /dev/null 
    [[ $? -ne 0 ]] && { echo "Failed to create zpool"; exit 1; }
  else
    for i in 2 3; do dd if=/dev/zero of=/tmp/zfs-test-disk0${i}.img bs=1G count=1;  done;
    /usr/sbin/zpool create $ZPOOL /tmp/zfs-test-disk02.img /tmp/zfs-test-disk03.img  >> /dev/null 
    [[ $? -ne 0 ]] && { echo "Failed to create zpool"; exit 1; }
  fi
  /usr/sbin/zpool status | grep $ZPOOL >> /dev/null 
  [[ $? -ne 0 ]] && { echo "Created pool not found"; exit 1; }
  /usr/bin/systemctl preset zfs-import-cache zfs-import-scan zfs-mount zfs-share zfs-zed zfs.target

  cat <<EOF >/etc/rc.local
#!/bin/bash
# THIS FILE IS ADDED FOR COMPATIBILITY PURPOSES
#
# It is highly advisable to create own systemd services or udev rules
# to run scripts during boot instead of using this file.
#
# In contrast to previous versions due to parallel execution during boot
# this script will NOT be run after all other services.
#
# Please note that you must run 'chmod +x /etc/rc.d/rc.local' to ensure
# that this script will be executed during boot.

sleep 5 ;  zfs mount -a
touch /var/lock/subsys/local
EOF
    chmod 755 /etc/rc.local
}

function setup_lustre_role()
{
set -x
  declare -a NODE_OPT
  NODE_OPT=("$@")
  MGS_VM=`hostname`
  MGS_IP=`cat /etc/hosts | grep $MGS_VM | tail -n 1 | awk '{print $1}'`
  if [ "${NODE_OPT[1]}" == "custfs" ]
  then
    MNT_POINT=`cat /vagrant/config | grep MNT_PNT_CUST | awk -F"=" '{print $2}'`
  else
    MNT_POINT=`cat /vagrant/config | grep MNT_PNT_CS | awk -F"=" '{print $2}'`
  fi

  /usr/sbin/chkconfig lustre on
  /usr/bin/systemctl start lustre
  /usr/sbin/modprobe lnet
  /usr/sbin/modprobe lustre

  echo "options lnet networks=tcp0(ens32)" > /etc/modprobe.d/lnet.conf 

  case "${NODE_OPT[0]}" in 
    'mgs')
            /usr/sbin/mkfs.lustre --"${NODE_OPT[0]}" --backfstype=zfs --reformat --verbose "${NODE_OPT[2]}"/"${NODE_OPT[0]}"
            echo "$MGS_VM - "${NODE_OPT[0]}" zfs:"${NODE_OPT[2]}"/"${NODE_OPT[0]}"" >> /etc/ldev.conf
            mkdir -p /mnt/lustre/local/"${NODE_OPT[0]}"
            /usr/sbin/mount.lustre "${NODE_OPT[2]}"/"${NODE_OPT[0]}" /mnt/lustre/local/"${NODE_OPT[0]}"
            ;;

    'mdt')  
            /usr/sbin/mkfs.lustre --"${NODE_OPT[0]}" --mgsnode=$MGS_IP@tcp0 --fsname="${NODE_OPT[1]}" --backfstype=zfs --reformat --verbose "${NODE_OPT[2]}"/"${NODE_OPT[0]}" 
            echo "$MGS_VM - "${NODE_OPT[1]}"-MDT0000 zfs:"${NODE_OPT[2]}"/"${NODE_OPT[0]}"" >> /etc/ldev.conf
            mkdir -p /mnt/lustre/local/"${NODE_OPT[1]}"-"${NODE_OPT[0]}"
            /usr/sbin/mount.lustre "${NODE_OPT[2]}"/"${NODE_OPT[0]}" /mnt/lustre/local/"${NODE_OPT[1]}"-"${NODE_OPT[0]}" 
            ;;
    'ost')  /usr/sbin/mkfs.lustre --"${NODE_OPT[0]}" --mgsnode=$MGS_IP@tcp0 --backfstype=zfs --index=1 --fsname="${NODE_OPT[1]}" --reformat --verbose "${NODE_OPT[2]}"/""${NODE_OPT[0]}""1""
            echo "$MGS_VM - "${NODE_OPT[1]}"-OST0001 zfs:"${NODE_OPT[2]}"/""${NODE_OPT[0]}""1""" >> /etc/ldev.conf
            mkdir -p /mnt/lustre/local/"${NODE_OPT[1]}"-""${NODE_OPT[0]}""1""
            /usr/sbin/mount.lustre "${NODE_OPT[2]}"/""${NODE_OPT[0]}""1"" /mnt/lustre/local/"${NODE_OPT[1]}"-""${NODE_OPT[0]}""1"" 
            ;;

    'client')  mkdir -p "/$MNT_POINT"
               /usr/bin/mount -t lustre -o user_xattr $MGS_IP@tcp0:/"${NODE_OPT[1]}" "/$MNT_POINT"
               echo "$MGS_IP@tcp0:/"${NODE_OPT[1]}" "/$MNT_POINT" lustre defaults,_netdev,user_xattr 0 00" >> /etc/fstab
               /usr/bin/lfs df -h
               ;;
  esac
  /usr/sbin/lctl dl
}



if [ $# -eq 4 ]
then
  FUNC=$1
  declare -a ARGS 
  ARGS=("$2" "$3" "$4")
  "$FUNC" "${ARGS[@]}"
elif [ $# -eq 2 ]
then
  FUNC=$1
  "$FUNC" "$2"
else
  echo "Missing args !!"
  exit 1
fi


