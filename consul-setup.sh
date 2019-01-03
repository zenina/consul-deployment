#!/bin/bash 
###############################
## Nina Limmer               ##
## 2018	       		     ##
## Consul Deployment Script  ##
###############################


SDIR=${PWD}
logfile=/tmp/consul-deploy.$(date +%F).log
echo $SDIR


log(){
	htype=$1
	host=$2
	shift 2
	 while read line; 
	do
		echo "[${htype}] [${host}] ==> $line" | tee -a $logfile
	done

}

installConsul(){
	CONSUL_ZIP_URL=https://releases.hashicorp.com/consul/1.4.0/consul_1.4.0_linux_amd64.zip
	CONSUL_ZIP=${CONSUL_ZIP_URL##*/}
	echo $CONSUL_ZIP_URL
	echo $CONSUL_ZIP
	apt-get update
	apt-get install unzip 
	cd /root/
	wget ${CONSUL_ZIP_URL}
	unzip ${CONSUL_ZIP}
	mv -v consul /usr/local/bin/
	rm ${CONSUL_ZIP}

}

sshf(){
	privatekey=~/.ssh/id_rsa
	host=$1
	shift 1
	cmd=$@
	ssh -i ${privatekey} ${host} "${cmd}"
}

configureClient(){
	local tmpconfiglocation
	local remoteconfiglocation
	local remoteupstartconfig
	local configtemplate
	local upstarttemplate
	local upstartconfig
	tmpconfiglocation="/tmp/consul/$(date +%F)/client"
	remoteconfiglocation="/etc/consul.d/client/"
	remoteupstartconfig="/etc/init/consul-client.conf"
	configtemplate="${SDIR}/configs/client/config.json"	
	upstarttemplate="${SDIR}/configs/client/consul-client.conf"
	upstartconfig=${tmpconfiglocation}/consul-client.conf
	deploypath="/root/consul-deploy"
	joinips="\"$bootstrap\", \"$server\", \"$client\""
	datadir=$(grep data_dir configs/*/*.json | awk -F\" '{print $4}') 
	mkdir $datadir
	rm -rfv ${datadir}/serf/local.keyring
	encrypt="$(grep encrypt /etc/consul.d/bootstrap/config.json | awk -F\" '{print $4}')"
	mkdir -p $tmpconfiglocation
	echo "=> Generating config.json to location $tmpconfiglocation"
	sed -e "s/\${encrypt}/${encrypt}/" -e "s/\${joinips}/${joinips}/" ${configtemplate} > ${tmpconfiglocation}/config.json
	sed -e "s/\${encrypt}/${encrypt}/" -e "s/\${bindip}/${client}/" ${upstarttemplate} > ${upstartconfig}
	cat ${tmpconfiglocation}/config.json
	echo "=> Copying configuration files to remote server $client"	
	sshf $client "mkdir -v ${deploypath}"
	scp ${tmpconfiglocation}/config.json ${client}:${deploypath}
	scp ${upstartconfig} ${client}:${deploypath}
	 
	echo "=> Configuring server over SSH on IP: $client"

sshf $client <<EOF
	$(typeset -f )
	installConsul
	mkdir -vp /etc/consul.d/client
	mkdir /var/consul
	cp -v ${deploypath}/config.json /etc/consul.d/client/config.json
	cp -v ${deploypath}/consul-client.conf /etc/init/consul-client.conf
	init-checkconf $upstartconfig
	rm -rv ${deploypath}
	service consul-client stop 
	service consul-client start
	sleep 3
	consul members

EOF
}


configureServer(){
	local tmpconfiglocation
	local remoteconfiglocation
	local remoteupstartconfig
	local configtemplate
	local upstarttemplate
	local upstartconfig
	tmpconfiglocation="/tmp/consul/$(date +%s)/server"
	remoteconfiglocation="/etc/consul.d/server/"
	remoteupstartconfig="/etc/init/consul-server.conf"
	configtemplate="${SDIR}/configs/server/config.json"	
	upstarttemplate="${SDIR}/configs/server/consul-server.conf"
	upstartconfig=${tmpconfiglocation}/consul-server.conf
	deploypath="/root/consul-deploy"
	joinips="\"$bootstrap\", \"$server\", \"$client\""
	datadir=$(grep data_dir configs/*/*.json | awk -F\" '{print $4}') 
	mkdir $datadir
	rm -rfv ${datadir}/serf/local.keyring
	encrypt="$(grep encrypt /etc/consul.d/bootstrap/config.json | awk -F\" '{print $4}')"
	mkdir -vp $tmpconfiglocation
	echo "=> Generating config.json to location $tmpconfiglocation"
	sed -e "s/\${encrypt}/${encrypt}/" -e "s/\${joinips}/${joinips}/" ${configtemplate} > ${tmpconfiglocation}/config.json
	sed -e "s/\${encrypt}/${encrypt}/" -e "s/\${bindip}/${server}/" ${upstarttemplate} > ${tmpconfiglocation}/consul-server.conf
	cat ${tmpconfiglocation}/config.json
	echo "=> Configuring consul server with the following startup options"
	init-checkconf $upstartconfig
	echo "=> Copying configuration files to remote server $server"	
	sshf $server "mkdir -v ${deploypath}"
	scp ${tmpconfiglocation}/config.json ${server}:${deploypath}
	scp ${upstartconfig} ${server}:${deploypath}
	 
	echo "=> Configuring server over SSH on IP: $server"

sshf $server <<EOF
	$(typeset -f )
	installConsul
	mkdir -p /etc/consul.d/server
	mkdir /var/consul
	cp -v ${deploypath}/config.json /etc/consul.d/server/config.json
	cp -v ${deploypath}/consul-server.conf /etc/init/consul-server.conf
	rm -rv ${deploypath}
	service consul-server stop 
	service consul-server start
	sleep 3
	consul members

EOF



}



configureBootstrap(){
	local configlocation
	local configtemplate
	local upstarttemplate
	local upstartconfig	
	configlocation="/etc/consul.d/bootstrap/"
	configtemplate="${SDIR}/configs/bootstrap/config.json"	
	upstarttemplate="${SDIR}/configs/bootstrap/consul-bootstrap.conf"
	upstartconfig="/etc/init/consul-bootstrap.conf"
	joinips="\"$bootstrap\", \"$server\", \"$client\""
	if ifconfig | grep $bootstrap;
		then
		echo "=> Configuring bootstrap locally for IP: $bootstrap"
		installConsul
		mkdir -p /etc/consul.d/bootstrap
		datadir=$(grep data_dir configs/*/*.json | awk -F\" '{print $4}') 
		mkdir $datadir
		rm -rfv ${datadir}/serf/local.keyring
		encrypt="$(consul keygen)"
		echo "=> Generating config.json to location $configlocation"
		sed -e "s/\${encrypt}/${encrypt}/" -e "s/\${joinips}/${joinips}/" $configtemplate > ${configlocation}/config.json
		sed -e "s/\${encrypt}/${encrypt}/" -e "s/\${bindip}/${bootstrap}/" ${upstarttemplate} > $upstartconfig
		cat ${configlocation}/config.json
		echo "Copying startup config to init"
		echo "=> Starting consul with the following startup options"
		init-checkconf $upstartconfig
		service consul-bootstrap stop 
		service consul-bootstrap start
		sleep 3
		consul members
	fi
}


parseOpts(){

optspec=":hv-:"
while getopts "$optspec" optchar; do
    case "${optchar}" in
        -)
            case "${OPTARG}" in
                bootstrap)
                    bootstrap="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    echo "Parsing option: '--${OPTARG}', value: '${bootstrap}'" >&2;
		    configureBootstrap=true
                    ;;
                bootstrap=*)
                    bootstrap=${OPTARG#*=}
                    opt=${OPTARG%=$val}
                    echo "Parsing option: '--${opt}', value: '${bootstrap}'" >&2
		    configureBootstrap=true
                    ;;
                server)
                    server="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    echo "Parsing option: '--${OPTARG}', value: '${server}'" >&2;
		    configureServer=true
                    ;;
                server=*)
                    server=${OPTARG#*=}
                    opt=${OPTARG%=$val}
                    echo "Parsing option: '--${opt}', value: '${server}'" >&2
		    configureServer=true
                    ;;
                client)
                    client="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    echo "Parsing option: '--${OPTARG}', value: '${client}'" >&2;
		    configureClient=true
                    ;;
                client=*)
                    client=${OPTARG#*=}
                    opt=${OPTARG%=$val}
                    echo "Parsing option: '--${opt}', value: '${client}'" >&2
		    configureClient=true
                    ;;
                *)
                    if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                        echo "Unknown option --${OPTARG}" >&2
                    fi
		    echo "You must specify the following options:"
		    echo "usage: $0 [-v] [--bootstrap[=]<host ip>]" >&2
		    echo "usage: $0 [-v] [--server[=]<host ip>]" >&2
		    echo "usage: $0 [-v] [--client[=]<host ip>]" >&2
            	    exit 2
                    ;;
            esac;;
        h)
            echo "usage: $0 [-v] [--bootstrap[=]<host ip>]" >&2
            echo "usage: $0 [-v] [--server[=]<host ip>]" >&2
            echo "usage: $0 [-v] [--client[=]<host ip>]" >&2
            exit 2
            ;;
        v)
            echo "Parsing option: '-${optchar}'" >&2
            ;;
        *)
            if [ "$OPTERR" != 1 ] || [ "${optspec:0:1}" = ":" ]; then
                echo "Non-option argument: '-${OPTARG}'" >&2
            fi
		echo "You must specify the following options:"
		    echo "usage: $0 [-v] [--bootstrap[=]<host ip>]" >&2
		    echo "usage: $0 [-v] [--server[=]<host ip>]" >&2
		    echo "usage: $0 [-v] [--client[=]<host ip>]" >&2
            	    exit 2
            ;;
    esac
done

if [[ $configureBootstrap == true ]]; then 
    echo "run configure bootstrap"
    configureBootstrap | log "BOOTSTRAP $bootstrap"
fi

if [[ $configureServer == true ]]; then 
    echo "run configure server"
    configureServer | log "SERVER $server"
fi

if [[ $configureClient == true ]]; then 
    echo "run configure client"
    configureClient | log "CLIENT $client"
fi

}
parseOpts $@
