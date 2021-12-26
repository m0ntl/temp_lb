#!/bin/bash


### Update resource details here ###
sub_id="64fd3ba5-b109-434e-aa61-6dd72c2341f2"
vmss1_name="ss1-vmss"
vmss2_name="ss2-vmss"
rg1_name="vmss1rg"
rg2_name="vmss2rg"
lb_name="my-lb"
hp_name="http_probe"
bap_name="myvnet-beap"
lb_rg="myrg"
lb_ip="10.0.1.4"
vmss1_ip="10.0.100.5"
vmss2_ip="10.0.101.4"

# Resource path definition
py="python main.py"
sub_base_path="/subscriptions/${sub_id}"
vmss1_id="${sub_base_path}/resourceGroups/${rg1_name}/providers/Microsoft.Compute/virtualMachineScaleSets/${vmss1_name}"
vmss2_id="${sub_base_path}/resourceGroups/${rg2_name}/providers/Microsoft.Compute/virtualMachineScaleSets/${vmss2_name}"
hp_id="${sub_base_path}/resourceGroups/${lb_rg}/providers/Microsoft.Network/loadBalancers/${lb_name}/probes/${hp_name}"
bap_id="${sub_base_path}/resourceGroups/${lb_rg}/providers/Microsoft.Network/loadBalancers/${lb_name}/backendAddressPools/${bap_name}"

allowed_commands=["help","open_timer","close_timer"]

deregisterAllVMSS(){
	#Disconnect both vmss from bap in case they were connected before
	echo "Starting to deregister VMSS..."
	{
		$py deregister-vmss --vmss-id $vmss1_id && echo "Deregistration successful for vmss 1"
		$py perform-upgrade --vmss-id $vmss1_id
	} || {
		echo "Failed to deregister vmss 1"
	}
	{
		$py deregister-vmss --vmss-id $vmss2_id && echo "Deregistration successful for vmss 2"  
		$py perform-upgrade --vmss-id $vmss2_id
	} || {
		echo "Failed to deregister vmss 2"
	}
}

help(){
	echo "Script to test Forter VMSS PoC"
	echo "Enter 1 or more of the following options:"
	echo "open_timer - how long it takes for a port open to take effect both directly & via lb"
	echo "close_timer - how long it takes for a port close to stop responding directly & via lb"
}

