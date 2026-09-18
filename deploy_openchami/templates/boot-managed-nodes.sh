#! /usr/bin/bash
# SPDX-FileCopyrightText: (C) Copyright 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Phase 8: boot-managed-nodes
#
# - On cluster systems, switch DNS to the coresmd-coredns server
# - Set up boot service configuration for the nodes
# - Set up cloud-init metadata for nodes
# - Boot managed nodes (host mode: create VMs; cluster mode: power cycle)
# - Try to SSH to the nodes as a sanity check
#
# Run as the deployment user; uses sudo for privileged operations.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/prep_setup.sh"
source "/etc/profile.d/build-image.sh"

IMAGE_BUILDERS=(
    {%- for file in manifest.files.values() %}
    {%- if "image-builder" in file.annotations %}
    "{{ manifest.deployment_directory }}/{{ file.target }}"
    {%- endif %}
    {%- endfor %}
)

WORK_DIRS=(
    "${DEPLOY_DIR}/boot"
    "${DEPLOY_DIR}/boot-metadata"
)

OCHAMI_PATH="$(command -v ochami)" || true
[ -n "${OCHAMI_PATH}" ] || { fail "'ochami' not installed"; exit 1; }


function configure_cloud_init_metadata() {
    {%- if openchami_config.metadata_service == "metadata-service" %}
    base_url="http://${MANAGEMENT_HEADNODE_IP}:8081/metadata-service"
    {%- elif openchami_config.metadata_service == "cloud-init" %}
    base_url="http://${MANAGEMENT_HEADNODE_IP}:8081/cloud-init"
    {%- else %}
    info "boot-managed-nodes: no recognized metadata service configured, skipping metadata setup"
    return
    {%- endif %}
    if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
        ssh-keygen -t rsa -q -f ~/.ssh/id_rsa -N ""
    fi
    sudo mkdir -p "${DEPLOY_DIR}/boot-metadata"
    cat <<EOF | sudo tee "${DEPLOY_DIR}/boot-metadata/md-defaults.yaml" > /dev/null
---
base_url: "${base_url}"
cluster_name: "${CLUSTER_NAME}"
nid_length: 3
public_keys:
  - "$(cat ~/.ssh/id_rsa.pub)"
short_name: "nid-"
EOF

    {%- if openchami_config.metadata_service == "metadata-service" %}
    ochami metadata defaults add \
           -d "$(yaml_to_json < "${DEPLOY_DIR}/boot-metadata/md-defaults.yaml")"
    {%- else %}
    ochami cloud-init defaults set -f yaml \
           -d @"${DEPLOY_DIR}/boot-metadata/ci-defaults.yaml"
    {%- endif %}

    for group in $(node_groups); do
        cat <<EOF | sudo tee "${DEPLOY_DIR}/boot-metadata/md-group-${group}.yaml" > /dev/null
- name: "${group}"
  description: "${group} nodes"
  template: |
    ## template: jinja
    #cloud-config
    merge_how:
    - name: list
      settings: [append]
    - name: dict
      settings: [no_replace, recurse_list]
    users:
{%- if openchami_config.cloud_init_templating_disabled %}
    - name: testuser
      ssh_authorized_keys:
      - "$(cat ~/.ssh/id_rsa.pub)"
    - name: root
      ssh_authorized_keys:
      - "$(cat ~/.ssh/id_rsa.pub)"
{%- else %}
      - name: testuser
        ssh_authorized_keys: {{ "{{ ds.meta_data.instance_data.v1.public_keys }}" }}
      - name: root
        ssh_authorized_keys: {{ "{{ ds.meta_data.instance_data.v1.public_keys }}" }}
{%- endif %}
    disable_root: false
EOF
    {%- if openchami_config.metadata_service == "metadata-service" %}
    ochami metadata group add \
           -d "$(yaml_to_json < "${DEPLOY_DIR}/boot-metadata/md-group-${group}.yaml")"
    {%- else %}
    ochami cloud-init group set -f yaml \
           -d @"${DEPLOY_DIR}/boot-metadata/ci-group-${group}.yaml"
    {%- endif %}
done
    {%- for node in nodes %}
    {%- if openchami_config.metadata_service == "metadata-service" %}
    ochami metadata instance add \
           -d '{"instance_id": "{{ node.name }}", "local_hostname": "{{ node.hostname }}" }'
    {%- else %}
    ochami cloud-init node set \
           -d '[{"id":"{{ node.name }}","local-hostname":"{{ node.hostname }}"}]'
    {%- endif %}
    {% endfor %}
}

