#! /usr/bin/bash
# SPDX-FileCopyrightText: (C) Copyright 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Phase 2: setup-s3-and-registry
#
# - Remove S3 volumes and shut down minio.service
# - Remove registry volumes and shut down registry.service
# - Reload systemd
# - Install the versity S3 server
# - Start registry.service
# - Install and configure regctl
# - Configure the S3 client
# - Create S3 buckets
#
# Run as the deployment user; uses sudo for privileged operations.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/prep_setup.sh"

ROCKY_DIRS=(
    "/data/oci"
)

S3_PUBLIC_BUCKETS=(
    "efi"
    "boot-images"
)

function cleanup_service() {
    local service="${1}"; shift || { fail "no service specified"; die; }
    local dir="${1}"; shift || dir=""
    info "cleaning up service '${service}'"
    if sudo systemctl status --no-pager --full "${service}" > /dev/null 2>&1; then
        sudo systemctl stop "${service}"
    fi
    if [ -n "${dir}" ] && [ -d "${dir}" ]; then
        info "removing volume directory '${dir}'"
        sudo rm -rf "${dir}"
        sudo podman system prune -a -f --volumes
    fi
}

# ── Remove S3 and registry volumes and stop services ──────────────────
info "setup-s3-and-registry: stopping versitygw.service and removing /data/s3"
cleanup_service versitygw.service /var/lib/versitygw

info "setup-s3-and-registry: removing versitygw-quadlet package"
sudo dnf -y remove versitygw-quadlet || :

info "setup-s3-and-registry: installing versitygw S3 service as quadlet"
# Get latest release RPM URL
VERSITY_RELEASE=latest
VERSITY_RELS=https://api.github.com/repos/openchami/versitygw-quadlet/releases
VERSITY_REL=/latest
latest_versity_url=$(curl -s "${VERSITY_RELS}/${VERSITY_RELEASE}" | \
        jq -r '.assets[] | select(.name | endswith("'"$(rpm --eval '%dist')"'.noarch.rpm")) | .browser_download_url')
# Download RPM
curl -L "${latest_versity_url}" -o versitygw.rpm
# Install the RPM
sudo dnf install -y ./versitygw.rpm

info "setup-s3-and-registry: stopping registry.service and removing /data/oci"
cleanup_service registry.service /data/oci

# ── Recreate backing directories ──────────────────────────────────────
for dir in "${ROCKY_DIRS[@]}"; do
    info "setup-s3-and-registry: creating directory ${dir}"
    sudo mkdir -p "${dir}"
    sudo chown -R "${DEPLOY_USER}:" "${dir}"
done

# ── Reload systemd and start services ─────────────────────────────────
info "setup-s3-and-registry: reloading systemd"
sudo systemctl daemon-reload
info "setup-s3-and-registry: starting registry.service"
sudo systemctl start registry.service
info "setup-s3-and-registry: enabling versitygw.service"
sudo systemctl enable --now versitygw-gensecrets.service
info "setup-s3-and-registry: starting versitygw.service"
sudo systemctl start versitygw.service
info "setup-s3-and-registry: bootstrapping S3 users and buckets"
sudo systemctl enable --now versitygw-bootstrap.service

# ── Install and configure regctl ──────────────────────────────────────
info "setup-s3-and-registry: installing and configuring regctl"
ARCH="$(derive_architecture)"
curl -fsSL \
    "https://github.com/regclient/regclient/releases/latest/download/regctl-linux-${ARCH}" \
    -o regctl
sudo mv regctl /usr/local/bin/regctl
sudo chmod 755 /usr/local/bin/regctl
/usr/local/bin/regctl registry set --tls disabled \
    "${MANAGEMENT_HEADNODE_FQDN}:${REGISTRY_API_PORT}"

# ── Configure S3 client and create buckets ────────────────────────────
info "setup-s3-and-registry: getting S3 Keys and Region"
source <(sudo cat /etc/versitygw/secrets.env)
cat << EOF > "${HOME}/.s3cfg"
# Setup endpoint
host_base = {{ hosting_config.net_head_hostname }}.{{ hosting_config.net_head_domain }}:{{ openchami_config.s3.api_port }}
host_bucket = {{ hosting_config.net_head_hostname }}.{{ hosting_config.net_head_domain }}:{{ openchami_config.s3.api_port }}
bucket_location = "${VGW_REGION}"
use_https = False

# Setup access keys
access_key = ${ROOT_ACCESS_KEY}
secret_key = ${ROOT_SECRET_KEY}

# Enable S3 v4 signature APIs
signature_v2 = False
EOF

info "setup-s3-and-registry: configuring S3 AWS keys and region"
aws configure set aws_access_key_id "${ROOT_ACCESS_KEY}"
aws configure set aws_secret_access_key "${ROOT_SECRET_KEY}"
aws configure set region "${VGW_REGION}"

info "setup-s3-and-registry: creating and configuring S3 buckets"
for bucket in "${S3_PUBLIC_BUCKETS[@]}"; do
    # shellcheck disable=SC2015
    s3cmd ls | grep "s3://${bucket}" && s3cmd rb -r "s3://${bucket}" || true
    s3cmd mb "s3://${bucket}"
    s3cmd setownership "s3://${bucket}" BucketOwnerPreferred
    aws s3api put-bucket-acl --bucket "${bucket}" --acl public-read --endpoint-url "http://${MANAGEMENT_HEADNODE_IP}:${S3_API_PORT}"
    s3cmd setpolicy "${DEPLOY_DIR}/s3-public-read-${bucket}.json" \
          "s3://${bucket}" \
          --host="${MANAGEMENT_HEADNODE_IP}:${S3_API_PORT}" \
          --host-bucket="${MANAGEMENT_HEADNODE_IP}:${S3_API_PORT}"
done

info "setup-s3-and-registry: complete"
