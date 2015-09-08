#!/bin/bash
#
#Configuration Script for the Sandbox Overcloud Controller Nodes
#@author: Philippe Jeurissen (Nuage Networks)
#@version 1.0

############
#PREREQS:  #
############
# 1 Fill out the parameters below
#
# 2 Copy these files to /opt/nuage before starting:
#         mkdir /opt/nuage
#         scp 10.225.194.135:/root/nuage/rpm/heat-contrib-nuage-1671-nuage_kilo.noarch.rpm /opt/nuage
#         scp 10.225.194.135:/root/nuage/rpm/nuage-neutron-1670-nuage_kilo.noarch.rpm /opt/nuage
#         scp 10.225.194.135:/root/nuage/rpm/nuagenetlib-3.2.2_74-nuage_kilo.noarch.rpm /opt/nuage
#         scp 10.225.194.135:/root/nuage/rpm/nuage-openstack-neutronclient-1670-nuage_kilo.noarch.rpm /opt/nuage

#IP of VSD node 1
vsd1="10.255.193.13"
#IP of VSD node 2
vsd2="10.255.193.14"
#IP of VSD node 3
vsd3="10.255.193.15"
#VSD SuperUser Username
vsd_user="csproot"
#VSD SuperUser Password
vsd_pass="csproot"
#HA Proxy Internal VIP
ha_proxy_vip_inside="10.225.193.20"
#Port to be used on the Internal VIP to access the VSD GUI
ha_proxy_vsd_inside_port="443"
#Port to be used on the Internal VIP to access the VSD Stats
ha_proxy_vsd_stats_inside_port="4242"
#HA Proxy External VIP
ha_proxy_vip_outside="10.225.195.11"
#Port to be used on the External VIP to access the VSD GUI
ha_proxy_vsd_outside_port="443"
#Port to be used on the External VIP to access the VSD Stats
ha_proxy_vsd_stats_outside_port="4242"

path_packages="/opt/nuage"
nuage_heat_rpm="heat-contrib-nuage-1671-nuage_kilo.noarch.rpm"
nuage_plugin_rpm="nuage-neutron-1670-nuage_kilo.noarch.rpm"
nuage_netlib_rpm="nuagenetlib-3.2.2_74-nuage_kilo.noarch.rpm"
nuage_neutron_client_rpm="nuage-openstack-neutronclient-1670-nuage_kilo.noarch.rpm"


################
#Pre-Run Checks#
################
# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi
if [ ! -f $path_packages/$nuage_heat_rpm ]; then
    echo "Nuage Heat Extension Package not found!"
	exit 1
fi
if [ ! -f $path_packages/$nuage_plugin_rpm ]; then
    echo "Nuage Neutron Plugin Package not found!"
	exit 1
fi
if [ ! -f $path_packages/$nuage_netlib_rpm ]; then
    echo "Nuage Netlib Package not found!"
	exit 1
fi
if [ ! -f $path_packages/$nuage_neutron_client_rpm ]; then
    echo "Nuage Neutronclient Package not found!"
	exit 1
fi

##########################
#Remove unwanted Packages#
##########################
echo "Removing unwanted packages"

systemctl stop neutron-server.service
systemctl stop neutron-dhcp-agent.service
systemctl stop neutron-l3-agent.service
systemctl stop neutron-metadata-agent.service
systemctl stop neutron-openvswitch-agent.service
systemctl stop neutron-netns-cleanup.service
systemctl stop neutron-ovs-cleanup.service
systemctl disable neutron-dhcp-agent.service
systemctl disable neutron-l3-agent.service
systemctl disable neutron-metadata-agent.service
systemctl disable neutron-openvswitch-agent.service
systemctl disable neutron-netns-cleanup.service
systemctl disable neutron-ovs-cleanup.service

yum remove openstack-neutron-lbaas openstack-neutron-ml2 openstack-neutron-openvswitch -y

#########################
#OpenStack Configuration#
#########################
echo "Configuring OpenStack"

sed -i "s/^ovs_bridge=.*/ovs_bridge=alubr0/"  /etc/nova/nova.conf

