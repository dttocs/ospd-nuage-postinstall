#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

#
#Configuration Script for the Sandbox Overcloud Compute Nodes
#@author: Philippe Jeurissen (Nuage Networks) 
#@version 1.1

############
#PREREQS:  #
############
# 1 Make sure the redhat subscription credentials below are correct (with correct password)
#
# 2 Setup SSH passphraseless keys between the controllers, compute nodes and UC5
# 
# 3 Ensure firewalls are open 
#
# 4 Fill out the parameters below

mkdir -p /opt/nuage
scp 192.168.251.215:/data/nuage_binary/3.2r3/VRS/\*.rpm /opt/nuage


######################################
#PARAMETERS. PLease fill these out!!!#
######################################

#VSC1 DATA IP
vsc1="10.193.52.56"
#VSC2 DATA IP
vsc2="10.193.52.57"
#Overcloud Admin Username
os_user="admin"
#Overcloud Admin Password
os_pass="3f3fc462335841c3463ad41168b4ec3b1ad05a16"
#Overcloud Metadata Secret(check the overcloud /etc/nova/nova.conf for this)
metadata_secret="unset"
http_proxy_ip='192.168.251.215'
http_proxy_port='8080'
redhat_user='user'
redhat_pass='pass'

################
#Pre-Run Checks#
################
# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

subscription-manager config --server.proxy_hostname=${http_proxy_ip} --server.proxy_port=${http_proxy_port}  && \
subscription-manager register --username ${redhat_user} --password ${redhat_pass} --auto-attach && \
subscription-manager repos --enable=rhel-7-server-rpms  && \
subscription-manager repos --enable=rhel-7-server-rh-common-rpms && \ 
subscription-manager repos --enable=rhel-ha-for-rhel-7-server-rpms && \
subscription-manager repos --enable=rhel-7-server-openstack-7.0-rpms && \
subscription-manager repos --enable=rhel-7-server-openstack-7.0-director-rpms && \
subscription-manager repos --enable rhel-7-server-optional-rpms 

# Install EPEL repository and configure to use http proxy
export http_proxy="http://${http_proxy_ip}:${http_proxy_port}"
rpm -Uvh http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm
cp /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo.orig
sed -i "s/gpgcheck=1/gpgcheck=1\nproxy=http:\/\/${http_proxy_ip}:${http_proxy_port}/" /etc/yum.repos.d/epel.repo


###########################
#Remove unwanted Packages #
###########################
echo "Removing unwanted packages"
systemctl stop openvswitch
yum remove -y openvswitch openstack-neutron openstack-neutron-common openstack-neutron-lbaas openstack-neutron-ml2 openstack-neutron-openvswitch python-openvswitch

if [ -f /etc/openvswitch/conf.db ] ; then
    echo "Removing existing openvswitch database file: /etc/openvswitch/conf.db"
    rm -rf /etc/openvswitch/conf.db
fi

#######################
#Network Configuration#
#######################
echo "Configuring Network"

echo "re-configuring eth0 interface"
eth0_ipaddr=$(ifconfig eth0 | grep 'inet ' | awk '{ print $2}')
eth0_netmask=$(ifconfig eth0 | grep 'inet ' | awk '{ print $4}')
eth0_gateway=$(ip route | grep eth0 | awk '/default/ { print $3 }')
cat <<EOF >/etc/sysconfig/network-scripts/ifcfg-eth0
NAME=eth0
DEVICE=eth0
ONBOOT=yes
NM_CONTROLLED=no
TYPE=Ethernet
BOOTPROTO=static
IPADDR=${eth0_ipaddr}
NETMASK=${eth0_netmask}
GATEWAY=${eth0_gateway}
EOF

echo "re-configuring eth1 interface"
cat <<EOF >/etc/sysconfig/network-scripts/ifcfg-eth1
NAME=eth1
DEVICE=eth1
ONBOOT=yes
NM_CONTROLLED=no
TYPE=Ethernet
BOOTPROTO=none
MTU=9000
EOF

for cfgfile in /etc/sysconfig/network-scripts/ifcfg-vlan* ; do 
  ipaddr=$(crudini --get $cfgfile "" IPADDR)
  netmask=$(crudini --get $cfgfile "" NETMASK)
  vlan_id=$(crudini --get $cfgfile "" DEVICE | sed -e 's/vlan//')
  echo "configuring eth1.${vlan_id} sub-interface"
  cat <<EOF >/etc/sysconfig/network-scripts/ifcfg-eth1.${vlan_id}
NAME=eth1.${vlan_id}
DEVICE=eth1.${vlan_id}
NM_CONTROLLED=no
VLAN_ID=${vlan_id}
VLAN=yes
TYPE=Vlan
ONBOOT=yes
BOOTPROTO=static
IPADDR=${ipaddr}
NETMASK=${netmask}
MTU=9000
EOF
done

