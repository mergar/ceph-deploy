#!/bin/sh
auto_iface=$( /sbin/route -n get 0.0.0.0 | awk '/interface/{print $2}' )
my_ip=$( ifconfig ${auto_iface} | awk '/inet [0-9]+/ { print $2}' | /usr/bin/head -n 1 |awk '{ printf $1 }' )
fqdn=$( hostname )
hostname=$( hostname -s )
echo "${my_ip} ${hostname} ${fqdn}" >> /etc/hosts
pkg update -f
pkg install -y ceph14
ln -sf /usr/local/etc/ceph /etc/ceph
fsid=$( uuidgen )
#egrep -v '(^[;|#])|^    (#|;)' /etc/ceph/ceph.conf.sample | grep . > /etc/ceph/ceph.conf

if [ -z "${fsid}" ]; then
	echo "no fsid"
	exit 1
fi

if [ -z "${hostname}" ]; then
	echo "no hostname"
	exit 1
fi

if [ -z "${my_ip}" ]; then
	echo "no ip"
	exit 1
fi


cat > /etc/ceph/ceph.conf <<EOF
[global]
    public network             = 10.0.0.0/24
    cluster network            = 10.0.0.0/24
    pid file                   = /var/run/ceph/$name.pid
    auth cluster required      = cephx
    auth service required      = cephx
    auth client required       = cephx
    cephx cluster require signatures = true
    cephx service require signatures = false
    fsid                       = ${fsid}
[mon]
    mon initial members        = ${hostname}
    mon host                   = ${hostname}
[mon.${hostname}]
    host = ${hostname}
    mon addr = ${my_ip}
#[mon.node2]
#    host = node2
#    mon addr = 10.0.0.4
#[mon.node3]
#    host = node3
#    mon addr = 10.0.0.4
[mds]
[osd]
     osd objectstore = filestore
[client]
    rbd cache                           = true
[client.radosgw.gateway]
EOF

set -o xtrace
ceph-authtool --create-keyring /etc/ceph/ceph.client.admin.keyring --gen-key -n client.admin --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow *' --cap mgr 'allow *'
ceph-authtool --create-keyring /tmp/ceph.mon.keyring --gen-key -n mon. --cap mon 'allow *'
ceph-authtool /tmp/ceph.mon.keyring --import-keyring /etc/ceph/ceph.client.admin.keyring

monmaptool --create --add ${hostname} ${my_ip} --fsid 076778a1-5c80-11ea-8717-00a098a5e085 /tmp/monmap
mkdir /var/lib/ceph/mon/ceph-${hostname}

chown -R ceph:ceph /var/lib/ceph/mon/ceph-${hostname} /var/run/ceph /var/log/ceph /tmp/ceph.mon.keyring
sudo -u ceph ceph-mon --mkfs -i ${hostname} --monmap /tmp/monmap --keyring /tmp/ceph.mon.keyring
sudo -u ceph touch /var/lib/ceph/mon/ceph-${hostname}/done

service ceph enable
service ceph start

#verify:
ceph osd lspools
ceph -s