function wait_for_host_script() {
    # Try to retrieve the boot script for the specified host. We do this
    # by asking the boot service (BSS or boot-service) for the boot script
    # using Curl. To be permitted to do this we need to use the
    # "X-FORWARDED-FOR: <IP>" header with Curl to masquerade as the node
    # we are checking on. If it works, we are good to go, if not we sleep
    # 5 seconds and retry. Time out after 15 minutes (or the optionally
    # provided number of attempts) and fail.
    local host_id="${1}"; shift || { fail "no target host id provided"; die; }
    local host_ip="${1}"; shift || { fail "no target host ip provided"; die; }
    local attempts="${1:-180}"
    
    for ((i = 0; i < attempts; i++)); do
        # Learn the URI that coresmd-coredns is going to hand out for
        # obtaining the boot script and use that here.  This ensures
        # we are using the same URI that coresmd-coredns is using, so
        # it should match what the boot sequence sees.
        boot_uri="$( \
          yaml_to_json < /etc/openchami/configs/coredhcp.yaml | \
          jq -r '.server4.plugins | .[] | select(has("coresmd")).coresmd' | \
          grep 'ipxe_uri=' | \
          sed -e 's/^[^=]*= *//' \
        )"
        if curl -s "${boot_uri}?host=${host_id}" \
                -H "X-FORWARDED-FOR: ${host_ip}" \
                -o /dev/null; then
            info "waited $((i * 5)) seconds for '${host_id}' boot script"
            return 0
        fi
        sleep 5
    done
    # We timed out waiting for the script to be ready...
    fail "timed out waiting for '${host_id}' boot script to be ready"
    return 1
}

function ssh_to_compute_node() {
    local hostname="${1}"; shift || { fail "no hostname specified"; die; }
    local user="${1}"; shift || { fail "no deployment username provided"; die; }
    local cmd="${1}"; shift || cmd="true"
    local retries="${1}"; shift || retries=60
    local check="-o StrictHostKeyChecking=no"
    local file="-o UserKnownHostsFile=/dev/null"
    local time="-o ConnectTimeout=10"
    local where="root@${hostname}"
    info "attempting SSH to ${hostname} as ${user}"
    for ((retry=0; retry < retries; ++retry)); do
        if sudo su - "${user}" -c \
                "ssh ${check} ${file} ${time} ${where} '${cmd}'"; then
            info "SSH to ${hostname} succeeded"
            return 0
        fi
        (( retry < retries-1 )) && sleep 10
    done
    info "failed to SSH to ${hostname} after ${retries} attempts"
    return 1
}

# Reset a compute node either using RedFish on a BMC, if we are
# deploying in 'cluster' mode, or using 'virsh destroy' and 'virsh
# start' if we are deploying in host mode.
function restart_compute_node() {
    local node_name="${1}"; shift || { fail "no node given for reset"; die; }
    local bmc_name="${1}"; shift || { fail "no BMC given for reset"; die; } 
{%- if deployment_mode == 'cluster' %}
    info "boot-managed-nodes: power-cycling '${node_name}[BMC=${bmc_name}]'"
    power-off-node "${node_name}" "${bmc_name}" || true
    power-on-node "${node_name}" "${bmc_name}"
{%- else %}
    info "boot-managed-nodes: restarting VM '${node_name}'"
    sudo virsh destroy "${node_name}" || true
    sudo virsh start "${node_name}"
{%- endif %}
}

