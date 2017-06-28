#!/bin/bash -eux

S3_IP=`cat /vagrant/config | grep S3_IP | awk -F"=" '{print $2}'`
S3_ACCESS_ID=`cat /vagrant/config | sed -n 's/^ *S3_ACCESS_ID*= *//p'`
S3_SECRET_KEY=`cat /vagrant/config | grep S3_SECRET_KEY | awk -F"=" '{print $2}'`
S3_BUCKET=`cat /vagrant/config | grep S3_BUCKET | awk -F"=" '{print $2}'`
S3_BUCKET_REPO="$S3_BUCKET""repo"
MNT_MARFS=`cat /vagrant/config | grep MNT_MARFS | awk -F"=" '{print $2}'`
CUSTFS=`cat /vagrant/config | grep CUSTFS | awk -F"=" '{print $2}'`
MNT_LHSM=`cat /vagrant/config | grep MNT_LHSM | awk -F"=" '{print $2}'`
MNT_PNT_CUST=`cat /vagrant/config | grep MNT_PNT_CUST | awk -F"=" '{print $2}'`

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
            /usr/sbin/lctl set_param -P mdt.*-MDT0000.hsm_control=enabled
            ;;
    'ost')  /usr/sbin/mkfs.lustre --"${NODE_OPT[0]}" --mgsnode=$MGS_IP@tcp0 --backfstype=zfs --index=1 --fsname="${NODE_OPT[1]}" --reformat --verbose "${NODE_OPT[2]}"/""${NODE_OPT[0]}""1""
            echo "$MGS_VM - "${NODE_OPT[1]}"-OST0001 zfs:"${NODE_OPT[2]}"/""${NODE_OPT[0]}""1""" >> /etc/ldev.conf
            mkdir -p /mnt/lustre/local/"${NODE_OPT[1]}"-""${NODE_OPT[0]}""1""
            /usr/sbin/mount.lustre "${NODE_OPT[2]}"/""${NODE_OPT[0]}""1"" /mnt/lustre/local/"${NODE_OPT[1]}"-""${NODE_OPT[0]}""1"" 
            ;;

    'client')  mkdir -p $MNT_POINT
               LIST_NIDS=`/usr/sbin/lctl list_nids`
               /usr/bin/mount -t lustre -o user_xattr $LIST_NIDS:/"${NODE_OPT[1]}" "$MNT_POINT"
               echo "$MGS_IP@tcp0:/"${NODE_OPT[1]}" "$MNT_POINT" lustre defaults,_netdev,user_xattr 0 00" >> /etc/fstab
               /usr/bin/lfs df -h
               ;;
  esac
  /usr/sbin/lctl dl
}

function setup_marfs_role()
{
  echo "*set up marfs*"

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
  LIST_NIDS=`/usr/sbin/lctl list_nids`
    

  cat <<EOF >/etc/lhsmd/agent
mount_root = "$MNT_LHSM"
client_device = "$LIST_NIDS:/$CUSTFS"
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

  mkdir -p /var/run/lhsmd
  /usr/bin/systemctl enable lhsmd.service
  /usr/bin/systemctl start lhsmd.service
  
}

