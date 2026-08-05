#! /usr/bin/bash
# SPDX-FileCopyrightText: (C) Copyright 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Phase 6: configure-cluster
#
# - Static node discovery
#
# Run as the deployment user; uses sudo for privileged operations.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/prep_setup.sh"
source /etc/profile.d/build-image.sh

# ── Get OCHAMI Token ─────────────────────────────────────────────
info "cofigure-cluster: waiting for an ochami access token"
for _ in {1..10}; do
    get-ochami-token || DEMO_ACCESS_TOKEN=""
    [ -n "${DEMO_ACCESS_TOKEN}" ] && break
    sleep 10
done
[ -n "${DEMO_ACCESS_TOKEN}" ] || \
    { fail "cannot obtain ochami access token"; exit 1; }

# ── Perform static node discovery ───────────────────────────────
#
# NOTE: The '|| true' part of this command is here to work around SMD
# issue 118. Once that has been resolved, that should be removed. This
# is being tracked locally by issue 19.
info "configure-cluster: performing static node discovery"
# shellcheck disable=SC2046
ochami discover static $(discovery_version) \
    -f yaml \
    -d @"${DEPLOY_DIR}/nodes/nodes.yaml" || true

info "configure-cluster: complete"
