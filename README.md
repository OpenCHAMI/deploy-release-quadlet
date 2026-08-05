# OpenCHAMI Quadlet Based Deployment Tool

The OpenCHAMI Quadlet Based Deployment Tool consists of a Python
wrapper and a base configuration designed to deploy OpenCHAMI onto a
host node using the quadlet implementation of OpenCHAMI described in
the [OpenCHAMI Tutorial](https://openchami.org/docs/tutorial/) using a
"`host` mode" configuration that creates and boots a single virtual
managed (compute) node co-resident on the OpenCHAMI headnode host. The
deployment tool can be used either to deploy OpenCHAMI and the virtual
managed node on physical hardware or on a virtual machine, as long as
the virtual machine supports nested virtualization and has sufficient
resources to run both the OpenCHAMI headnode software and the virtual
managed node.

The deployment tool can also run in a "`cluster` mode" in which the
OpenCHAMI head node and all managed nodes are connected to a physical
or virtual network cluster where the managed nodes are not co-resident
on the host node. In this case, the assumption is that the managed
nodes can be powered on, powered off, and reset using RedFish calls to
RedFish instances running on Base Board Management Controllers (BMCs)
accesible across a network from the headnode.

## System Requirements

At present, the deployment tool uses the 'dnf' package manager, which
is an RPM based package manager primarily used on RedHat systems. The
deployment tool expects to run on a Rocky Linux or similar
distribution of Linux.

The deployment tool can currently successfully deploy OpenCHAMI and
bring up virtual compute nodes on x86-64 (amd64) and AMD-64 (aarch64)
hosts. The default configuration assumes x86-64. This README provides
an example configuration overlay to enable AMD-64 operation, as well
as a broader description of configuration overlays.

For `host` mode operation, the deployment tool recommends a minimum of
4GB of memory, 4 CPU cores and 40GB of free disk space on the
headnode. If the headnode is a VM it must support nested
virtualization for the deployment tool to work in `host` mode. On
MacOS, currently, nested virtualization is only supported by VMs
running on an M3 or better system under Apple Virtualization not those
running under KVM.

The deployment tool requires a minimum version 3.9 of Python installed
on the headnode.

The user running the deployment tool must either be `root` or have
`sudo` access on the headnode.

## Installing and Running the Deployment Tool

The deployment tool works best when it is installed in a Python
virtual environment on the host you plan to use as a head node. To
create a virtual environment named `venv` in your home directory, make
sure you have at least Python 3.9 installed and run:

```shell
python3 -m venv ~/venv
```

Once you have created the virtual environment (for example `~/venv`)
activate it as follows:

```
source ~/venv/bin/activate
```

To install the deployment tool use `git` to clone this repository (
[https://github.com/hpe-erl/deploy-openchami-quadlet](https://github.com/hpe-erl/deploy-openchami-quadlet)
) and check out the version of the deployment tool you want. The
version of the deployment tool you need depends on the version of
OpenCHAMI you are deploying.

Once you have the correct version checked out, enter the root directory of the cloned repository and use

```shell
pip install .
```

to install it in your virtual environment.

Since you installed `deploy_openchami` in your own virtual environment
and not in a location that is globally known by all users, it is
necessary to invoke it by its full pathname when running it with
`sudo` as you will do in the next section. You will see the following
showing how that is done (modify it according to where you placed your
virtual environment):

```shell
sudo ~/venv/bin/deploy_openchami ...
```

Now you are ready to use the deployment tool. This is done in two
stages. The first stage needs to be run when you first start on a
brand-new headnode or if you change the version of OpenCHAMI or
`ochami` you want to test. This stage installs packages needed by the
installation process, creates a non-root administrative user (by
default `rocky`), installs the configured version of [OpenCHAMI
Release](https://github.com/openchami/release) and installs the
configured version of [ochami](https://github.com/openchami/ochami).
The second stage needs to be run each time you want to (re-)deploy
OpenCHAMI on your headnode.

Before starting, you should determine what version of OpenCHAMI
release you want to deploy and place, at least that, into a
configuration file in the directory where you plant to run your
deployment. Here is a sample configuration that will deploy OpenCHAMI
Release version `v0.1.6`:

```
openchami_config:
  release:
    version: v0.1.6
```

For the following examples, that is the content of the file
`config.yaml`.

1. Use the deployment tool to prepare the headnode for OpenCHAMI
deployment:

```shell
sudo ~/venv/bin/deploy_openchami -p config.yaml
```

2. Use the deployment tool to deploy OpenCHAMI and start a virtual
compute node:

```shell
sudo ~/venv/bin/deploy_openchami config.yaml
```

__NOTE: If your are running on an arm64 (aarch64) host, you will need
to change the repository URLs in the default image builder
configuration. See the 'Configuration' section below to learn how to
do this using a configuration overlay.__

Assuming this completes successfully, you should be able to become the
deployment user (by default this is `rocky`) and SSH to your virtual
compute node:

```shell
sudo su - rocky
ssh root@compute-001
```

## Configuration

The deployment tool contains a rich configuration that allows for both
future changes to OpenCHAMI and changes to the way OpenCHAMI is
deployed on your headnode. This configuration, in turn drives the
creation of configuration files and scripts used internally to deploy
OpenCHAMI. The base configuration drives a deployment quite similar
to the OpenCHAMI tutorial with virtual managed (compute) nodes. This
base configuration can be modified at run time by providing the paths
to one or more YAML format configuration overlays on the command line.

### Example Configuration Overlay for ARM-64 Hosts

For example, to change the repository URLs in the image builders so you
can deploy this on an `arm64` (`aarch64`) host, all that is required is a
configuration overlay that overrides those URLs. Something like this:

```yaml
images:
  builders:
    rocky-base-9:
      data:
        repos:
        # Note: since 'repos' is a list, all of the elements need to be
        #       specified fully as the new list will completely replace
        #       the list in the default configuration.
        - alias: 'Rocky_9_BaseOS'
          # Change the 'url' field from x86_64 (in the default config) to
          # 'aarch64' in your config to pull packages of the correct
          # machine architecture.
          url: 'https://dl.rockylinux.org/pub/rocky/9/BaseOS/aarch64/os/'
          gpg: 'https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9'
        - alias: 'Rocky_9_AppStream'
          # Change the 'url' field from x86_64 (in the default config) to
          # 'aarch64' in your config to pull packages of the correct
          # machine architecture.
          url: 'https://dl.rockylinux.org/pub/rocky/9/AppStream/aarch64/os/'
          gpg: 'https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9'
    compute-base-rocky9:
      data:
        # Note: since 'repos' is a list, all of the elements need to be
        #       specified fully as the new list will completely replace
        #       the list in the default configuration
        repos:
        - alias: 'Epel9'
          # Change the 'url' field from x86_64 (in the default config) to
          # 'aarch64' in your config to pull packages of the correct
          # machine architecture.
          url: 'https://dl.fedoraproject.org/pub/epel/9/Everything/aarch64/'
          gpg: 'https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9'
```

A maintained version of the above configuration overlay is provided in
[docs/example-overlays/config-aarch64.yaml](docs/example-overlays/config-aarch64.yaml).

### Example Overlay for Cluster Mode OpenCHAMI Deployment

The following is an example configuration overlay for deploying
OpenCHAMI on a cluster with a head node and four compute nodes all
residing on a cluster network 10.2.1.0/24 with an external DNS server
at 10.234.0.1 and a single BMC managing the four nodes and residing on
a hardware management network 10.3.1.0/24 at 10.3.1.1. The MAC
addresses have been collected from the BMCs and compute nodes.

__NOTE: set the RedFish password in here to match the setting on the BMC__

```
# Set the deployment mode to 'cluster' instead of 'host' so that no
# VM will be created on the head node and the cluster will be set up
# to use coresmd-coredns for DNS.
deployment_mode: cluster
bmcs:
  # An X-Name is used here because it shows the relationship between 
  x2000c0s0b0:
    blade_class: host-blade
    blade_instance: 0
    network:
      redfish_username: root
      # NOTE: the redfish password is not shown here, but it should be
      #       configured to match whatever is configured for RedFish
      #       on the BMC.
      redfish_password: null
      mac: 52:54:00:b2:2e:f4  # Get this from the BMC
      # The BMC is on a Hardware Management Network (1.3.1.1/24)
      ipv4: 10.3.1.1
hosting_config:
  cluster_name: demo
  cluster_net_dhcp_start: 10.2.1.32
  cluster_net_dhcp_end: 10.2.1.254
  cluster_net_mask: 255.255.255.0
  net_head_dns_server: 10.234.0.1
  net_head_domain: openchami.cluster
  net_head_hostname: demo
  net_head_ip: 10.2.1.2
nodes:
- name: x2000c0s0b0n0
  bmc_name: x2000c0s0b0
  cluster_net_interface: compnet
  hostname: compute-001
  nid: 1
  node_group: compute
  interfaces:
  - network_name: compnet
    # Get this from the node's NIC on the cluster network
    mac_addr: 52:54:00:3d:71:7b
    ip_addrs:
    - name: compnet
      ip_addr: 10.2.1.32
- name: x2000c0s0b0n1
  bmc_name: x2000c0s0b0
  cluster_net_interface: compnet
  hostname: compute-002
  nid: 2
  node_group: compute
  interfaces:
  - network_name: compnet
    # Get this from the node's NIC on the cluster network
    mac_addr: 52:54:00:6a:d2:33
    ip_addrs:
    - name: compnet
      ip_addr: 10.2.1.33
- name: x2000c0s0b0n2
  bmc_name: x2000c0s0b0
  cluster_net_interface: compnet
  hostname: compute-003
  nid: 3
  node_group: compute
  interfaces:
  - network_name: compnet
    # Get this from the node's NIC on the cluster network
    mac_addr: 52:54:00:3b:aa:78
    ip_addrs:
    - name: compnet
      ip_addr: 10.2.1.34
- name: x2000c0s0b0n3
  bmc_name: x2000c0s0b0
  cluster_net_interface: compnet
  hostname: compute-004
  nid: 4
  node_group: compute
  interfaces:
  - network_name: compnet
    # Get this from the node's NIC on the cluster network
    mac_addr: 52:54:00:06:48:e8
    ip_addrs:
    - name: compnet
      ip_addr: 10.2.1.35
```

A maintained version of the above configuration overlay is provided in
[docs/example-overlays/config-cluster-mode.yaml](docs/example-overlays/config-cluster-mode.yaml).

### Configuring the Tool to Skip Specific Deployment Phases

The Deployment Tool runs in 8 distinct phases, through two sequential
commands:

- `deploy_openchami -p ...`
- `deploy_openchami ...`

The `deploy_openchami -p ...` command runs the `setup_node` phase, if
it is enabled. The `deploy_openchami ...` command runs the remaining
enabled phases.

Here is a description of each phase.

#### Setup Node

The `setup_node` phase prepares the host node for the deployment of
OpenCHAMI. It does the following:

- Reset DNS to original settings (in case they have been changed by a
  previous run of `deploy_openchami`)
- Install required packages
- Create the deployment user (check first, create if absent)
- Add deployment user to sudoers with NOPASSWD (check first)
- Copy deployment user's s3cfg file to user's directory
- Turn on IP forwarding
- Set up the virtual environment for 'host' mode if applicable

These actions are quite idempotent, and it is generally a good idea to
let them run whenever the `-p` option is used, so disabling this phase
is discouraged.

#### Setup S3 and Registry

The `setup_s3_and_registry` phase sets up a management node hosted S3
server and OCI registry that your OpenCHAMI installation can use if
you do not have site provided instances of these. You can skip this
phase if you have configured your deployment to use existing services
or if you have already deployed OpenCHAMI using the deployment tool
and want to re-use the artifacts stored in the management node hosted
services.

#### Prepare OpenCHAMI

The `prepare_openchami` phase does the following:

- Remove any existing 'ochami' package installation
- Install 'ochami' (download RPM or build from source)
- Remove any existing 'openchami' package installation
- Remove any existing 'openchami-release' git repo
- Set up new OpenCHAMI Release repo, check out specified version, build RPM

If you are developing code in either OpenCHAMI Release or `ochami` you
probably want to run this phase every time. If you are developing code
for an OpenCHAMI service and want to modify the local OpenCHAMI
Release to pick up your changes, you probably want to skip this phase
so you can edit and manually rebuild the already cloned instance of
OpenCHAMI Release which can be found in your deployment directory (by
default, `/opt/workdir/openchami_release`) after the first fully
enabled run of the tool.

#### Install OpenCHAMI

The `install_openchami` phase does the following:

- Merge the openchami.env configuration file
  (/etc/openchami/configs/openchami.env) from configured settings -
  Install the OpenCHAMI Release RPM built by prepare-openchami or by
  hand by you

This is generally a big part of using the Deployment Tool, so it is
unlikely you want to disable this step unless you are working on one
of the earlier or later phases and are either happy with the existing
OpenCHAMI installation or want to hold off on installation.

#### Start OpenCHAMI

The `start_openchami` phase does the following:

- Shut down any currently running instance of openchami.target
- Set up OpenCHAMI system files needed for this run
- Start openchami.target
- Configure the ochami CLI client
- Wait for SMD to start

Again, this is usually what you are using the deployment tool
for. Unless you are debugging the earlier phases you probably want to
let this phase run.

#### Configure Cluster

The `configure_cluster` phase runs static discovery using a generated
`nodes.yaml` file. If you started OpenCHAMI after re-installing it,
you will need this phase to run as well for later phases to work. If
you are using an already installed, started and discovered OpenCHAMI,
skip this phase to avoid conflicts.

NOTE: there is currently a bug in SMD that causes a spurious report of a
      failure in static discovery. This error is currently being ignored
      when it occurs.

#### Build Images

The `build_images` phase builds the configured set of node images and
stores them in the registry and in S3 for use in booting managed
nodes. This is by far the most time consuming part of deploying
OpenCHAMI using the tool, so it is useful to disable it and the
`setup_s3_and_registry` phase if you have externally provided S3 and
Registry services or if you have previously built images and stored
them in the managment node hosted services.

#### Boot Managed Nodes

The `boot_managed_nodes` phase does the following:

- On cluster systems, switch DNS to the coresmd-coredns server
- Set up boot service configuration for the nodes
- Set up cloud-init metadata for nodes
- Boot managed nodes (host mode: create VMs; cluster mode: power cycle)
- Try to SSH to the nodes as a sanity check

This phase proves that your deployment is working. Skip it if you just want to deploy onto a system and then begin provisioning and booting nodes yourself.

#### Configuring the Desired Phases

To configure the phases, write an overlay file that specifies which
phases you would like to disable (all phases are enabled by
default). To disable a phase change its setting in the
`openchami_config.deployment_phases` configuration to `false`. The
following illustrates a specific configuration overlay that is useful
for skipping the `setup_s3_and_registry` phase and the `build_images`
phases:

```
openchami_config:
  deployment_phases:
    setup_node: true
    setup_s3_and_registry: false
    prepare_openchami: true
    install_openchami: true
    start_openchami: true
    configure_cluster: true
    build_images: false
    boot_managed_nodes: true
```

### Configuring The Tool to Deploy Older Release Versions

This repository provides a set of configuration overlay example
configurations intended to preserve the behavior needed to deploy older
versions of OpenCHAMI Release. The most recent version of the tool
will be configured to deploy the most recent OpenCHAMI release, but
that configuration can be overlayed by using the appropriate overlay
from `docs/example-overlays`. For example, to set the tool up to
deploy OpenCHAMI Release v0.1.4 through v0.1.6, copy
`docs/example-overlays/config-0.1.4` to your current directory and
run

```
sudo ~/venv/bin/deploy_openchami config-0.1.4.yaml config.yaml
```

where `config.yaml` is your personal configuration overlay file (if
any) and `config-0.1.4.yaml` is the overlay for OpenCHAMI Release
versions v0.1.4 through v0.1.6.

### Working with the Deployment Tool Configuration

When creating a configuration overlay, it helps to know what the
configuration to be overlaid looks like, and what the configuration
looks like after applying the overlay. There are two options to the
deployment tool that allow you to see the contents of the deployment
tool configuration. The first option dumps out the entire contents of
the base configuration file, complete with comments explaining the
pieces. This is a good place to start:

```shell
~/venv/bin/deploy_openchami -b
```

From there you can cut and paste the necessary pieces to create new
configuration overlays.

The second option dumps out the final configuration after applying
your configuration overlay(s):

```shell
~/venv/bin/deploy_openchami -c amd64_config_overlay.yaml
```

This configuration may be in a different order from the base
configuration and is not commented, but it allows you to verify that
your configuration changes were applied the way you want them.

To validate your deployment tool final configuration, use:

```shell
~/venv/bin/deploy_openchami -v amd64_config_overlay.yaml
```

This helps ensure that your configuration is correct and
consistent, and, where possible, required system elements are in place
to support the configuration you have created.

Deploy your newly configured OpenCHAMI system by first preparing the
host node using:

```shell
sudo ~/venv/bin/deploy_openchami -p amd64_config_overlay.yaml
```

then deploying the new configuration using:

```shell
sudo ~/venv/bin/deploy_openchami amd64_config_overlay.yaml
```

If all went well, you should have OpenCHAMI running on a 64 bit AMD host
with a co-located VM serving as compute node.

```shell
sudo su - rocky
ssh root@compute-001
```

The deployment tool has been designed to be able to be run correctly
multiple times on the same host with new configurations, so, if you
tried deploying on an AMD system before reading this part, you should
be able to simply re-run with the new configuration overlay.

This mechanism also allows you to change many other aspects of how your
OpenCHAMI system is deployed. The AMD overlay was simply a convenient
way to demonstrate the mechanism and enable AMD deployments.

## Limitations

The deployment tool currently has the following limitations. Except
where otherwise noted, solutions to these are being investigated and
implemented:

- there is no 'remove' operation in the deployment tool
- while the deployment tool tries to be re-runable, it is not
  perfectly idempotent, so situations may arise where re-running the
  deployment tool fails leaving the host in an inconsitent state. There
  are currently no known instances of this, but with arbitrary
  configuration overlays, not every case can be tested.
- The OpenCHAMI target itself may not be restartable. While the deployment
  tool tries to clear as much residual state as it can, if OpenCHAMI
  won't re-start, then the tool will not re-run. Usually stopping and
  removing OpenCHAMI, then rebooting the headnode and re-deploying
  OpenCHAMI will clear these problems.
- along similar lines, the deployment tool is not protected against
  being interrupted (for example CTRL-C) in the middle of a sensitive
  operation that may leave the system in an inconsistent state -- it is
  safest not to interrupt a running instance.
- the minimum configuration of the headnode can host up to two virtual
  managed nodes. To host more than that, use a host with more CPU,
  Memory and Disk resources.
- issues have been seen with the `openchami-external` podman network
  disappearing after several runs of the deployment tool. This appears to be
  intractable without a reboot, but a reboot of the host node will clear
  it.
- issues have been seen with the digests of boot images not matcing (some
  kind of corruption of the boot image either in or on the way to the
  registry). We are currently stopping the registry, removing both the
  disk resident registry storage and the podman volume and then restarting
  what should be a fresh registry to alleviate this. It does not always
  work. Rebooting the host node seems to clear this problem.
