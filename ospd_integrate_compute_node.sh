#!/bin/bash
#
#Configuration Script for the Sandbox Overcloud Compute Nodes
#@author: Philippe Jeurissen (Nuage Networks)
#@version 1.0

############
#PREREQS:  #
############
# 1 Make sure the node is registered with RH and can use yum install
#
# 2 Fill out the parameters below
#
# 3 Copy these files to /opt/nuage before starting:
#         mkdir /opt/nuage
#         scp 10.225.194.135:/root/nuage/rpm/nuage-openvswitch-3.2.2-74.el7.x86_64.rpm /opt/nuage
#         scp 10.225.194.135:/root/nuage/rpm/nuage-metadata-agent-3.2.2-74.el7.x86_64.rpm /opt/nuage
#         scp 10.225.194.135:/root/nuage/rpm/protobuf-2.5.0-7.el7.x86_64.rpm /opt/nuage
#         scp 10.225.194.135:/root/nuage/rpm/protobuf-c-1.0.1-1.el7.x86_64.rpm /opt/nuage
#         scp 10.225.194.135:/root/nuage/rpm/protobuf-compiler-2.5.0-7.el7.x86_64.rpm /opt/nuage


######################################
#PARAMETERS. PLease fill these out!!!#
######################################

#VSC1 DATA IP
vsc1="10.225.193.138"
#VSC2 DATA IP
vsc2="10.225.193.139"
#Overcloud Admin Username
os_user="admin"
#Overcloud Admin Password
os_pass="8cf55faf6b77aecc9d92b9e6f8041fcf644b3df6"
#Overcloud Metadata Secret(check the overcloud /etc/nova/nova.conf for this)
metadata_secret="unset"

path_packages="/opt/nuage"
nuageVRS_rpm="nuage-openvswitch-3.2.2-74.el7.x86_64.rpm"
nuage_metadata_agent_rpm="nuage-metadata-agent-3.2.2-74.el7.x86_64.rpm"
protobuf_rpm="protobuf-2.5.0-7.el7.x86_64.rpm"
protobufc_rpm="protobuf-c-1.0.1-1.el7.x86_64.rpm"
protobufcompiler_rpm="protobuf-compiler-2.5.0-7.el7.x86_64.rpm"




################
#Pre-Run Checks#
################
# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi
if [ ! -f $path_packages/$nuageVRS_rpm ]; then
    echo "Nuage VRS Package not found!"
	exit 1
fi
if [ ! -f $path_packages/$nuage_metadata_agent_rpm ]; then
    echo "Nuage Metadata Package not found!"
	exit 1
fi
if [ ! -f $path_packages/$protobuf_rpm ]; then
    echo "Protobuf Package not found!"
	exit 1
fi
if [ ! -f $path_packages/$protobufc_rpm ]; then
    echo "Protobuf-c Package not found!"
	exit 1
fi
if [ ! -f $path_packages/$protobufcompiler_rpm ]; then
    echo "Protobuf-compiler Package not found!"
	exit 1
fi

##########################
#Remove unwanted Packages#
##########################
echo "Removing unwanted packages"

yum remove openvswitch openstack-neutron openstack-neutron-common openstack-neutron-lbaas openstack-neutron-ml2 openstack-neutron-openvswitch python-openvswitch -y


#######################
#Network Configuration#
#######################
echo "Configuring Network"

bond0_int=$(awk -F "=" '/BOND_IFACES/ {print $2}' /etc/sysconfig/network-scripts/ifcfg-bond0 | tr -d '"')
bond1_int=$(awk -F "=" '/BOND_IFACES/ {print $2}' /etc/sysconfig/network-scripts/ifcfg-bond1 | tr -d '"')
bond0_vlan232_ip=$(awk -F "=" '/IPADDR/ {print $2}' /etc/sysconfig/network-scripts/ifcfg-vlan232)
bond0_vlan233_ip=$(awk -F "=" '/IPADDR/ {print $2}' /etc/sysconfig/network-scripts/ifcfg-vlan233)
bond1_vlan231_ip=$(awk -F "=" '/IPADDR/ {print $2}' /etc/sysconfig/network-scripts/ifcfg-vlan231)

