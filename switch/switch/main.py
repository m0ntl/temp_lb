from typing import TypedDict, Literal, Union, Optional, List

import click
import os
import asyncio
import time
import azure.mgmt.compute.aio as aioc
import azure.identity.aio as aioi
from functools import wraps

from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.network.models import BackendAddressPool, NetworkSecurityGroup
from azure.mgmt.compute import ComputeManagementClient

from azure.mgmt.compute.models import (
    VirtualMachineScaleSet,
    ApiEntityReference,
    VirtualMachineScaleSetVMInstanceRequiredIDs,
    VirtualMachineStatusCodeCount,
    InstanceViewStatus,
)
from azure.mgmt.storage import StorageManagementClient
from azure.mgmt.resource import ResourceManagementClient
from azure.identity import ClientSecretCredential
from azure.monitor.query import MetricsQueryClient, MetricsQueryResult


# "/subscriptions/subscription-id/resourceGroups/myrg/providers/Microsoft.Network/loadBalancers/my-lb/backendAddressPools/myvnet-beap"
# "/subscriptions/subscription-id/resourceGroups/myrg/providers/Microsoft.Network/virtualNetworks/myvnet/subnets/consumer-subnet"
# "/subscriptions/subscription-id/resourceGroups/vmss1rg/providers/Microsoft.Compute/virtualMachineScaleSets/ss1-vmss"