# (Re-)create a host mode compute node (VM on the management node) if
# we are deploying in 'host' mode. Restart the node (which already exists
# outside of the deployment process) if we are deploying in cluster mode.
function create_compute_node() {
    local node_name="${1}"; shift || { fail "no node given for reset"; die; }
    local bmc_name="${1}"; shift || { fail "no BMC given for reset"; die; } 
    local interfaces=("$@")

{%- if deployment_mode == 'host' %}
    info "boot-managed-nodes: launching VM '${node_name}'"
    if sudo virsh list --all | grep -q "${node_name}"; then
        info "boot-managed-nodes: detroying existing VM '${node_name}'"
        sudo virsh destroy "${node_name}" || true
        info "boot-managed-nodes: undefining existing VM '${node_name}'"
        sudo virsh undefine "${node_name}" --nvram || \
            info "could not undefine '${node_name}'"
    fi
    if [ "$(derive_architecture)" == 'amd64' ]; then
        UEFI="loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS.fd,loader_secure=no"
    else
        UEFI="uefi"
    fi
    local network_opts=""
    for interface in "${interfaces[@]}"; do
        network_opts="${network_opts} --network ${interface}"
    done
    # Notice that '$network_opts' is not quoted here. That is
    # intentional because we are expanding multiple '--network'
    # options and their arguments. If '$network_opts' were quoted, it
    # would expand as one big string and fail the command usage.
    #
    # shellcheck disable=SC2046
    sudo virt-install \
         --name "${node_name}" \
         --memory 4096 \
         --vcpus 1 \
         --disk none \
         --pxe \
         --os-variant centos-stream9 \
         ${network_opts} \
         --graphics none \
         --console pty,target_type=serial \
         --boot network,hd \
         --boot "${UEFI}" \
         --virt-type kvm \
         --noautoconsole
{%- else %}
    restart_compute_node "${node_name}" "${bmc_name}"
{%- endif %}
}

# ── Get OCHAMI Token ─────────────────────────────────────────────
info "boot-managed-nodes: waiting for an ochami access token"
for ((i = 0; i < 10; i++ )); do
    get-ochami-token || DEMO_ACCESS_TOKEN=""
    [ -n "${DEMO_ACCESS_TOKEN}" ] && break
    sleep 10
done
[ -n "${DEMO_ACCESS_TOKEN}" ] || \
    { fail "cannot obtain ochami access token"; exit 1; }

# ── Create work directories ───────────────────────────────────────────
for dir in "${WORK_DIRS[@]}"; do
    info "boot-managed-nodes: preparing work directory ${dir}"
    [ -d "${dir}" ] && sudo rm -rf "${dir}"
    sudo mkdir -p "${dir}"
done

{%- if deployment_mode == 'cluster' %}
# ── Switch DNS to coresmd-coredns (cluster mode only) ─────────────────
info "boot-managed-nodes: verifying coresmd-coredns is active"
systemctl is-active --quiet coresmd-coredns.service || \
    { fail "coresmd-coredns is not active -- investigate and retry"; exit 1; }
info "boot-managed-nodes: switching DNS to cluster internal nameserver"
switch_dns "${MANAGEMENT_HEADNODE_IP}" "${CLUSTER_DOMAIN}"
{%- endif %}

# ── Generate boot configuration ───────────────────────────────────────
info "boot-managed-nodes: generating boot configuration"
cd "${DEPLOY_DIR}/boot" || {
    fail "failed to enter the boot scripts directory"
    exit 1
}
for builder in "${IMAGE_BUILDERS[@]}"; do
    BOOT_CONFIG_FILE="${DEPLOY_DIR}/boot/$(basename "${builder}" .yaml).json"
    S3_PREFIX="$(yaml_to_json < "${builder}" | \
        jq -r '.options.s3_prefix' | sed -e 's:/[[:blank:]]*$::')"
    [[ "${S3_PREFIX}" != "null" ]] || continue
    # Notice that '$(managed_macs)' is not quoted here. That is
    # because we are expanding a list of MAC addresses, and want each
    # one to be a separate argument.
    #
    # shellcheck disable=SC2046
    generate-boot-config-json \
        "${S3_PREFIX}" \
        "${MANAGEMENT_HEADNODE_IP}" \
        $(managed_macs) | \
        sudo tee "${BOOT_CONFIG_FILE}" > /dev/null
