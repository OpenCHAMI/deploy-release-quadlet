#! /usr/bin/bash
# SPDX-FileCopyrightText: (C) Copyright 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Pick up the common setup for the prepare scripts
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/prep_setup.sh"

function install_ochami() {
    local ochami_version="{{ openchami_config.ochami.version }}"
{%- if openchami_config.ochami.build %}
    local ochami_url="{{ openchami_config.ochami.url }}"
    info "retrieving OpenCHAMI CLI (ochami) soure repo: '${ochami_url}'"
    rm -rf "${DEPLOY_DIR}/ochami"
    su - "${DEPLOY_USER}" -c \
         "git config --global --add safe.directory '${DEPLOY_DIR}/ochami'"
    git clone "${ochami_url}" "${DEPLOY_DIR}/ochami"
    info "building version '${ochami_version}' of 'ochami'"
    cd "${DEPLOY_DIR}/ochami"
    git checkout "${ochami_version}"
    make install
{%- else %}
    info "retrieving OpenCHAMI CLI (ochami) RPM"
    local latest_release_url=$(curl -s https://api.github.com/repos/OpenCHAMI/ochami/releases/${ochami_version} | jq -r ".assets[] | select(.name | endswith(\"$(derive_architecture).rpm\")) | .browser_download_url")
    curl -L "${latest_release_url}" -o ochami.rpm
    info "Installing OpenCHAMI CLI (ochami) RPM"
    dnf install -y ./ochami.rpm
{%- endif %}
}

function install_openchami() {
    local openchami_url="{{ openchami_config.release.url }}"
    local release_version="{{ openchami_config.release.version }}"
    info "retrieving OpenCHAMI Release source repo: '${openchami_url}'"
    rm -rf "${DEPLOY_DIR}/openchami_release"
    su - "${DEPLOY_USER}" -c \
         "git config --global --add safe.directory '${DEPLOY_DIR}/ochami'"
    git clone "${openchami_url}" "${DEPLOY_DIR}/openchami_release"
    info "building version '${release_version}' of OpenCHAMI Release"
    cd "${DEPLOY_DIR}/openchami_release"
    git checkout "${release_version}"
    make
    local rpm="$(ls openchami-*.noarch.rpm)"
    # Install the RPM. First, Remove openchami if it is currently
    # installed, ignore failure
    info "removing any previous OpenCHAMI instance"
    dnf remove -y --noautoremove openchami || true
    # Also remove some cruft it leaves around
    rm -rf /etc/openchami
    # Now install it...
    info "installing latest OpenCHAMI: '${rpm}'"
    dnf install -y "${rpm}"
}

info "preparing platform - install required packages"
PRE_INSTALL_PACKAGES="\
        epel-release \
{%- for package in hosting_config.extra_packages.pre %}
        {{ package }} \
{%- endfor %}
"
PACKAGES="\
{%- if deployment_mode == 'host' %}
        libvirt \
        qemu-kvm \
        virt-install \
        virt-manager \
{%- endif %}
        dnsmasq \
        podman \
        buildah \
        git \
        ansible-core \
        openssl \
        nfs-utils \
        s3cmd \
        make\
        rpmdevtools\
{%- if openchami_config.ochami.build %}
        scdoc \
{%- endif %}
{%- for package in hosting_config.extra_packages.main %}
        {{ package }} \
{%- endfor %}
"
dnf -y check-update || true
# packages needed before main package list install
dnf install -y ${PRE_INSTALL_PACKAGES}
# packages needed to install and use OpenCHAMI
dnf -y install ${PACKAGES}  # list of packages, should not be quoted

# Don't enable libvirt if we are not running in host mode
{%- if deployment_mode == 'host' %}
systemctl enable --now libvirtd
{%- endif %}

{%- if openchami_config.ochami.build %}
# Go is needed to build 'ochami' and should be at the latest stable
# release version to avoid problems.  Uninstall any version of golang
# that might currently be part of the distribution or might have been
# installed by a prior deployment.
dnf remove -y golang || true
rm -rf /usr/local/go
rm -f /usr/bin/go
# Figure out the newest stable release of golang so we can install that.
GOLANG_VERSION="$(curl -s "https://go.dev/VERSION?m=text" | head -1)"
GOLANG_ARCH="$(derive_architecture)"
# Retrieve the tarball for the latest version of golang
curl -s -o "${DEPLOY_DIR}/golang.tgz" \
     "https://dl.google.com/go/${GOLANG_VERSION}.linux-${GOLANG_ARCH}.tar.gz"
(cd /usr/local; tar xzf "${DEPLOY_DIR}/golang.tgz")
ln -s /usr/local/go/bin/go /usr/bin/go
{%- endif %}
info "preparing platform - create the deployment user '${DEPLOY_USER}'"
if ! getent group "${DEPLOY_GROUP}"; then
    info "creating primary group '{{ group }}' for '${DEPLOY_USER}'"
    groupadd "${DEPLOY_GROUP}"
fi
{%- for group in manifest.deployment_user.supplementary_groups %}
if ! getent group "{{ group }}"; then
    info "creating supplementary group '{{ group }}' for '${DEPLOY_USER}'"
    groupadd "{{ group }}"
fi
{%- endfor %}
if ! getent passwd "${DEPLOY_USER}"; then
    info "creating user '${DEPLOY_USER}'"
    useradd -g "${DEPLOY_GROUP}" "${DEPLOY_USER}"
fi
{%- for group in manifest.deployment_user.supplementary_groups %}
if ! getent group "{{ group }}"; then
    info "adding supplementary group '{{ group }}' to '${DEPLOY_USER}'"
    usermod -aG "{{ group }}" "${DEPLOY_USER}"
fi
{%- endfor %}
# Remove the deployment user from /etc/sudoers and then put it back
# with NOPASSWD access
info "giving user '${DEPLOY_USER}' passwordless sudo access"
sed -i -e "/[[:space:]]*${DEPLOY_USER}/d" /etc/sudoers
echo "${DEPLOY_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Install OpenCHAMI Release package and the OpenCHAMI CLI (ochami).
install_openchami
install_ochami
