#!/bin/bash


### Update resource names here ###
sub_id="64fd3ba5-b109-434e-aa61-6dd72c2341f2"
vmss1_name="ss1-vmss"
vmss2_name="ss2-vmss"
rg1_name="vmss1rg"
rg2_name="vmss2rg"
lb_name="my-lb"
hp_name="http_probe"
bap_name="myvnet-beap"
lb_rg="myrg"

# Resource path definition
py="python main.py"
sub_base_path="/subscriptions/${sub_id}"
vmss1_id="${sub_base_path}/resourceGroups/${rg1_name}/providers/Microsoft.Compute/virtualMachineScaleSets/${vmss1_name}"
vmss2_id="${sub_base_path}/resourceGroups/${rg2_name}/providers/Microsoft.Compute/virtualMachineScaleSets/${vmss2_name}"
hp_id="${sub_base_path}/resourceGroups /${lb_rg}/providers/Microsoft.Network/loadBalancers/${lb_name}/probes/${hp_name}"
bap_id="${sub_base_path}/resourceGroups/${lb_rg}/providers/Microsoft.Network/loadBalancers/${lb_name}/backendAddressPools/${bap_name}"
lb_ip="10.0.1.4"

# Start of script
echo "starting script"

#Disconnect both vmss from bap in case they were connected before
{
	start=`date +%s`
	$py deregister-vmss --vmss-id $vmss1_id && echo "Deregistration successful for vmss 1"
	end=`date +%s.%N`
	runtime1=$( echo "$end - $start" | bc -l )
} || {
	echo "Failed to deregister vmss 1"
}
{
	start=`date +%s`
	$py deregister-vmss --vmss-id $vmss2_id && echo "Deregistration successful for vmss 2"  
	end=`date +%s.%N`
	runtime2=$( echo "$end - $start" | bc -l )
} || {
	echo "Failed to deregister vmss 2"
}
echo "Runtime of deregistering vmss1 from bap: ${runtime1}"
echo "Runtime of deregistering vmss2 from bap: ${runtime2}"

### test order ###
# 1. Connect VMSS1
# 2. Test connection
# 3. Connect VMSS2
# 4. Block VMSS1
# 5. Disconnect VMSS1

$py register-vmss --bap-id $bap_id --vmss-id $vmss1_id --health-probe-id $hp_id
$py open-vmss --vmss-id $vmss1_id
#Test connection here