function setup_robinhood_role()
{
  echo "* Set up mariadb and robinhood role *"
  /usr/bin/systemctl enable mariadb
  /usr/bin/systemctl start mariadb
  openssl rand -base64 14 > /etc/robinhood.d/.dbpassword
  RH_PWD=`cat /etc/robinhood.d/.dbpassword | awk '{print $1}'`
  ROOT_PWD=`cat /etc/robinhood.d/.dbpassword | awk '{print $1}'`
  DB_NAME=rbh_$CUSTFS

  echo "Set password $ROOT_PWD"
  cat <<QQQ  | mysql_secure_installation

n
y
y
y
y
QQQ

  if systemctl is-active mariadb.service >/dev/null ; then
    cat <<SQL | mysql -u root mysql
update user set password=PASSWORD("$ROOT_PWD") where User='root';
flush privileges;
SQL
  else
    echo "MariaDB server is not active" >&2
    exit 1
  fi

  rbh-config create_db "$DB_NAME" '%' "$RH_PWD" "$ROOT_PWD"

  cat <<EOF >/etc/robinhood.d/$CUSTFS.conf
# -*- mode: c; c-basic-offset: 4; indent-tabs-mode: nil; -*-
# vim:expandtab:shiftwidth=4:tabstop=4:

General {
	fs_path = "$MNT_PNT_CUST";
	fs_type = lustre;
}

#### policy definitions ####

# include template policy definitions for Lustre/HSM
%include "includes/lhsm.inc"
# include template policy definitions for legacy TMPFS flavor
%include "includes/tmpfs.inc"
# include template policy definitions for removing directories
#%include "includes/rmdir.inc"
# include template for alerts
%include "includes/alerts.inc"
# include template for checksuming
%include "includes/check.inc"

#### fileclass definitions ####

FileClass even_files {
    definition { type == file and name == "*[02468]" }
    # only for policy matching, not to display in reports
    report = no;
}

FileClass odd_files {
    definition { type == file and name == "*[13579]" }
    lhsm_archive_action_params { archive_id = 2; }
    report = no;
}

# fileclasses to display in reports (can still be used in policies)
FileClass empty_files {
    definition { type == file and size == 0 }
    # report = yes (default)
}
FileClass small_files {
    definition { type == file and size > 0 and size <= 16MB }
    # report = yes (default)
}
FileClass std_files {
    definition { type == file and size > 16MB and size <= 1GB }
}
FileClass big_files {
    definition { type == file and size > 1GB }
}

FileClass largedir {
    definition { type == directory and dircount > 10000 }
}

FileClass f1 {
    definition { type == file and name == "file.1" }
}

FileClass f2 {
    definition { type == file and name == "file.2" }
}

#### Common Lustre/HSM parameters ####

lhsm_config {
    # used for 'undelete': command to change the fid of an entry in archive
    rebind_cmd = "/usr/sbin/lhsmtool_posix --hsm_root=/mnt/hsm_backup --archive {archive_id} --rebind {oldfid} {newfid} {fsroot}";
    uuid {
        # where the CT stored the UUID
        xattr = "trusted.lhsm_uuid";
    }
}

#### Lustre/HSM archive configuration ####

lhsm_archive_parameters {
    nb_threads = 8;
## archive 1000 files max at once
#    max_action_count = 1000;
#    max_action_volume = 1TB;

    # suspend policy run if action error rate > 50% (after 100 errors)
    suspend_error_pct = 50%;
    suspend_error_min = 100;

    # overrides policy default action
    # action = cmd("lfs hsm_archive --archive {archive_id} /mnt/lustre/.lustre/fid/{fid}");

    # default action parameters
    action_params {
        archive_id = 1;
    }
}

lhsm_archive_rules {
    ignore_fileclass = empty_files;

    rule archive_small {
        target_fileclass = small_files;
        condition { last_mod >= 10sec }

        # overrides policy action
        # action = cmd("lfs hsm_archive {fullpath}");
        action_params { archive_id = 1; }
    }

    rule archive_std {
        target_fileclass = std_files;
        target_fileclass = big_files;
        action_params { archive_id = 2; }
        condition { last_mod >= 30min }
    }

    # fallback rule
    rule default {
        action_params { archive_id = 3; }
        condition { last_mod >= 30min }
    }
}

# run every 5 min
lhsm_archive_trigger {
    trigger_on = periodic;
    check_interval = 5min;
}

#### Lustre/HSM release configuration ####

lhsm_release_rules {
    ignore_fileclass = empty_files;

    # keep small files on disk as long as possible
    rule release_small {
        target_fileclass = small_files;
        condition { last_access > 1y }
    }

    rule release_std {
        target_fileclass = std_files;
        target_fileclass = big_files;
        condition { last_access > 1d }
    }

    # fallback rule
    rule default {
        condition { last_access > 6h }
    }
}

# run 'lhsm_release' on full OSTs
lhsm_release_trigger {
    trigger_on = ost_usage;
    high_threshold_pct = 85%;
    low_threshold_pct  = 80%;
    check_interval     = 5min;
}

lhsm_release_parameters {
    nb_threads = 8;
## purge 1000 files max at once
#    max_action_count = 1000;
#    max_action_volume = 1TB;

    # suspend policy run if action error rate > 50% (after 100 errors)
    suspend_error_pct = 50%;
    suspend_error_min= 100;
}


#### Deleting old unused files #######

cleanup_rules {
    rule default {
        condition { last_access > 30d }
    }
}

# clean when inode count > 100M
cleanup_trigger {
    trigger_on = global_usage;
    high_threshold_cnt = 100M;
    low_threshold_cnt  = 100M;
    check_interval     = 5min;
}

### Alerts specification
alert_rules {

    # don't check entries more frequently than daily
    ignore { last_check < 1d }
    # don't check entries while they are modified
    ignore { last_mod < 1h }

    rule raise_alert {
        ## List all fileclasses that would raise alerts HERE:
        target_fileclass = f1;
        target_fileclass = f2;
        target_fileclass = largedir;

        # customize alert title:
        action_params { title = "entry matches '{fileclass}' ({rule})"; }

        # apply to all matching fileclasses in the policy scope
        condition = true;
    }

    # clear alert status
    rule default {
        action = none;
        action_params { alert = clear; }
        # apply to all entries that don't match 'raise_alert'
        condition = true;
    }
}

# trigger alert check hourly
alert_trigger {
    trigger_on = periodic;
    check_interval = 1h;
}


########### checksum rules ############

fileclass never_checked {
    # never checked or no successful check
    definition { checksum.last_success == 0 }
    # don't display this fileclass in --classinfo reports.
    report = no;
}

checksum_rules {
    ignore { last_check < 7d }
    ignore { last_mod < 1d }

    rule initial_check {
        target_fileclass = never_checked;
        condition { last_mod > 1d }
    }

    rule default {
       condition { last_mod > 1d and last_check > 7d }
    }
}

# start checksum hourly
checksum_trigger {
    trigger_on = periodic;
    check_interval = 1h;
}

############# rmdir rules ############

rmdir_empty_parameters {
    lru_sort_attr = none;
}

rmdir_empty_trigger {
    trigger_on = periodic;
    check_interval = 1h;
}

rmdir_empty_rules {
    ignore { depth < 4 }

    rule default {
        condition { last_mod > 15d }
    }
}

########### end of policy rules ############


# ChangeLog Reader configuration
# Parameters for processing MDT changelogs :
ChangeLog {
    # 1 MDT block for each MDT :
    MDT {
        # name of the first MDT
        mdt_name  = "MDT0000" ;

        # id of the persistent changelog reader
        # as returned by "lctl changelog_register" command
        reader_id = "cl2" ;
    }
    polling_interval = 1s;
}

Log {
    # Log verbosity level
    # Possible values are: CRIT, MAJOR, EVENT, VERB, DEBUG, FULL
    debug_level = EVENT;

    # Log file
    log_file = "/var/log/robinhood.log";

    # File for reporting purge events
    report_file = "/var/log/robinhood_actions.log";

    # set alert_file, alert_mail or both depending on the alert method you wish
    alert_file = "/var/log/robinhood_alerts.log";
    alert_show_attrs = yes;
}

ListManager {
        MySQL {
                server = "localhost";
                db = $DB_NAME;
                user = "robinhood";
                # password or password_file are mandatory
                # password = "robinhood";
                password_file = /etc/robinhood.d/.dbpassword;
                engine = innodb;
        }
}
EOF

  /usr/sbin/robinhood --scan --once -L stderr
}

function setup_pftool_role()
{
  echo "* Set up pftool role *"
  if grep -Fxq "localhost slots=4" /etc/openmpi-x86_64/openmpi-default-hostfile
  then
    echo "Don't update /etc/openmpi-x86_64/openmpi-default-hostfile!!"
  else
    echo "localhost slots=4" >> /etc/openmpi-x86_64/openmpi-default-hostfile
  fi

  if grep "btl" /etc/openmpi-x86_64/openmpi-mca-params.conf
  then
    echo "Don't update /etc/openmpi-x86_64/openmpi-mca-params.conf !!"
  else
    echo "btl = tcp,sm,self" >> /etc/openmpi-x86_64/openmpi-mca-params.conf
  fi

  cat <<EOF >/home/vagrant/.bashrc
# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi
module load mpi/openmpi-x86_64

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
EOF

  cat <<EOF >/root/.bashrc
# .bashrc

# User specific aliases and functions

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Source global definitions
if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi

module load mpi/openmpi-x86_64
EOF
  chmod 777 /home/vagrant/.bashrc
  chmod 777 /root/.bashrc   
}

# main

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


