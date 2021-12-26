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

#Script progress indicator
spin[0]="-"
spin[1]="\\"
spin[2]="|"
spin[3]="/"

# Start of script
echo "starting script"

#Disconnect both vmss from bap in case they were connected before
{
	start=`date +%s`
	$py deregister-vmss --vmss-id $vmss1_id && echo "Deregistration successful for vmss 1"
	$py perform-upgrade --vmss-id $vmss1_id
	end=`date +%s.%N`
	runtime1=$( echo "$end - $start" | bc -l )
} || {
	echo "Failed to deregister vmss 1"
}
{
	start=`date +%s`
	$py deregister-vmss --vmss-id $vmss2_id && echo "Deregistration successful for vmss 2"  
	$py perform-upgrade --vmss-id $vmss2_id
	end=`date +%s.%N`
	runtime2=$( echo "$end - $start" | bc -l )
} || {
	echo "Failed to deregister vmss 2"
}
#echo "Runtime of deregistering vmss1 from bap: ${runtime1}"
#echo "Runtime of deregistering vmss2 from bap: ${runtime2}"

### test order ###
# 1. Connect VMSS1
# 2. Test connection
# 3. Connect VMSS2
# 4. Block VMSS1
# 5. Disconnect VMSS1
echo "Start test"
$py close-vmss --vmss-id $vmss1_id #for testing only
sleep 30
$py register-vmss --bap-id $bap_id --vmss-id $vmss1_id --health-probe-id $hp_id
$py perform-upgrade --vmss-id $vmss1_id
lb_response=$(curl http://$lb_ip --connect-timeout 3 -s)
vmss1_response=$(curl http://$vmss1_ip -s)
while [[ $lb_response != *"Blue"* ]] && [[ $vmss1_response != *"Blue"* ]] then
do
	echo "lb rsponse is: ${lb_response}"
	echo "vmss1 response is: ${vmss1_response}"
	sleep 1
	lb_response=$(curl http://$lb_ip --connect-timeout 3 -s)
	vmss1_response=$(curl http://$vmss1_ip -s)
done

echo "lb rsponse is: ${lb_response}"
echo "vmss1 response is: ${vmss1_response}"
#echo "Connected VMSS1 with nsg blocking HP"
#echo "vmss1_response: ${vmss1_response}"
#echo "lb_response: ${lb_response}"
#echo "now opening the NSG and waiting for LB to return correct page..."
#$py open-vmss --vmss-id $vmss1_id
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