done

# ── Install boot configuration ────────────────────────────────────────
ACTIVE_BOOT_CONFIG="$(basename \
    "{{ images.builders[images.deployment_targets['compute']].metadata.boot_param_filename }}" \
    .yaml).json"

info "boot-managed-nodes: installing boot configuration '${ACTIVE_BOOT_CONFIG}'"
{%- if openchami_config.use_boot_service %}
sudo "${OCHAMI_PATH}" config --system cluster set demo cluster.boot-service.uri /boot-service
ochami boot config add -d @"${DEPLOY_DIR}/boot/${ACTIVE_BOOT_CONFIG}"
{%- else %}
ochami bss boot params set -d @"${DEPLOY_DIR}/boot/${ACTIVE_BOOT_CONFIG}"
{%- endif %}

# ── Set up cloud-init metadata ────────────────────────────────────────
info "boot-managed-nodes: configuring cloud-init metadata"
configure_cloud_init_metadata

{%- if deployment_mode == 'cluster' %}

# ── Clear Residual Managed Node cloud-init state ──────────────────────
#
# In cluster mode, if we are returning to a cluster that has already
# been deployed and has existing nodes in it, the managed nodes will
# have undesired residual configured state on them from when
# cloud-init was most recently run. So, if there are reachable managed
# nodes, clear away the cloud-init state on each one.
{%- for node in nodes %}
# Check reachability and clear cloud-init as needed
host="$(printf "nid-%3.3d" {{ node.nid }})"
# Wait for DNS to catch up if needed
retries=10
info "boot-managed-nodes: waiting for '${host}' to show up in DNS"
while ! host "${host}" | grep -q "has address"; do
    [[ "$((retries--))" -gt 0 ]] || {
        fail "timed out waiting for '${host}' in DNS"
        exit 1
    }
    sleep 10
done
if ssh_to_compute_node "${host}" "${DEPLOY_USER}" "true" "1"; then
    info "clearing cloud-init on '${host}' to prepare for fresh boot"
    ssh_to_compute_node "${host}" "${DEPLOY_USER}" \
                        "cloud-init clean --logs" "1"
fi
{% endfor %}
{%- endif %}

# ── Create managed nodes as needed ─────────────────────────────────────
#
# This could be done in-line with booting the nodes, which would
# simplify the retry logic in the case where a boot fails the first
# time. By doing it here, though, we give the nodes, especially when
# there is more than one node in the cluster) more parallel time to
# boot meaning the check for whether they booted runs faster in the
# non-retry case.
{%- for node in nodes %}
# Collect the network interface information for the node
interfaces=(
{%- for iface in node.interfaces %}
    "network={{ iface.network_name }},model=virtio,mac={{ iface.mac_addr }}"
{%- endfor %}
)
create_compute_node "{{ node.name }}" "{{ node.bmc_name }}" "${interfaces[@]}"
{%- endfor %}


# ── Boot managed nodes and verify SSH connectivity ─────────────────────
{%- for node in nodes %}
  {#
   the following loop is intended to find the first IP address on the cluster
   network. It should produce only one wait_for_host_script /
   ssh_to_compute_node pair per node.
  #}
  {%- for interface in node.interfaces %}
    {%- if interface.network_name == node.cluster_net_interface %}
wait_for_host_script "{{ node.name }}" "{{ interface.ip_addrs[0].ip_addr }}"
ssh_to_compute_node "$(printf "nid-%3.3d" {{ node.nid }})" "${DEPLOY_USER}"
    {%- endif %}
  {%- endfor %}
{%- endfor %}
