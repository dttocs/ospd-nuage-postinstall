#!/bin/bash
#
#Configuration Script for the Sandbox Overcloud DB Nodes
#@author: Philippe Jeurissen (Nuage Networks)
#

echo "DB creation, only run once!"
mysql <<EOF
drop database ovs_neutron;
create database ovs_neutron;
EOF
neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/nuage/nuage_plugin.ini upgrade head

echo "DB creation COMPLETED!"
echo "Do NOT run this on the other DB nodes!!!"