echo "removing existing stale interface configurations"
rm -f /etc/sysconfig/network-scripts/*-br-compute
rm -f /etc/sysconfig/network-scripts/*vlan*

for device in eth2 eth3 ; do
  if [ -f /etc/sysconfig/network-scripts/ifcfg-${device} ] ; then
    echo "setting ONBOOT=no for ${device}, as it may cause 'service network restart' to fail due to no DHCP server being available"
    crudini --set /etc/sysconfig/network-scripts/ifcfg-${device} "" ONBOOT no
  fi
done

cat <<EOF > /etc/resolv.conf
search internal.hkexpoc.lab
nameserver 10.193.54.213
EOF

#########################
#OpenStack Configuration#
#########################
echo "Configuring OpenStack"
# there was an error below, the ^ was missing before url, so #url would parse first.
#controller=$(grep ^url /etc/nova/nova.conf | grep -Pom 1 '[0-9.]{7,15}')
controller=$(crudini --get /etc/nova/nova.conf "neutron" url | grep -Pom 1 '[0-9.]{7,15}')
echo "controller is ${controller}"
#sed -i "s/^ovs_bridge=.*/ovs_bridge=alubr0/"  /etc/nova/nova.conf
crudini --set /etc/nova/nova.conf neutron ovs_bridge alubr0
crudini --set /etc/nova/nova.conf libvirt vif_driver nova.virt.libvirt.vif.LibvirtGenericVIFDriver
crudini --set /etc/nova/nova.conf neutron service_metadata_proxy True 
crudini --set /etc/nova/nova.conf DEFAULT use_forwarded_for True
crudini --set /etc/nova/nova.conf neutron ${metadata_secret}
crudini --set /etc/nova/nova.conf DEFAULT instance_name_template inst-%08x

# Re-point NOVNC to internal network
#controller=$(crudini --get /etc/nova/nova.conf "neutron" url | grep -Pom 1 '[0-9.]{7,15}')
#crudini --set /etc/nova/nova.conf DEFAULT novncproxy_base_url "http://${controller}:6080/vnc_auto.html"

######################
#Installing Nuage VRS#
######################
echo "Installing Nuage VRS Package"

# Install dependancies as specified in Step 4 of Page 61 of the Nuage Install Guide
yum install -y libvirt perl-JSON qemu-kvm vconfig python-twisted-core

yum install -y /opt/nuage/nuage-openvswitch-*.rpm 
yum install -y /opt/nuage/nuage-metadata-*.rpm

#####################
#Nuage Configuration#
#####################
echo "Configuring Nuage"
setenforce 0
sed -i "s/^SELINUX=.*/SELINUX=permissive/"  /etc/selinux/config
sed -i "s/^# ACTIVE_CONTROLLER=.*/ACTIVE_CONTROLLER=$vsc1/"  /etc/default/openvswitch
sed -i "s/^# STANDBY_CONTROLLER=.*/STANDBY_CONTROLLER=$vsc2/"  /etc/default/openvswitch

if [ ! -f /etc/default/nuage-metadata-agent ] ; then
    echo "error: /etc/default/nuage-metadata-agent does not exist"
	exit 1
fi
sed -i "s/^# METADATA_PORT=.*/METADATA_PORT=9697/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_METADATA_IP=.*/NOVA_METADATA_IP=$controller/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_METADATA_PORT=.*/NOVA_METADATA_PORT=8775/"  /etc/default/nuage-metadata-agent
sed -i "s/^# METADATA_PROXY_SHARED_SECRET=.*/METADATA_PROXY_SHARED_SECRET=$metadata_secret/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_CLIENT_VERSION=.*/NOVA_CLIENT_VERSION=2/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_OS_USERNAME=.*/NOVA_OS_USERNAME=$os_user/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_OS_PASSWORD=.*/NOVA_OS_PASSWORD=$os_pass/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_OS_TENANT_NAME=.*/NOVA_OS_TENANT_NAME=admin/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_OS_AUTH_URL=.*/NOVA_OS_AUTH_URL=http:\/\/$controller:5000\/v2.0/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NUAGE_METADATA_AGENT_START_WITH_OVS=.*/NUAGE_METADATA_AGENT_START_WITH_OVS=false/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_API_ENDPOINT_TYPE=.*/NOVA_API_ENDPOINT_TYPE=publicURL/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_REGION_NAME=.*/NOVA_REGION_NAME=RegionOne/"  /etc/default/nuage-metadata-agent

service openvswitch restart
service nuage-metadata-agent restart

# the bridges below should have been deleted when /etc/openvswitch/conf.db is deleted, but just to be sure we redo.
ovs-vsctl del-br br-compute
ovs-vsctl del-br br-int
ovs-vsctl del-br br-tun
ovs-vsctl del-br br-ex

chkconfig openvswitch

subscription-manager unregister

echo "Nuage integration completed."
echo "Please reboot the node 2 times to restore network connectivity."
