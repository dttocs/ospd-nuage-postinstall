#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

#
#Configuration Script for the Sandbox Overcloud Controller Nodes
#@author: Philippe Jeurissen (Nuage Networks)
#@version 1.1
# Note: Version 3.2r3 and Horizon Extension added to Version 1.1.


############
#PREREQS:  #
############
#
# 1 Make sure the csproot user is added to CMS Users group within the VSD GUI
#   Otherwise modify the scripts to use the OSadmin if desired.
#
# 2 Make sure the redhat subscription credentials below are correct (with correct password)
#  
# 3 Setup SSH passphraseless keys between the controllers and UC5
#
# 4 Ensure firewalls are open 
#
# 5 Verify the http forwarding proxy below is operational  
#
# 6 Fill out the parameters below

#IP of VSD node 1
vsd1="10.193.54.51"
#IP of VSD node 2
vsd2="10.193.54.52"
#IP of VSD node 3
vsd3="10.193.54.53"
#VSD SuperUser Username
vsd_user="csproot"
#VSD SuperUser Password
vsd_pass="csproot"
#HA Proxy Internal VIP
ha_proxy_vip_inside="10.193.54.101"
#Port to be used on the Internal VIP to access the VSD GUI
ha_proxy_vsd_inside_port="8443"
#Port to be used on the Internal VIP to access the VSD Stats
ha_proxy_vsd_stats_inside_port="4242"
#HA Proxy External VIP
ha_proxy_vip_outside="10.193.53.102"
#Port to be used on the External VIP to access the VSD GUI
ha_proxy_vsd_outside_port="8443"
#Port to be used on the External VIP to access the VSD Stats
ha_proxy_vsd_stats_outside_port="4242"
# http proxy used for yum
http_proxy_ip='192.168.251.215'
http_proxy_port='8080'
# redhat subscription credentials
redhat_user='user'
redhat_pass='pass'

path_packages="/opt/nuage"
nuage_heat_rpm="heat-contrib-nuage-1694-nuage_kilo.noarch.rpm"
nuage_plugin_rpm="nuage-neutron-1694-nuage_kilo.noarch.rpm"
nuage_netlib_rpm="nuagenetlib-3.2.3_101-nuage_kilo.noarch.rpm"
nuage_neutron_client_rpm="nuage-openstack-neutronclient-1694-nuage_kilo.noarch.rpm"
nuage_horizon_rpm="nuage_horizon-1694-nuage_kilo.noarch.rpm"


mkdir -p /opt/nuage
for rpm in $nuage_heat_rpm $nuage_plugin_rpm $nuage_netlib_rpm $nuage_neutron_client_rpm $nuage_horizon_rpm ; do
    scp 192.168.251.215:/data/nuage_binary/3.2r3/openstack/kilo/el7/${rpm} $path_packages
done

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
if [ ! -f $path_packages/$nuage_horizon_rpm ]; then
    echo "Nuage Horizon Extension Package not found!"
	exit 1
fi


##########################
#Remove unwanted Packages#
##########################
echo "Removing unwanted packages"

systemctl stop neutron-server.service && \
systemctl stop neutron-dhcp-agent.service && \
systemctl stop neutron-l3-agent.service && \
systemctl stop neutron-metadata-agent.service && \
systemctl stop neutron-openvswitch-agent.service && \
systemctl stop neutron-netns-cleanup.service && \
systemctl stop neutron-ovs-cleanup.service && \
systemctl disable neutron-dhcp-agent.service && \
systemctl disable neutron-l3-agent.service && \
systemctl disable neutron-metadata-agent.service && \
systemctl disable neutron-openvswitch-agent.service && \
systemctl disable neutron-netns-cleanup.service && \
systemctl disable neutron-ovs-cleanup.service

subscription-manager config --server.proxy_hostname=${http_proxy_ip} --server.proxy_port=${http_proxy_port}  && \
subscription-manager register --username ${redhat_user} --password ${redhat_pass} --auto-attach && \
subscription-manager repos --enable=rhel-7-server-rpms  && \
subscription-manager repos --enable=rhel-7-server-rh-common-rpms && \
subscription-manager repos --enable=rhel-ha-for-rhel-7-server-rpms && \
subscription-manager repos --enable=rhel-7-server-openstack-7.0-rpms && \
subscription-manager repos --enable=rhel-7-server-openstack-7.0-director-rpms


