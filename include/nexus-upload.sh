#!/usr/bin/env bash
# Copyright 2020-2021 Hewlett Packard Enterprise Development LP
#
# User Access Node Installation Helper Script for Offline Installs

ROOTDIR="$(dirname "${BASH_SOURCE[0]}")/.."
source "${ROOTDIR}/lib/install.sh"

# Upload assets to existing repositories
skopeo-sync "${ROOTDIR}/docker" 
nexus-upload helm "${ROOTDIR}/helm" "${CHARTS_REPO:-"charts"}"

# Upload repository contents
nexus-upload raw "${ROOTDIR}/rpms/cray-sles15-sp1-ncn" "uan-2.0.0-sle-15sp1"
