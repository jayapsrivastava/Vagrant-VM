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
    for i in 0 1; do dd if=/dev/zero of=/tmp/zfs-loop-dev0${i}.img bs=1G count=1;  done;
    /usr/sbin/zpool create $ZPOOL /tmp/zfs-loop-dev00.img /tmp/zfs-loop-dev01.img >> /dev/null 
    [[ $? -ne 0 ]] && { echo "Failed to create zpool"; exit 1; }
  else
    for i in 0 1; do dd if=/dev/zero of=/tmp/zfs-loop-dev${i}.img bs=1G count=1;  done;
    /usr/sbin/zpool create $ZPOOL /tmp/zfs-loop-dev0.img /tmp/zfs-loop-dev1.img  >> /dev/null 
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

    'client')  mkdir -p $MNT_POINT
               /usr/bin/mount -t lustre -o user_xattr $MGS_IP@tcp0:/"${NODE_OPT[1]}" "$MNT_POINT"
               echo "$MGS_IP@tcp0:/"${NODE_OPT[1]}" "$MNT_POINT" lustre defaults,_netdev,user_xattr 0 00" >> /etc/fstab
               /usr/bin/lfs df -h
               ;;
  esac
  /usr/sbin/lctl dl
}

function setup_marfs_role()
{
  echo "*set up marfs*"
  
  S3_IP=`cat /vagrant/config | grep S3_IP | awk -F"=" '{print $2}'`
  S3_ACCESS_ID=`cat /vagrant/config | sed -n 's/^ *S3_ACCESS_ID*= *//p'`
  S3_SECRET_KEY=`cat /vagrant/config | grep S3_SECRET_KEY | awk -F"=" '{print $2}'`
  S3_BUCKET=`cat /vagrant/config | grep S3_BUCKET | awk -F"=" '{print $2}'`
  S3_BUCKET_REPO="$S3_BUCKET""repo"
  MNT_MARFS=`cat /vagrant/config | grep MNT_MARFS | awk -F"=" '{print $2}'`

  mkdir -p /camstors/.mdrepos/ #FIX /camstors to /camstor/
  mkdir -p /camstors/.mdrepos/$S3_BUCKET
  touch /camstors/.mdrepos/$S3_BUCKET/fsinfo
  mkdir -p /camstors/.mdrepos/$S3_BUCKET/mdfs
  mkdir -p /camstors/.mdrepos/$S3_BUCKET/trash
  mkdir -p /camstors/.mdrepos/root
  mkdir -p /camstors/.mdrepos/root/mdfs
  touch  /camstors/.mdrepos/root/fsinfo
  mkdir -p $MNT_MARFS #FIX /camstors/archives to /camstor/archive
  
  if [ ! -e /root/.awsAuth ] ; then
    echo "root:$S3_ACCESS_ID:$S3_SECRET_KEY" > /root/.awsAuth
    chmod 600 /root/.awsAuth
  fi


  cat <<EOF >/etc/marfsconfigrc
<config>
    <name>On CentOS7 DevVM</name>
    <version>1.0</version>

    <mnt_top>$MNT_MARFS</mnt_top>

    <mdfs_top>/camstors/.mdrepos</mdfs_top>

    <repo>
      <name>/camstors/.mdrepos</name>

      <host>/camstors/.mdrepos/drepo</host>
      <host_offset>1</host_offset>
      <host_count>1</host_count>
      <update_in_place>no</update_in_place>
      <ssl>no</ssl>
      <access_method>DIRECT</access_method>
      <chunk_size>1073741824</chunk_size> # 1GB
      <max_get_req>0</max_get_req> # no limit (use chunk_size)

      <max_pack_file_count>0</max_pack_file_count> # 0=disable packing, -1=unlimited
      <min_pack_file_count> 10</min_pack_file_count>
      <max_pack_file_size> 104857600</max_pack_file_size> # 100 MB max individual file
      <min_pack_file_size> 1</min_pack_file_size>

      <security_method>NONE</security_method>

      <enc_type>NONE</enc_type>
      <comp_type>NONE</comp_type>
      <correct_type>NONE</correct_type>
      <latency>10000</latency>

      <DAL>POSIX</DAL>
    </repo>

    <repo>
      <name>$S3_BUCKET_REPO</name>
      <host>$S3_IP</host>

      <access_method>S3_EMC</access_method>
      <update_in_place>no</update_in_place>
      <ssl>no</ssl>
      <max_get_size>0</max_get_size>  # unconstrained

      <chunk_size>268435456</chunk_size>  # 256M

      <max_pack_file_count>-1</max_pack_file_count>
      <min_pack_file_count> 10</min_pack_file_count>
      <max_pack_file_size> 104857600</max_pack_file_size> # 100 MB max individual file
      <min_pack_file_size>1</min_pack_file_size>

      <security_method>S3_AWS_MASTER</security_method>

      <enc_type>NONE</enc_type>
      <comp_type>NONE</comp_type>
      <correct_type>NONE</correct_type>
      <latency>10000</latency>
    </repo>

    <namespace>
      <name>$S3_BUCKET</name>
      <alias>$S3_BUCKET</alias>
      <mnt_path>/$S3_BUCKET</mnt_path>
      <bperms>RM,WM,RD,WD,TD,UD</bperms>
      <iperms>RM,WM,RD,WD,TD,UD</iperms>
      <iwrite_repo_name>$S3_BUCKET_REPO</iwrite_repo_name>
      <range>
        <min_size>0</min_size>
        <max_size>-1</max_size>
        <repo_name>$S3_BUCKET_REPO</repo_name>
      </range>
      <md_path>/camstors/.mdrepos/$S3_BUCKET/mdfs</md_path>
      <trash_md_path>/camstors/.mdrepos/$S3_BUCKET/trash</trash_md_path>
      <fsinfo_path>/camstors/.mdrepos/$S3_BUCKET/fsinfo</fsinfo_path>
      <quota_space>1073741824</quota_space>
      <quota_names>32</quota_names>
    </namespace>

    <namespace>
      <name>root</name>
      <alias>proxy1</alias>
      <mnt_path>/</mnt_path>
      <bperms>NONE</bperms>
      <iperms>RM</iperms>
      <md_path>/camstors/.mdrepos/root/mdfs</md_path>
      <iwrite_repo_name>$S3_BUCKET_REPO</iwrite_repo_name>
      <range>
        <min_size>0</min_size>
        <max_size>-1</max_size>
        <repo_name>$S3_BUCKET_REPO</repo_name>
      </range>
      <trash_md_path>/should_never_be_used</trash_md_path>
      <fsinfo_path>/camstors/.mdrepos/root/fsinfo</fsinfo_path>
      <quota_space>-1</quota_space>
      <quota_names>-1</quota_names>
    </namespace>

</config>
EOF

  MARFSCONFIGRC=/etc/marfsconfigrc marfs_fuse $MNT_MARFS 
  #[[ $? -ne 0 ]] && { echo "Failed to mount marfs"; exit 1; }
  
}