yum remove -y openstack-neutron-lbaas openstack-neutron-ml2 openstack-neutron-openvswitch 

#########################
#OpenStack Configuration#
#########################
echo "Configuring OpenStack"

#sed -i "s/^ovs_bridge=.*/ovs_bridge=alubr0/"  /etc/nova/nova.conf
crudini --set /etc/nova/nova.conf neutron ovs_bridge alubr0
crudini --set /etc/nova/nova.conf libvirt vif_driver nova.virt.libvirt.vif.LibvirtGenericVIFDriver

#########################
#Installing Nuage Plugin#
#########################
echo "Installing Nuage Plugin"
for rpm in $nuage_heat_rpm $nuage_plugin_rpm $nuage_netlib_rpm $nuage_neutron_client_rpm $nuage_horizon_rpm ; do
  echo "- installing ${rpm}"
  yum install -y /opt/nuage/${rpm} 
done

#####################
#Nuage Configuration#
#####################
echo "Configuring Nuage"

#edit neutron.conf
# Old Way:
#sed -i "s/^service_plugins =.*/#service_plugins =neutron.services.l3_router.l3_router_plugin.L3RouterPlugin/"  /etc/neutron/neutron.conf
#sed -i "s/^# api_extensions_path =.*/api_extensions_path =\/usr\/lib\/python2.7\/site-packages\/neutron\/plugins\/nuage/"  /etc/neutron/neutron.conf
#sed -i "s/^# core_plugin =.*/core_plugin =neutron.plugins.nuage.plugin.NuagePlugin/"  /etc/neutron/neutron.conf
# New Way:
crudini --set /etc/neutron/neutron.conf DEFAULT api_extensions_path "/usr/lib/python2.7/site-packages/nuage_neutron/plugins/nuage/extensions"
crudini --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips True
crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin neutron.plugins.nuage.plugin.NuagePlugin
crudini --del /etc/neutron/neutron.conf DEFAULT service_plugins 

#create nuage_plugin.ini
if [ -f /ext/neutron/plugins/nuage/nuage_plugin.ini ]; then
	rm -f /ext/neutron/plugins/nuage/nuage_plugin.ini
fi
mkdir -p /etc/neutron/plugins/nuage

echo "[RESTPROXY]" >> /etc/neutron/plugins/nuage/nuage_plugin.ini
echo "default_net_partition_name = OpenStack" >> /etc/neutron/plugins/nuage/nuage_plugin.ini
# Bug, tell developers, the below was wrong variable
echo "server = $ha_proxy_vip_inside:$ha_proxy_vsd_inside_port" >> /etc/neutron/plugins/nuage/nuage_plugin.ini
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
# old way:
# sed -i "s/^#plugin_dirs =.*/plugin_dirs = \/usr\/lib64\/heat,\/usr\/lib\/heat,\/usr\/local\/lib\/heat,\/usr\/local\/lib64\/heat,\/usr\/lib\/python2.7\/site-packages\/nuage-heat\/resources/" /etc/heat/heat.conf
# new way:
crudini --set /etc/heat/heat.conf DEFAULT plugin_dirs "/usr/lib64/heat,/usr/lib/heat,/usr/local/lib/heat,/usr/local/lib64/heat,/usr/lib/python2.7/site-packages/nuage-heat/resources/"
systemctl start openstack-heat-engine.service

# horizon extension configurations, see step 6 of page 17 of kilo guide
sed -i "s/HORIZON_CONFIG = {/HORIZON_CONFIG = {\n    'customization_module': 'nuage_horizon.customization',/" /usr/share/openstack-dashboard/openstack_dashboard/local/local_settings.py
sed -i "s/  Alias \/dashboard\/static/  Alias \/dashboard\/static\/nuage \"\/usr\/lib\/python2.7\/site-packages\/nuage_horizon\/static\"\n  Alias \/dashboard\/static/" /etc/httpd/conf.d/*-horizon_vhost.conf
service httpd restart

#haproxy
if grep "nuage_vsd" "/etc/haproxy/haproxy.cfg"  > /dev/null
then
	echo "Already found vsd config in /etc/haproxy/haproxy.cfg. Please check it manually."
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

systemctl daemon-reload

subscription-manager unregister

echo "Nuage integration completed."
echo "Make sure to create the neutron DB with the hkex_integrate_controller_db.sh script, then restart Neutron-Server"
echo "by executing on each node: systemctl restart neutron-server.service"





