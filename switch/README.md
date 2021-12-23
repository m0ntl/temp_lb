# Usage

`Deploy0` deploys a VNET, subnets, Azure LB (including BAP, probe and routing rule), Azure Bastion service and a VMSS cluster 'management' with 1 instance. Variables can change the deployment structure, e.g., to use Application Gateway. 
`Deploy1` and `Deploy2` deploy a VMSS with a NSG that disallows LB probes to probe instances. Variables can be used to associate the instances with a BAP.

The idea is to use Azure Bastion to connect to the management instance. This will allow you to do `curl http://ip-lb` to test connection to backend-servers. 

To control the LB's access to backend servers, use Python script in `switch/switch/main.py`. See `python main.py --help` for help. Example: `python main.py open-vmss --vmss-id="/subscriptions/subscription-id/resourceGroups/vmss2rg/providers/Microsoft.Compute/virtualMachineScaleSets/ss2-vmss"`

Note: If VMSS1 is closed (via update to NSG) before VMSS2 is opened then consumers will continue to get data from VMSS1. This will change when VMSS2 is opened. https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-custom-probe-overview

| Description | Standard SKU | Basic SKU |
| ----------- | ------------ | --------- |
| Probe types |	TCP, HTTP, HTTPS |	TCP, HTTP |
| Probe down behavior |	All probes down, **all TCP flows continue.** | All probes down, all TCP flows expire. |