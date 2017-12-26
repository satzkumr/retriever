#!/bin/bash
#######################################################################
# Creates docker file and builds your cluster based on the input files
#
# Contact: mrsathishkumar12@gmail.com
#
#######################################################################

RETRIEVER_HOME=/root/retriever

#sourcing input file

source $RETRIEVER_HOME/inputs/requirement.sh
source $RETRIEVER_HOME/inputs/docker_conf.sh

############################ Configurations #################################

#NFS server where your disk files get stored
NFS_SERVER="10.10.71.23"

#Bookeepker locations where all cluster information logged
BOOK_KEEPER=/mapr/My52Cluster_72/tmp/cluster_register

#Where your intermediate files go
outfile=$RETRIEVER_HOME/dockerfiles/$CLUSTER_NAME

#Path where your MapR-FS disk images are strored
DISKS_FILEPATH=/tmp/nfsmount/My52Cluster_72/tmp

########################### Configuration Ends here! #########################


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
	echo "RUN yum install lsof openssh-server" 
	echo "WORKDIR /tmp/setup/MapRRepoFiles" >> $outfile
	echo "RUN cp /tmp/setup/MapRRepoFiles/startscript /usr/sbin" >> $outfile
	echo "RUN chmod +x /usr/sbin/startscript" >> $outfile
	echo "RUN cp /tmp/setup/MapRRepoFiles/$1/* /etc/yum.repos.d/" >> $outfile

	#Creating mount point for storing your MapR-FS disk images
	echo "RUN mkdir /tmp/nfsmount" >> $outfile
	echo "RUN yum install nfs-utils -y" >> $outfile
	echo "RUN yum install mapr-core mapr-fileserver -y" >> $outfile
	echo "Creating Base docker file............................[DONE]"
}


#Actual logic where it assigns the roles to cluster
#Arguments: cluster roles

add_cluster_roles()
{
	#Removing the older cluster template if any, But this should not be the case
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

	clustertempdir=$RETRIEVER_HOME/cluster-templates/$CLUSTER_NAME
		
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
	
	#Passing cluster name to startsript to prepare the disk storage 

	# This is the startup point for the cluster where the disks are created and mounted
	for (( i=1; i<=$NODE_COUNT; i++))
        do
       echo "ENTRYPOINT "/usr/sbin/startscript $CLUSTER_NAME $NFS_SERVER $DISKS_FILEPATH $DISKS_PER_NODE" " >> $clustertempdir/${hosts[$i]}
	done;
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
		echo "$CLUSTER_NAME.$file"
		docker run -d -it --name $CLUSTER_NAME.$file --hostname $file --privileged $IMAGE_ID >> /tmp/${CLUSTER_NAME}_containerid 

	done;
	generate_hosts_file
	echo "Launch Complete !! Please run below commands on your docker images. once logging in"
	echo "Adding entry to cluster book keeper" 

	echo "$CLUSTER_NAME | $CLUSTER_VERSION | $NODE_COUNT  | $NODE_COMPONENTS " >> $BOOK_KEEPER 
	echo "-------------------------------------------------------------------------------------" >> $BOOK_KEEPER
	
	echo "-----------------------------------------------------------------------------------" 
	echo "/opt/mapr/server/configure.sh -N $CLUSTER_NAME -Z $ZK_HOSTNAMES -C $CLDB_HOSTNAMES -F /tmp/disk --create-user"
	echo "-----------------------------------------------------------------------------------" 
}

#Generating the hosts file for the conatiners for cluster
generate_hosts_file()
{
        idfile=/tmp/${CLUSTER_NAME}_containerid
        echo -e "127.0.0.1       localhost \n::1     localhost ip6-localhost ip6-loopback" > /tmp/${CLUSTER_NAME}_hosts
        if [ ! -f $idfile ]; then
            echo "ContainerId file $idfile not found! docker run did not run properly exiting"
            exit
        fi
        if [ ! -s $idfile ]; then
                echo "Empty file"
                exit
        fi
	file_content=`cat $idfile`

        echo Genrating the hosts file from docker inspect
        for node in $file_content
        do

                data=` docker inspect $node |grep -E  "Hostname\"|IPAddress\"|\"HostsPath\""|column -t  |uniq |tr -d \",\,,:|awk '{print $2}'|tr '\n' ':' |cut -d '%' -f1  |tr : " "`
        echo $data|cut -d " " -f2,3|awk '{print $2" "$1}' >> /tmp/${CLUSTER_NAME}_hosts

                hostfile_tmp=`echo $data|cut -d " " -f1`
		hostfile=`echo $hostfile $hostfile_tmp` 
        done

        for location in $hostfile
        do
                if [ ! -z "$location" ];then
                        echo Copying the hosts file to the hosts file
                        /bin/cp -f  /tmp/${CLUSTER_NAME}_hosts  $location
                fi
        done
       
	sleep 10s 
	for node in $file_content
        do
		echo "running Configure.sh  for" $node
               docker exec -it  $node /opt/mapr/server/configure.sh -N $CLUSTER_NAME -Z $ZK_HOSTNAMES -C $CLDB_HOSTNAMES -F /tmp/disks --create-user
		
	done 
	>/tmp/${CLUSTER_NAME}_containerid

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
		if [ $zks -gt 0 ] && [ $zks -le $nodes ] && [ $(( $zks % 2 )) -ne 0 ] ;
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

echo "Checking in cluster bookeeper for existing cluster names"
# Just to avod accidental overwrites of cluster

 grep -i -w $CLUSTER_NAME $BOOK_KEEPER
 
 if [ $? -ne 0 ] ;then
	echo " Cluster name not present..Good to go !"
 else
	echo "Cluster name already present... ! Exitting"
 	exit 1;
 fi

echo "----------------------------------------------------------------------------------------------------"
echo "Number of node: $NODE_COUNT , CLDBS: $NO_OF_CLDBS , Zookeepers: $NO_OF_ZKS , Resource Managers: $NO_OF_RMS , HOSTNAME parts : $NODE_HOSTS Cluster Version: $CLUSTER_VERSION"
echo "----------------------------------------------------------------------------------------------------"

#Calling main function to build docker file

build_docker_file $NODE_COUNT $NO_OF_CLDBS $NO_OF_ZKS $NO_OF_RMS $NODE_HOSTS $CLUSTER_VERSION
