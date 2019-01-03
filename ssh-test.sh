#!/bin/bash


sshf(){

privatekey=~/.ssh/id_rsa
host=$1
shift 1
cmd=$@
ssh -i ${privatekey} ${host} "${cmd}"

}


operation(){

location=/etc/init/file
hostname
uname
ls -al /etc/init/file

}

ssh 10.136.155.77 <<EOF
$(typeset -f operation)
    operation

EOF


#cat <( declare -f operation )
#/tmp/operation.sh
#echo "operation" >> /tmp/operation.sh
#chmod 755 /tmp/operation.sh 
#/tmp/operation.sh sshf 10.136.155.77

# $( operation )
#EOF
#operation | sshf 10.136.155.77 
#(declare -f operation ; operation) | sshf 10.136.155.77
#sshf 10.136.155.77 (declare -f operation ; operation) 
#sshf a


sshf 10.136.155.77 operation
