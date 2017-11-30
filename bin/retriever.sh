#!/bin/bash

RETRIEVER_HOME=/home/mapr/myProjects/retriever

#sourcing input file

source $RETRIEVER_HOME/inputs/requirement.sh
source $RETRIEVER_HOME/inputs/docker_conf.sh

outfile=$RETRIEVER_HOME/dockerfiles/$CLUSTER_NAME

#Funciton implementations goes here!

create_host_names()
{
	echo "Generating hostnames"
	i=1
	declare -ga hosts
	while [ $i -le $2 ]
	do
		nodename=`echo $1 | awk -F '.' '{print $1}'`
		domain=`echo $1 | awk -F '.' '{print $2 "." $3}'`
		newhost="$nodename$i.$domain"
		hosts[$i]="$newhost"
		echo $nodename$i.$domain
		i=$((i+1))
	done;
}

create_base_dockerfile()
{

	#this will empty the file if any with the same cluster name
	echo "FORM $FROM_SRC" > $outfile
	echo "RUN yum install git -y" >> $outfile
	echo "RUN rm -rf /tmp/setup" >> $outfile
	echo "RUN mkdir /tmp/setup" >> $outfile
	echo "WORKDIR /tmp/setup" >> $outfile
	echo "RUN git clone "http://github.com/satzkumr/MapRRepoFiles.git"" >> $outfile
	echo "RUN yum clean all" >> $outfile
	echo "RUN yum install java-1.7.0-openjdk.x86_64 -y " >>$outfile
	echo "RUN yum install *jdk-devel* -y" >> $outfile
}

#Arguments, NO_OF_NODES,$NO_OF_CLDBS,$NO_OF_ZKS,$NO_OF_RMS,$NODE_HOSTS

build_docker_file()
{
	nodes=$1 
	cldbs=$2
	zks=$3
	rms=$4
	hostnames=$5
	#calling utility function to generate hostnames"
	create_host_names $hostnames $nodes

	create_base_dockerfile 
}



















#Execution starts here!

echo "Welcome to retriever cluster builder"
echo "Hang on! ... Retrieving your cluster requirements"

#Checking the presence of input file

if [ -f $RETRIEVER_HOME/inputs/requirement.sh ];then
	echo "Input file present."
else
	echo "Input file not present ! Something is not right"
	exit 1;
fi

echo "Good, we got your requirement file, here is the replay"
echo "Number of node: $NODE_COUNT , CLDBS: $NO_OF_CLDBS , Zookeepers: $NO_OF_ZKS , Resource Managers: $NO_OF_RMS , HOSTNAME parts : $NODE_HOSTS Cluster Version: $CLUSTER_VERSION"

#Calling main function to build docker file

build_docker_file $NODE_COUNT $NO_OF_CLDBS $NO_OF_ZKS $NO_OF_RMS $NODE_HOSTS