rm -f /etc/sysconfig/network-scripts/*-br-bond
rm -f /etc/sysconfig/network-scripts/*-br-bond2
rm -f /etc/sysconfig/network-scripts/*vlan*

#bond0
rm -f /etc/sysconfig/network-scripts/ifcfg-bond0
echo "DEVICE=bond0" >> /etc/sysconfig/network-scripts/ifcfg-bond0
echo "ONBOOT=yes" >> /etc/sysconfig/network-scripts/ifcfg-bond0
echo "HOTPLUG=no" >> /etc/sysconfig/network-scripts/ifcfg-bond0
echo "NM_CONTROLLED=no" >> /etc/sysconfig/network-scripts/ifcfg-bond0
echo "TYPE=Ethernet" >> /etc/sysconfig/network-scripts/ifcfg-bond0
echo "BONDING_OPTS="mode=1 miimon=100"" >> /etc/sysconfig/network-scripts/ifcfg-bond0
echo "BONDING_MASTER=yes" >> /etc/sysconfig/network-scripts/ifcfg-bond0

#bond0 interfaces

for i in $bond0_int
do
	rm -f /etc/sysconfig/network-scripts/ifcfg-$i
	echo "DEVICE=$i" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "ONBOOT=yes" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "BOOTPROTO=none" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "HOTPLUG=no" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "NM_CONTROLLED=no" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "SLAVE=yes" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "MASTER=bond0" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "TYPE=Ethernet" >> /etc/sysconfig/network-scripts/ifcfg-$i
done

#bond1
rm -f /etc/sysconfig/network-scripts/ifcfg-bond1
echo "DEVICE=bond1" >> /etc/sysconfig/network-scripts/ifcfg-bond1
echo "ONBOOT=yes" >> /etc/sysconfig/network-scripts/ifcfg-bond1
echo "HOTPLUG=no" >> /etc/sysconfig/network-scripts/ifcfg-bond1
echo "NM_CONTROLLED=no" >> /etc/sysconfig/network-scripts/ifcfg-bond1
echo "TYPE=Ethernet" >> /etc/sysconfig/network-scripts/ifcfg-bond1
echo "BONDING_OPTS="mode=1 miimon=100"" >> /etc/sysconfig/network-scripts/ifcfg-bond1
echo "BONDING_MASTER=yes" >> /etc/sysconfig/network-scripts/ifcfg-bond1

#bond1 interfaces

for i in $bond1_int
do
	rm -f /etc/sysconfig/network-scripts/ifcfg-$i
	echo "DEVICE=$i" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "ONBOOT=yes" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "BOOTPROTO=none" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "HOTPLUG=no" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "NM_CONTROLLED=no" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "SLAVE=yes" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "MASTER=bond1" >> /etc/sysconfig/network-scripts/ifcfg-$i
	echo "TYPE=Ethernet" >> /etc/sysconfig/network-scripts/ifcfg-$i
done

#bond0_vlan232
if [ ! -f /etc/sysconfig/network-scripts/ifcfg-bond0.232 ]; then
	echo "DEVICE=bond0.232" >> /etc/sysconfig/network-scripts/ifcfg-bond0.232
	echo "ONBOOT=yes" >> /etc/sysconfig/network-scripts/ifcfg-bond0.232
	echo "BOOTPROTO=none" >> /etc/sysconfig/network-scripts/ifcfg-bond0.232
	echo "HOTPLUG=no" >> /etc/sysconfig/network-scripts/ifcfg-bond0.232
	echo "NM_CONTROLLED=no" >> /etc/sysconfig/network-scripts/ifcfg-bond0.232
	echo "IPADDR=$bond0_vlan232_ip" >> /etc/sysconfig/network-scripts/ifcfg-bond0.232
	echo "NETMASK=255.255.255.128" >> /etc/sysconfig/network-scripts/ifcfg-bond0.232
	echo "VLAN=yes" >> /etc/sysconfig/network-scripts/ifcfg-bond0.232
fi

#bond0_vlan233
if [ ! -f /etc/sysconfig/network-scripts/ifcfg-bond0.233 ]; then
	echo "DEVICE=bond0.233" >> /etc/sysconfig/network-scripts/ifcfg-bond0.233
	echo "ONBOOT=yes" >> /etc/sysconfig/network-scripts/ifcfg-bond0.233
	echo "BOOTPROTO=none" >> /etc/sysconfig/network-scripts/ifcfg-bond0.233
	echo "HOTPLUG=no" >> /etc/sysconfig/network-scripts/ifcfg-bond0.233
	echo "NM_CONTROLLED=no" >> /etc/sysconfig/network-scripts/ifcfg-bond0.233
	echo "IPADDR=$bond0_vlan233_ip" >> /etc/sysconfig/network-scripts/ifcfg-bond0.233
	echo "NETMASK=255.255.255.128" >> /etc/sysconfig/network-scripts/ifcfg-bond0.233
	echo "VLAN=yes" >> /etc/sysconfig/network-scripts/ifcfg-bond0.233
fi

#bond1_vlan231
if [ ! -f /etc/sysconfig/network-scripts/ifcfg-bond1.231 ]; then
	echo "DEVICE=bond1.231" >> /etc/sysconfig/network-scripts/ifcfg-bond1.231
	echo "ONBOOT=yes" >> /etc/sysconfig/network-scripts/ifcfg-bond1.231
	echo "BOOTPROTO=none" >> /etc/sysconfig/network-scripts/ifcfg-bond1.231
	echo "HOTPLUG=no" >> /etc/sysconfig/network-scripts/ifcfg-bond1.231
	echo "NM_CONTROLLED=no" >> /etc/sysconfig/network-scripts/ifcfg-bond1.231
	echo "IPADDR=$bond1_vlan231_ip" >> /etc/sysconfig/network-scripts/ifcfg-bond1.231
	echo "NETMASK=255.255.255.128" >> /etc/sysconfig/network-scripts/ifcfg-bond1.231
	echo "VLAN=yes" >> /etc/sysconfig/network-scripts/ifcfg-bond1.231
fi

#########################
#OpenStack Configuration#
#########################
echo "Configuring OpenStack"
controller=$(grep url /etc/nova/nova.conf | grep -Pom 1 '[0-9.]{7,15}')
sed -i "s/^ovs_bridge=.*/ovs_bridge=alubr0/"  /etc/nova/nova.conf