open_timer(){
	echo "Starting open_timer test"
	deregisterAllVMSS
	$py close-vmss --vmss-id $vmss1_id 
	$py register-vmss --bap-id $bap_id --vmss-id $vmss1_id --health-probe-id $hp_id
	$py perform-upgrade --vmss-id $vmss1_id
	$py open-vmss --vmss-id $vmss1_id
	startOpenPortTiming=`date +%s`
	lb_response=$(curl http://$lb_ip --connect-timeout 3 -s)
	vmss1_response=$(curl http://$vmss1_ip --connect-timeout 3 -s)
	while [[ $lb_response != *"Blue"* ]] || [[ $vmss1_response != *"Blue"* ]] 
	do
		echo "lb rsponse is: ${lb_response}"
		echo "vmss1 response is: ${vmss1_response}"
		sleep 1
		lb_response=$(curl http://$lb_ip --connect-timeout 3 -s)
		vmss1_response=$(curl http://$vmss1_ip  --connect-timeout 3 -s)
	done
	endOpenPortTiming=`date +%s.%N`
	echo "lb rsponse is: ${lb_response}"
	echo "vmss1 response is: ${vmss1_response}"
	openPortTotalTime=$( echo "$endOpenPortTiming - $startOpenPortTiming" | bc -l )
	echo "total time: $openPortTotalTime"
}

close_timer(){
	#Clean enviroment - deregister + open port + register + update
	deregisterAllVMSS
	echo "Starting close_timer test"
	$py open-vmss --vmss-id $vmss1_id
	$py register-vmss --bap-id $bap_id --vmss-id $vmss1_id --health-probe-id $hp_id
	$py perform-upgrade --vmss-id $vmss1_id
	
	# Wait for port to be open (same response from lb and vmss)
	lb_response=$(curl http://$lb_ip --connect-timeout 3 -s)
	vmss1_response=$(curl http://$vmss1_ip --connect-timeout 3 -s)
	while [[ $lb_response != *"Blue"* ]] || [[ $vmss1_response != *"Blue"* ]] 
	do
		echo "Waiting for port to be open..."
		echo "lb rsponse is: ${lb_response}"
		echo "vmss1 response is: ${vmss1_response}"
		sleep 1
		lb_response=$(curl http://$lb_ip --connect-timeout 3 -s)
		vmss1_response=$(curl http://$vmss1_ip  --connect-timeout 3 -s)
	done
	
	#Close port and start timer
	$py close-vmss --vmss-id $vmss1_id 
	#Start timer
	startClosePortTiming=`date +%s`
	#fetch response directly & via lb
	lb_response=$(curl http://$lb_ip --connect-timeout 3 -s)
	vmss1_response=$(curl http://$vmss1_ip --connect-timeout 3 -s)
	#wait for vmss & lb to return empty
	while [[ $lb_response == *"Blue"* ]] || [[ $vmss1_response == *"Blue"* ]] 
	do
		echo "lb rsponse is: ${lb_response}"
		echo "vmss1 response is: ${vmss1_response}"
		sleep 1
		lb_response=$(curl http://$lb_ip --connect-timeout 3 -s)
		vmss1_response=$(curl http://$vmss1_ip  --connect-timeout 3 -s)
	done
	#Close timer
	endClosePortTiming=`date +%s.%N`
	echo "lb rsponse is: ${lb_response}"
	echo "vmss1 response is: ${vmss1_response}"
	closePortTotalTime=$( echo "$endClosePortTiming - $startClosePortTiming" | bc -l )
	#Echo total time taken
	echo "total time: $closePortTotalTime"
}

if [ $# == 0 ] 
then
	help
else
	for var in "$@"
	do
		if [[ $allowed_commands =~ $var ]]; 
		then 
			$var 
		else
			echo "Invalid argument: $var"
			echo "run with \"help\" for possible arguments"
		fi
	done
fi


### test order ###
# 1. Connect VMSS1
# 2. Test connection
# 3. Connect VMSS2
# 4. Block VMSS1
# 5. Disconnect VMSS1
#echo "Start test"
#echo "Connected VMSS1 with nsg blocking HP"
#echo "vmss1_response: ${vmss1_response}"
#echo "lb_response: ${lb_response}"
#echo "now opening the NSG and waiting for LB to return correct page..."
#echo "waiting for LB to reflect vmss1 response"
#while [ "${vmss1_response}" != "${lb_response}" ]
#do
#	#echo "waiting for LB to reflect vmss1 response"
#	echo -ne "\b$i"
#	sleep 0.05
#	lb_response=$(curl http://$lb_ip --connect-timeout 3 -s)
#done
#
##switch over to vmss2
#$py open-vmss --vmss-id $vmss2_id
#$py register-vmss --bap-id $bap_id --vmss-id $vmss2_id --health-probe-id $hp_id
#$py perform-upgrade --vmss-id $vmss2_id
#$py close-vmss --vmss-id $vmss1_id #for testing only
#vmss2_response=$(curl http://$vmss2_ip)
#echo "waiting for LB to reflect vmss2 response"
#while [ "${vmss2_response}" != "${lb_response}" ]
#do
#	#echo "waiting for LB to reflect vmss2 response"
#	echo -ne "\b$i"
#	sleep 0.05
#	lb_response=$(curl http://$lb_ip --connect-timeout 3 -s)
#done
#
#
#echo "script DONE"
#echo $vmss1_response
#echo $vmss2_response
#echo $lb_response












