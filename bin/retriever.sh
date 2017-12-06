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


# Other Global vars for this code
CLDB_HOSTNAMES=""
ZK_HOSTNAMES=""

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
		#echo $nodename$i.$domain
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
	echo "RUN yum install mapr-core mapr-fileserver" >> $outfile
	echo "Creating Base docker file............................[DONE]"
}


#Actual logic where it assigns the roles to cluster
#Arguments: cluster roles

add_cluster_roles()
{

	mkdir -p $RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME
	cp $outfile $RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME
	echo "Building template for nodes.."
	i=1;
	while [ $i -le $NODE_COUNT ];
	do
		echo "${hosts[$i]}  ...... [ DONE ]"
		cp $outfile $RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME/${hosts[$i]}
		clustertempdir=$RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME
		i=$((i+1))
	done;

		# Adding CLDB Roles to cluster template
		echo "-------------------------------------------------------------------------"
		echo "Adding CLDB Roles"
		echo "-------------------------------------------------------------------------"	
		for (( i=1; i<=$NO_OF_CLDBS; i++ ))
		do
	 		#Adding CLDB role to node
			echo "RUN yum install mapr-cldb -y" >> $clustertempdir/${hosts[$i]}			
			CLDB_HOSTNAMES="${CLDB_HOSTNAMES} ${hosts[$i]}"
		done;
		echo "CLDB roles added to Hosts: $CLDB_HOSTNAMES .........[DONE]"

		#Adding Zookeeper role to cluster nodes

		echo "-------------------------------------------------------------------------"
                echo "Adding Zookeeper Roles"
                echo "-------------------------------------------------------------------------"   

		for (( i=1; i<=$NO_OF_ZKS; i++))
                do
                        #Adding Zookeeper role to nodes
                        echo "RUN yum install mapr-zookeeper -y" >> $clustertempdir/${hosts[$i]}
			ZK_HOSTNAMES="${ZK_HOSTNAMES} ${hosts[$i]}"
                done;
		echo "Zookeeper roles added to Hosts: $ZK_HOSTNAMES .........[DONE]"

		#Adding Resourcemanager role to cluster nodes
		echo "-------------------------------------------------------------------------"
                echo "Adding Resourcemanager Roles"
                echo "-------------------------------------------------------------------------"   
		for (( i=1; i<=$NO_OF_RMS; i++))
                do
                        #Adding Resourcemanager role to nodes
                        echo "RUN yum install mapr-resourcemanager -y" >> $clustertempdir/${hosts[$i]}
                done;
		echo "Resource manager roles added to Hosts...............[DONE]"
		
		#Adding Nodemanager role to cluster nodes, By default all the nodes installed with NM Role

		echo "-------------------------------------------------------------------------"
                echo "Adding Node manager Roles"
                echo "-------------------------------------------------------------------------"  
                for (( i=1; i<=$NODE_COUNT; i++))
                do
                        #Adding Nodemanager role to nodes
                        echo "RUN yum install mapr-nodemanager -y" >> $clustertempdir/${hosts[$i]}
                done;	
		echo "Node manager roles added to all hosts...............[DONE]"	

		#Adding other roles mentioned in requirement
		for role in $NODE_COMPONENTS
		do
			if [ $role == drill ];
			then
				for (( i=1; i<$NO_OF_DRILL;i++))
				do
				echo "RUN yum install mapr-drillbits -y" >> $clustertempdir/${hosts[$i]}
				done;
			fi
		done;
		#To be done for other roles as well
}

#Function that runs your docker files and build the cluster
#Arguments: None

execute_docker_files()
{
	echo "----------------------------------------------------------------"
	echo "Preparing to execute your docker files.."
	echo "----------------------------------------------------------------"
	echo "Retriving files from your cluster template directory..for cluster $CLUSTERNAME"
	rm -f $RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME/$CLUSTER_NAME
	for file in `ls $RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME`
	do
	 	IMAGE_ID=$(docker build -t $CLUSTERNAME/$file $RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME/$file 2>/dev/null | awk '/Successfully built/{print $NF}')		
		echo "$file .......Docker image ID: $IMAGE_ID ..... [ DONE ]"
		#docker run -d -it --hostname $file --privileged $IMAGE_ID

	done;
	echo "Launch Complete !! Please run below command on your docker images. once logging in"
	echo "----------------------------------------------------------------" 
	echo "/opt/mapr/server/configure.sh -N $CLUSTER_NAME -Z $ZK_HOSTNAMES -C $CLDB_HOSTNAMES -F <disks file>"
	echo "----------------------------------------------------------------" 
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

	# Doing small validation on cluster requirement before building the file, Checks if CLDB > 0  and Less than the number of nodes

	if [ $cldbs -gt 0 ] && [ $cldbs -lt $nodes ] ;
	then
		#CLDB count seems to be good ! Lets check zk count
		if [ $zks -gt 0 ] && [ $zks -lt $nodes ];
		then
			echo "Zookeeper count is good !"
		else
			echo "Invalid zookeeper count..Make sure you have given correct number of nodes or count in odd numbers..Exitting" 
			exit 1;
		fi
	else
		echo "Invalid CLDB count...Make sure you have given atleast 1 cldb and not greater than nodes in cluster...Exitting"
		exit 1;
	fi
	
	create_base_dockerfile $version 

	add_cluster_roles $NODE_COMPONENTS

	execute_docker_files
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
