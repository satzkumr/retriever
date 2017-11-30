#!/bin/bash
#######################################################################
# Creates docker file and builds your cluster based on the input files
#
# Contact: mrsathishkumar12@gmail.com
#
#######################################################################

RETRIEVER_HOME=/home/mapr/myProjects/retriever

#sourcing input file

source $RETRIEVER_HOME/inputs/requirement.sh
source $RETRIEVER_HOME/inputs/docker_conf.sh

outfile=$RETRIEVER_HOME/dockerfiles/$CLUSTER_NAME

#Funciton implementations goes here!

#Utility function that generates hostnames for your cluster from the hoststring provided
#Arguments: hoststring, number of nodes

create_host_names()
{
	echo "Generating hostnames...................[ DONE ]"
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

#Creates a base docker file which contains java and MapR repository files
#Arguments: version of MapR cluster

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
	echo "WORKDIR /tmp/setup/MapRRepoFiles" >> $outfile
	echo "RUN find . -type d ! -name "$1" | xargs rm -rf " >> $outfile
	echo "RUN cp /tmp/setup/MapRRepoFiles/$1/* /etc/yum.repos.d/" >> $outfile
	echo "RUN yum install mapr-core mapr-fileserver mapr-nodemanager" >> $outfile
}


#Main function which calls sub functions
#Arguments: NO_OF_NODES,$NO_OF_CLDBS,$NO_OF_ZKS,$NO_OF_RMS,$NODE_HOSTS, Version of mapr cluster

build_docker_file()
{
	nodes=$1 
	cldbs=$2
	zks=$3
	rms=$4
	hostnames=$5
	version=$6
	#calling utility function to generate hostnames"
	create_host_names $hostnames $nodes

	create_base_dockerfile $version 

	if [ $cldbs -gt 0 ] && [ $cldbs -lt $nodes ] ;
	then
		cat $outfile > "$outfile.masternodes"
		echo "RUN yum install mapr-cldb -y" >> "$outfile.masternodes"
		if [ $zks -gt 0 ] && [ $zks -lt $nodes ];
		then
			echo "RUN yum install mapr-zookeeper -y" >> "$outfile.masternodes"
		else
			echo "Invalid zookeeper count..Make sure you have given correct number of nodes or count in odd numbers..Exitting" 
			exit 1;
		fi
	else
		echo "Invalid CLDB count...Make sure you have given atleast 1 cldb and not greater than nodes in cluster...Exitting"
		exit 1;
	fi

#	create_mapr_dockerfile
}


#Execution starts here!

echo "Welcome to retriever cluster builder"
echo "Retrieving your cluster requirements.............[DONE]"

#Checking the presence of input file

if [ -f $RETRIEVER_HOME/inputs/requirement.sh ];then
	echo "Good, we got your requirement file, here is the replay"
else
	echo "Input file not present ! Something is not right"
	exit 1;
fi

echo "----------------------------------------------------------------------------------------------------"
echo "Number of node: $NODE_COUNT , CLDBS: $NO_OF_CLDBS , Zookeepers: $NO_OF_ZKS , Resource Managers: $NO_OF_RMS , HOSTNAME parts : $NODE_HOSTS Cluster Version: $CLUSTER_VERSION"
echo "----------------------------------------------------------------------------------------------------"
#Calling main function to build docker file

build_docker_file $NODE_COUNT $NO_OF_CLDBS $NO_OF_ZKS $NO_OF_RMS $NODE_HOSTS $CLUSTER_VERSION