function setup_lemur_fvio_role()
{
  echo "*set up lemur-fvio*"
  FSNAME=$1
  MGS_IP=`cat /etc/hosts | grep $MGS_VM | tail -n 1 | awk '{print $1}'`
  MNT_MARFS=`cat /vagrant/config | grep MNT_MARFS | awk -F"=" '{print $2}'`
  

  cat <<EOF >/etc/lhsmd/agent
mount_root = "/mnt/lhsmd"
client_device = "$MGS_IP@tcp0:/$FSNAME"
enabled_plugins = ["lhsm-plugin-fvio"]
handler_count = 1
snapshots {
        enabled = false
}
EOF

  cat <<EOF >/etc/lhsmd/lhsm-plugin-fvio
#!DasLemurFVIOPlugin
archive_id: 1
marfs_mountpoint: $MNT_MARFS/$S3_BUCKET 
---
# logger config goes there
version: 1
disable_existing_loggers: False
formatters:
    simple:
        format: "%(asctime)s - %(name)s - %(levelname)s - %(message)s"

handle_params: &handle_params
    class: logging.handlers.RotatingFileHandler
    formatter: simple
    maxBytes: 10485760 # 10MB
    backupCount: 20
    encoding: utf8
handlers:
    console:
        class: logging.StreamHandler
        level: NOTSET
        formatter: simple
        stream: ext://sys.stdout

    debug_file_handler:
        <<: *handle_params
        level: DEBUG
        filename: /var/log/lhsm_plugin_fvio-debug.log

    error_file_handler:
        <<: *handle_params
        level: ERROR
        filename: /var/log/lhsm_plugin_fvio-error.log

loggers:
    copytool:
        level: DEBUG
        handlers: [console, error_file_handler, debug_file_handler]
        propagate: no
    hsm_agent:
        level: DEBUG
        handlers: [console, error_file_handler, debug_file_handler]
        propagate: no

root:
    level: NOTSET
    handlers: [console, debug_file_handler, error_file_handler]
EOF

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
  FUNC=$1
  "$FUNC"
fi