def coro(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        return asyncio.run(f(*args, **kwargs))

    return wrapper


class Memory(TypedDict):
    """
    Cache of credentials used by functions
    """

    credentials: ClientSecretCredential
    aio_credentials: aioi.ClientSecretCredential
    subscription_id: str


memory = Memory(
    credentials=ClientSecretCredential(
        client_id=os.environ["AZURE_CLIENT_ID"],
        client_secret=os.environ["AZURE_CLIENT_SECRET"],
        tenant_id=os.environ["AZURE_TENANT_ID"],
    ),
    aio_credentials=aioi.ClientSecretCredential(
        client_id=os.environ["AZURE_CLIENT_ID"],
        client_secret=os.environ["AZURE_CLIENT_SECRET"],
        tenant_id=os.environ["AZURE_TENANT_ID"],
    ),
    subscription_id=os.environ.get("AZURE_SUBSCRIPTION_ID", "64fd3ba5-b109-434e-aa61-6dd72c2341f2"),
)


def create_azure_session(
    credentials: ClientSecretCredential, subscription_id: str, service: str
) -> Union[
    ComputeManagementClient,
    NetworkManagementClient,
    StorageManagementClient,
    ResourceManagementClient,
    MetricsQueryClient,
    aioc.ComputeManagementClient,
]:
    """
    Creates a Azure session client, used for updating resources
    """
    assert service in ["compute", "network", "security", "storage", "resource", "metrics", "async-compute"]

    if service == "compute":
        return ComputeManagementClient(credentials, subscription_id)
    if service == "network":
        return NetworkManagementClient(credentials, subscription_id)
    if service == "storage":
        return StorageManagementClient(credentials, subscription_id)
    if service == "resource":
        return ResourceManagementClient(credentials, subscription_id)
    if service == "metrics":
        return MetricsQueryClient(credentials)
    if service == "async-compute":
        return aioc.ComputeManagementClient(credentials, subscription_id)


def disassociate_vmss_bap(compute_client: ComputeManagementClient, vmss_id: str):
    """
    Remove a VMSS's BAP association
    """
    vmss_id_elements = vmss_id.split("/")
    vmss_resource_group_name = vmss_id_elements[4]
    vmss_name = vmss_id_elements[8]

    vmss: VirtualMachineScaleSet = compute_client.virtual_machine_scale_sets.get(
        resource_group_name=vmss_resource_group_name, vm_scale_set_name=vmss_name
    )

    vmss.virtual_machine_profile.network_profile.network_interface_configurations[0].ip_configurations[
        0
    ].load_balancer_backend_address_pools = None
    #If a vmss has a health probe, must remove it when removing from the lb bap
    if vmss.virtual_machine_profile.network_profile is not None:
        vmss.virtual_machine_profile.network_profile.health_probe = None
    poller = compute_client.virtual_machine_scale_sets.begin_update(
        resource_group_name=vmss_resource_group_name, vm_scale_set_name=vmss_name, parameters=vmss
    )
    poller.wait()
    print(poller.status())


def manage_nsg_rule_lb_probe(
    compute_client: ComputeManagementClient,
    network_client: NetworkManagementClient,
    vmss_id: str,
    access: Literal["Allow", "Deny"],
):
    """
    Allow or Deny an LB's probe to access backend servers
    """
    vmss_id_elements = vmss_id.split("/")
    vmss_resource_group_name = vmss_id_elements[4]
    vmss_name = vmss_id_elements[8]

    vmss: VirtualMachineScaleSet = compute_client.virtual_machine_scale_sets.get(
        resource_group_name=vmss_resource_group_name, vm_scale_set_name=vmss_name
    )
    nsg_id = vmss.virtual_machine_profile.network_profile.network_interface_configurations[
        0
    ].network_security_group.id  # /subscriptions/subscription-id/resourceGroups/vmss1rg/providers/Microsoft.Network/networkSecurityGroups/ss1-vmss-nsg
    nsg_resource_group_name = nsg_id.split("/")[4]
    nsg_name = nsg_id.split("/")[8]

    nsg: NetworkSecurityGroup = network_client.network_security_groups.get(
        resource_group_name=nsg_resource_group_name, network_security_group_name=nsg_name
    )

    for sr in nsg.security_rules:
        if sr.name == "lb-probe-access":  # name is set in TF code
            sr.access = access
            break

    poller = network_client.network_security_groups.begin_create_or_update(
        resource_group_name=vmss_resource_group_name, network_security_group_name=nsg_name, parameters=nsg
    )
    poller.wait()
    print(poller.status())


def _get_vmss_instance_ids(compute_client: ComputeManagementClient, vmss_resource_group_name, vmss_name) -> List[str]:
    vm_plist = compute_client.virtual_machine_scale_set_vms.list(vmss_resource_group_name, vmss_name)
    instance_ids = []
    for vmss_lr in vm_plist:
        instance_ids.append(vmss_lr.instance_id)
    return instance_ids


def os_upgrade(compute_client: ComputeManagementClient, vmss_id: str):
    """
    Perform an os upgrade
    """
    vmss_id_elements = vmss_id.split("/")
    vmss_resource_group_name = vmss_id_elements[4]
    vmss_name = vmss_id_elements[8]

    poller = compute_client.virtual_machine_scale_sets.begin_update_instances(
        vmss_resource_group_name, vmss_name, VirtualMachineScaleSetVMInstanceRequiredIDs(instance_ids=["*"])
    )
    # poller = compute_client.virtual_machine_scale_sets.begin_reimage_all(
    #     vmss_resource_group_name, vmss_name, VirtualMachineScaleSetVMInstanceIDs()
    # )  # did not upgrade OS
    # poller = compute_client.virtual_machine_scale_set_rolling_upgrades.begin_start_os_upgrade(
    #     vmss_resource_group_name, vmss_name
    # ) # did not upgrade OS
    poller.wait()
    print(poller.status())


def print_metrics_query_result(mqr: MetricsQueryResult):
    print("cost: " + str(mqr.cost))
    print("timespan: " + mqr.timespan)
    print("granularity: " + str(mqr.granularity))
    print("namespace: " + mqr.namespace)
    print("resource_region: " + mqr.resource_region)
    # print("metrics: " + mqr.metrics)
    for metric in mqr.metrics:
        print(metric.name)
        for time_series_element in metric.timeseries:
            for metric_value in time_series_element.data:  # a (list[MetricValue])
                if metric_value.count != 0:
                    print("timestamp: " + str(metric_value.timestamp))
                    print("average: " + str(metric_value.average))


def get_lb_metrics(metrics_client: MetricsQueryClient, load_balancer_uri: str):

    # m_definitions = metrics_client.list_metric_definitions(load_balancer_uri)
    # for md in m_definitions:
    #     print("[" + md.namespace + "] " + md.name)

    # dimension: Microsoft.Network/loadBalancers, metric: DipAvailability. Average Load Balancer health status per time duration
    # dimension: Microsoft.Network/loadBalancers, metric: VipAvailability. Average Load Balancer data path availability per time duration

    mqr = metrics_client.query_resource(load_balancer_uri, ["DipAvailability"])
    print_metrics_query_result(mqr)


async def wait_for_vmss_health_status(
    compute_client: ComputeManagementClient,
    vmss_id: str,
    instances_should_be_healthy: bool = True,
):
    vmss_id_elements = vmss_id.split("/")
    vmss_resource_group_name = vmss_id_elements[4]
    vmss_name = vmss_id_elements[8]

    vm_instance_ids = _get_vmss_instance_ids(compute_client, vmss_resource_group_name, vmss_name)

    vm_instances_handled = [False for i in vm_instance_ids]
    do_while_loop = vm_instances_handled.count(True) != len(vm_instances_handled)

    while do_while_loop:
        for idx, vm_ii in enumerate(vm_instance_ids):
            vms = compute_client.virtual_machine_scale_set_vms
            vm_instance_view: VirtualMachineScaleSetVMInstanceView = vms.get_instance_view(
                vmss_resource_group_name, vmss_name, vm_ii
            )
            vm_status = vm_instance_view.vm_health.status
            if (instances_should_be_healthy and vm_status.code == "HealthState/healthy") or (
                not instances_should_be_healthy and vm_status.code == "HealthState/unhealthy"
            ):
                if not vm_instances_handled[idx]:
                    vm_instances_handled[idx] = True
                    print(
                        "Flipped positive status for instance '{}': code={}, level={}, display status={}, message='{}', time={}".format(
                            vm_ii,
                            vm_status.code,
                            vm_status.level,
                            vm_status.display_status,
                            vm_status.message,
                            str(vm_status.time),
                        )  # code=HealthState/unhealthy, level=Error, display status=The VM is reporting itself as unhealthy or is unreachable, message='None', time=2021-12-21 17:08:11+00:00
                        #   code=HealthState/healthy, level=Info, display status=The VM is reporting itself as healthy, message='None', time=2021-12-22 08:22:02+00:00
                    )
            else:
                if vm_instances_handled[idx]:
                    vm_instances_handled[idx] = False
                    print("Flipped negative status for instance '{}".format(vm_ii))
        do_while_loop = vm_instances_handled.count(True) != len(vm_instances_handled)
        if do_while_loop:
            await asyncio.sleep(5.0)


def update_vmss_with_bap(
    network_client: NetworkManagementClient,
    compute_client: ComputeManagementClient,
    bap_id: str,
    vmss_id: str,
    health_probe_id: Optional[str] = None,
):
    """
    Update a VMSS to be associated with a BAP. This assumes the VMSS has been created with one network interface that contains one IP configuration. This also assumes the Load Balancer has one BAP.
    """
    bap_id_elements = bap_id.split("/")
    bap_resource_group_name = bap_id_elements[4]
    load_balancer_name = bap_id_elements[8]
    bap_name = bap_id_elements[10]

    vmss_id_elements = vmss_id.split("/")
    vmss_resource_group_name = vmss_id_elements[4]
    vmss_name = vmss_id_elements[8]

    bap: BackendAddressPool = network_client.load_balancer_backend_address_pools.get(
        resource_group_name=bap_resource_group_name,
        load_balancer_name=load_balancer_name,
        backend_address_pool_name=bap_name,
    )
    vmss: VirtualMachineScaleSet = compute_client.virtual_machine_scale_sets.get(
        resource_group_name=vmss_resource_group_name, vm_scale_set_name=vmss_name
    )

    vmss.virtual_machine_profile.network_profile.network_interface_configurations[0].ip_configurations[
        0
    ].load_balancer_backend_address_pools = [bap]

    if health_probe_id is not None:
        vmss.virtual_machine_profile.network_profile.health_probe = ApiEntityReference(
            id=health_probe_id
        )  # '/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Network/loadBalancers/{loadBalancerName}/probes/{probeName}'.

    poller = compute_client.virtual_machine_scale_sets.begin_update(
        resource_group_name=vmss_resource_group_name, vm_scale_set_name=vmss_name, parameters=vmss
    )
    poller.wait()
    print(poller.status())


@click.group(invoke_without_command=True)
@click.pass_context
def cli(ctx):
    if ctx.invoked_subcommand is None:
        click.echo("Use sub command, see --help for help")


@cli.command()
@coro
@click.option("--vmss-id", help="ID of the VMSS that should be connected to the BAP", required=True)
@click.option(
    "--timeout",
    help="Maximum time in seconds, e.g., '5.0' to wait for all instances to have desired health status. Default is to not use timeout",
    required=False,
)
@click.option(
    "--desire-unhealthy-status",
    help="Desired health status should be unhealthy for the VMs. If not set then VMs should have healthy status",
    required=False,
)
async def query_lb(vmss_id, timeout, desire_unhealthy_status):
    cc = create_azure_session(memory["credentials"], memory["subscription_id"], "compute")
    if timeout is not None:
        task = asyncio.create_task(wait_for_vmss_health_status(cc, vmss_id, desire_unhealthy_status is None))
        try:
            r = await asyncio.wait_for(task, timeout=float(timeout))
        except asyncio.TimeoutError as ex:
            click.echo(
                "Failure in waiting for all instances to become {}".format(
                    "healthy" if desire_unhealthy_status else "unhealthy"
                )
            )
            raise ex
    else:
        await wait_for_vmss_health_status(cc, vmss_id, desire_unhealthy_status is None)


@cli.command()
@click.option("--bap-id", help="ID of the backend address pool to connect the VMSS to", required=True)
@click.option("--vmss-id", help="ID of the VMSS that should be connected to the BAP", required=True)
@click.option("--health-probe-id", help="ID of the health probe used to determine instance health", required=False)
def register_vmss(bap_id, vmss_id, health_probe_id):
    nc = create_azure_session(memory["credentials"], memory["subscription_id"], "network")
    cc = create_azure_session(memory["credentials"], memory["subscription_id"], "compute")
    update_vmss_with_bap(nc, cc, bap_id, vmss_id, health_probe_id)


@cli.command()
@click.option("--vmss-id", help="ID of the VMSS that should be allowed traffic", required=True)
def open_vmss(vmss_id):
    nc = create_azure_session(memory["credentials"], memory["subscription_id"], "network")
    cc = create_azure_session(memory["credentials"], memory["subscription_id"], "compute")
    manage_nsg_rule_lb_probe(cc, nc, vmss_id, "Allow")


@cli.command()
@click.option("--vmss-id", help="ID of the VMSS that should be disallowed traffic", required=True)
def close_vmss(vmss_id):
    nc = create_azure_session(memory["credentials"], memory["subscription_id"], "network")
    cc = create_azure_session(memory["credentials"], memory["subscription_id"], "compute")
    manage_nsg_rule_lb_probe(cc, nc, vmss_id, "Deny")


@cli.command()
@click.option("--vmss-id", help="ID of the VMSS that should be disallowed traffic", required=True)
def perform_upgrade(vmss_id):
    cc = create_azure_session(memory["credentials"], memory["subscription_id"], "compute")
    os_upgrade(cc, vmss_id)


@cli.command()
@click.option("--vmss-id", help="ID of the VMSS that should be connected to the BAP", required=True)
def deregister_vmss(vmss_id):
    cc = create_azure_session(memory["credentials"], memory["subscription_id"], "compute")
    disassociate_vmss_bap(cc, vmss_id)


if __name__ == "__main__":
    cli()