#########################
#Installing Nuage Plugin#
#########################
echo "Installing Nuage Plugin"

yum install /opt/nuage/* -y


#####################
#Nuage Configuration#
#####################
echo "Configuring Nuage"

#edit neutron.conf
sed -i "s/^service_plugins =.*/#service_plugins =neutron.services.l3_router.l3_router_plugin.L3RouterPlugin/"  /etc/neutron/neutron.conf
sed -i "s/^# api_extensions_path =.*/api_extensions_path =\/usr\/lib\/python2.7\/site-packages\/neutron\/plugins\/nuage/"  /etc/neutron/neutron.conf
sed -i "s/^# core_plugin =.*/core_plugin =neutron.plugins.nuage.plugin.NuagePlugin/"  /etc/neutron/neutron.conf

#create nuage_plugin.ini
if [ -f /ext/neutron/plugins/nuage/nuage_plugin.ini ]; then
	rm -f /ext/neutron/plugins/nuage/nuage_plugin.ini
fi
mkdir -p /etc/neutron/plugins/nuage

echo "[RESTPROXY]" >> /etc/neutron/plugins/nuage/nuage_plugin.ini
echo "default_net_partition_name = OpenStack" >> /etc/neutron/plugins/nuage/nuage_plugin.ini
echo "server = $ha_proxy_vip_inside:$ha_proxy_inside_port" >> /etc/neutron/plugins/nuage/nuage_plugin.ini
echo "serverauth = $vsd_user:$vsd_pass" >> /etc/neutron/plugins/nuage/nuage_plugin.ini
echo "organization = csp" >> /etc/neutron/plugins/nuage/nuage_plugin.ini
echo "auth_resource = /me" >> /etc/neutron/plugins/nuage/nuage_plugin.ini
echo "serverssl = True" >> /etc/neutron/plugins/nuage/nuage_plugin.ini
echo "base_uri = /nuage/api/v3_2" >> /etc/neutron/plugins/nuage/nuage_plugin.ini

rm -f /etc/neutron/plugin.ini
ln -s /etc/neutron/plugins/nuage/nuage_plugin.ini /etc/neutron/plugin.ini


#systemctl start neutron-server.service


#heat
systemctl stop openstack-heat-engine.service
sed -i "s/^#plugin_dirs =.*/plugin_dirs = \/usr\/lib64\/heat,\/usr\/lib\/heat,\/usr\/local\/lib\/heat,\/usr\/local\/lib64\/heat,\/usr\/lib\/python2.7\/site-packages\/nuage-heat\/resources/" /etc/heat/heat.conf
systemctl start openstack-heat-engine.service

#haproxy
if grep "/etc/haproxy/haproxy.cfg" "nuage_vsd" > /dev/null
then
	echo "Already found vsd config in /etc/haproxy/haproxy.cfg. PLease check it manually."
else
echo "
listen nuage_vsd
  bind $ha_proxy_vip_inside:$ha_proxy_vsd_inside_port
  bind $ha_proxy_vip_outside:$ha_proxy_vsd_outside_port
  server vsd0001 $vsd1:8443 check fall 5 inter 2000 rise 2
  server vsd0002 $vsd2:8443 check fall 5 inter 2000 rise 2
  server vsd0003 $vsd3:8443 check fall 5 inter 2000 rise 2
  
listen nuage_vsd_stats
  bind $ha_proxy_vip_inside:$ha_proxy_vsd_stats_inside_port
  bind $ha_proxy_vip_outside:$ha_proxy_vsd_stats_outside_port
  server vsd0001 $vsd1:4242 check fall 5 inter 2000 rise 2
  server vsd0001 $vsd2:4242 check fall 5 inter 2000 rise 2
  server vsd0001 $vsd3:4242 check fall 5 inter 2000 rise 2" >> /etc/haproxy/haproxy.cfg
fi  
service haproxy restart

echo "Nuage integration completed."
echo "Make sure to create the neutron DB with the "OSPd_integrate_controller_db.sh" script, then restart Neutron-Server"