######################
#Installing Nuage VRS#
######################
echo "Installing Nuage VRS Package"

subscription-manager repos  --enable=rhel-7-server-optional-rpms

yum install /opt/nuage/* -y



#####################
#Nuage Configuration#
#####################
echo "Configuring Nuage"
setenforce 0
sed -i "s/^SELINUX=.*/SELINUX=permissive/"  /etc/selinux/config

#open firewall
#iptables


sed -i "s/^# ACTIVE_CONTROLLER=.*/ACTIVE_CONTROLLER=$vsc1/"  /etc/default/openvswitch
sed -i "s/^# STANDBY_CONTROLLER=.*/STANDBY_CONTROLLER=$vsc2/"  /etc/default/openvswitch


sed -i "s/^# METADATA_PORT=.*/METADATA_PORT=9697/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_METADATA_IP=.*/NOVA_METADATA_IP=$controller/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_METADATA_PORT=.*/NOVA_METADATA_PORT=8775/"  /etc/default/nuage-metadata-agent
sed -i "s/^# METADATA_PROXY_SHARED_SECRET=.*/METADATA_PROXY_SHARED_SECRET=$metadata_secret/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_CLIENT_VERSION=.*/NOVA_CLIENT_VERSION=2/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_OS_USERNAME=.*/NOVA_OS_USERNAME=$os_user/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_OS_PASSWORD=.*/NOVA_OS_PASSWORD=$os_pass/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_OS_TENANT_NAME=.*/NOVA_OS_TENANT_NAME=admin/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_OS_AUTH_URL=.*/NOVA_OS_AUTH_URL=http:\/\/$controller:5000\/v2.0/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NUAGE_METADATA_AGENT_START_WITH_OVS=.*/NUAGE_METADATA_AGENT_START_WITH_OVS=yes/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_API_ENDPOINT_TYPE=.*/NOVA_API_ENDPOINT_TYPE=publicURL/"  /etc/default/nuage-metadata-agent
sed -i "s/^# NOVA_REGION_NAME=.*/NOVA_REGION_NAME=RegionOne/"  /etc/default/nuage-metadata-agent

service openvswitch restart
service nuage-metadata-agent restart
ovs-vsctl del-br br-bond1
ovs-vsctl del-br br-bond2
ovs-vsctl del-br br-int
ovs-vsctl del-br br-tun
ovs-vsctl del-br br-ex

echo "Nuage integration completed."
echo "Please reboot the node 2 times to restore network connectivity."
