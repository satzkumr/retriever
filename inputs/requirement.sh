#!/bin/bash

#Name of the cluster you want

CLUSTER_NAME="multicluster"

#Cluster version

CLUSTER_VERSION="5.2.2"

#Number of nodes you want

NODE_COUNT=2

#Disks per node - Shared environment - Please use wisely

DISKS_PER_NODE=2

#Hostname string, note that hostname would be added with 1,2.. if you want multiple hosts,Example:
#myhost1.cluster.com,myhost2...

NODE_HOSTS="myhost.cluster.com"

#Components 

#Number of CLDB nodes

NO_OF_CLDBS=2

#Number of Zookeepers

NO_OF_ZKS=1

#Number of resourcemanagers

NO_OF_RMS=2

#Other components

NODE_COMPONENTS="drill spark hive"

NO_OF_DRILL=1
