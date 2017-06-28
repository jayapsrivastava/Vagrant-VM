#!/bin/bash
set -x

function test() {

declare -a myarray=("$@")
#myarray=("$@") 
echo ""${myarray[0]}""1""
echo "${myarray[1]}"
echo "${myarray[2]}"

}

function setup_lemur_fvio_role()
{
  echo "*set up lemur-fvio*"
  FSNAME=$1
  IP=`hostname -I`
  cat <<EOF >/etc/lhsmd/agent
mount_root = "/mnt/lhsmd"
client_device = "$IP@tcp0:/$FSNAME"
enabled_plugins = ["lhsm-plugin-fvio"]
handler_count = 1
snapshots {
        enabled = false
}
EOF

}

fs=$1
setup_lemur_fvio_role  $fs





