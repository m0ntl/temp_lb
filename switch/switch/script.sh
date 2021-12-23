#!/bin/bash

echo "starting script"
py="python main.py"

sub_path="/subscriptions/64fd3ba5-b109-434e-aa61-6dd72c2341f2/"
vmss1_id="${sub_path}resourceGroups/vmss1rg/providers/Microsoft.Compute/virtualMachineScaleSets/ss1-vmss"
vmss2_id="${sub_path}resourceGroups/vmss2rg/providers/Microsoft.Compute/virtualMachineScaleSets/ss2-vmss"
hp_id="${sub_path}resourceGroups/myrg/providers/Microsoft.Network/loadBalancers/my-lb/probes/http_probe"
bap_id="${sub_path}resourceGroups/myrg/providers/Microsoft.Network/loadBalancers/my-lb/backendAddressPools/myvnet-beap"

#Disconnect both vmss from bap in case they were connected before

{
	start=`date +%s`
	$py deregister-vmss --vmss-id $vmss1_id && echo "Deregistration successful for vmss1"
	end=`date +%s.%N`
	runtime1=$( echo "$end - $start" | bc -l )
} || {
	echo "Failed to deregister vmss1"
}

{
	start=`date +%s`
	$py deregister-vmss --vmss-id $vmss2_id && echo "Deregistration successful for vmss2"  
	end=`date +%s.%N`
	runtime2=$( echo "$end - $start" | bc -l )
} || {
	echo "Failed to deregister vmss2"
}
echo "Runtime of deregistering vmss1 from bap: ${runtime1}"
echo "Runtime of deregistering vmss2 from bap: ${runtime2}"
