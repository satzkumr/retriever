#!/bin/bash
#######################################################################
# Creates docker file and builds your cluster based on the input files
#
# Contact: mrsathishkumar12@gmail.com
#
#######################################################################

RETRIEVER_HOME=/home/mapr/myProjects

#sourcing input file

source $RETRIEVER_HOME/inputs/requirement.sh
source $RETRIEVER_HOME/inputs/docker_conf.sh

#NFS Server Mount path - It is not used right now!
NFS_SERVER="10.10.71.23"

outfile=$RETRIEVER_HOME/dockerfiles/$CLUSTER_NAME

#Path where your MapR-FS disk images are strored
DISKS_FILEPATH=/tmp/nfsmount/My52Cluster_72/tmp

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
	echo "FROM $FROM_SRC" > $outfile
	echo "RUN yum install git -y" >> $outfile
	echo "RUN rm -rf /tmp/setup" >> $outfile
	echo "RUN mkdir /tmp/setup" >> $outfile
	echo "WORKDIR /tmp/setup" >> $outfile
	echo "RUN git clone "http://github.com/satzkumr/MapRRepoFiles.git"" >> $outfile
	echo "RUN yum clean all" >> $outfile
	echo "RUN yum install java-1.7.0-openjdk.x86_64 -y " >>$outfile
	echo "RUN yum install *jdk-devel* -y" >> $outfile
	#Adding Utilities 
	#echo "RUN yum install lsof openssh-server" 
	echo "WORKDIR /tmp/setup/MapRRepoFiles" >> $outfile
	echo "RUN cp /tmp/setup/MapRRepoFiles/startscript /usr/sbin" >> $outfile
	echo "RUN chmod +x /usr/sbin/startscript" >> $outfile
	echo "RUN cp /tmp/setup/MapRRepoFiles/$1/* /etc/yum.repos.d/" >> $outfile

	#Creating mount point for storing your MapR-FS disk images
	echo "RUN mkdir /tmp/nfsmount" >> $outfile
	echo "RUN yum install nfs-utils -y" >> $outfile
	echo "RUN yum install mapr-core mapr-fileserver -y" >> $outfile
	#echo "ENTRYPOINT "/usr/sbin/startscript" " >> $outfile
	echo "Creating Base docker file............................[DONE]"
}


#Actual logic where it assigns the roles to cluster
#Arguments: cluster roles

add_cluster_roles()
{

	rm -rf $RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME
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
	
 	i=1;	

	#Create disks file for each node, This would be used along with configure.sh -F
	clustertempdir=$RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME

	echo "Pre-creating Disk list file for each node... By defult 1 Disk for each node"
	while [ $i -le $NODE_COUNT ];
	do
		echo "Disk created for ${hosts[$i]}"
		#Writing disk list file
		echo "RUN echo $DISK_FILEPATH/${hosts[$i]} >> /tmp/disk"
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
				 echo "RUN yum install mapr-drillbits -y >> $clustertempdir/${hosts[$i]}"
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
		mkdir -p $RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME/$file.tmp
		mv $RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME/$file $RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME/$file.tmp/Dockerfile

		#Building Images
		docker build -t $CLUSTER_NAME:$file "$RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME/$file.tmp" 
		
		#Getting Image name before starting one by one
		IMAGE_ID=$(docker images | grep $CLUSTER_NAME |grep -v latest | grep $file | awk -F ' ' '{print $3 }')
		echo "$file .......Docker image ID: $IMAGE_ID ..... [ DONE ]"
		docker run -d -it --hostname $file --privileged $IMAGE_ID

	done;

	echo "Launch Complete !! Please run below commands on your docker images. once logging in"
	echo "-----------------------------------------------------------------------------------" 
	echo "1. Run /usr/sbin/startscript "
	echo "2. Check the /etc/hosts"
	echo "3. /opt/mapr/server/configure.sh -N $CLUSTER_NAME -Z $ZK_HOSTNAMES -C $CLDB_HOSTNAMES -F /tmp/disk"
	echo "-----------------------------------------------------------------------------------" 
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

	if [ $cldbs -gt 0 ] && [ $cldbs -le $nodes ] ;
	then
		#CLDB count seems to be good ! Lets check zk count
		if [ $zks -gt 0 ] && [ $zks -le $nodes ];
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
