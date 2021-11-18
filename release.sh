#!/usr/bin/env bash
# Copyright 2020-2021 Hewlett Packard Enterprise Development LP
set -Eeuox pipefail

# Function to log errors for simpler debugging
function notify {
        FAILED_COMMAND="$(caller): ${BASH_COMMAND}"
        echo "ERROR: ${FAILED_COMMAND}"
}
trap notify ERR

function copy_manifests {
    rsync -aq "${ROOTDIR}/manifests/" "${BUILDDIR}/manifests/"
    # Set any dynamic variables in the UAN manifest
    sed -i.bak -e "s/@product_version@/${VERSION}/g" "${BUILDDIR}/manifests/uan.yaml"
}

function copy_tests {
    rsync -aq "${ROOTDIR}/tests/" "${BUILDDIR}/tests/"
}

function copy_docs {
    DATE="`date`"
    rsync -aq "${ROOTDIR}/docs/" "${BUILDDIR}/docs/"
    # Set any dynamic variables in the UAN docs
    for docfile in `find "${BUILDDIR}/docs/" -name "*.md" -type f`;
    do
        sed -i.bak -e "s/@product_version@/${VERSION}/g" "$docfile"
        sed -i.bak -e "s/@date@/${DATE}/g" "$docfile"
    done
    for bakfile in `find "${BUILDDIR}/docs/" -name "*.bak" -type f`;
    do
        rm $bakfile
    done
}

function setup_nexus_repos {
    # generate Nexus blob store configuration
    sed s/@name@/${NAME}/g nexus-blobstores.yaml.tmpl | generate-nexus-config blobstore > "${BUILDDIR}/nexus-blobstores.yaml"

    # generate Nexus repository configuration
    REPOFILE=${ROOTDIR}/nexus-repositories.yaml.tmpl

    sed -e "s/@major@/${MAJOR}/g
            s/@minor@/${MINOR}/g
            s/@patch@/${PATCH}/g
            s/@version@/${VERSION}/g
            s#@bloblet_url@#${BLOBLET_URL}#g
            s/@name@/${NAME}/g" ${REPOFILE} | \
        generate-nexus-config repository  > "${BUILDDIR}/nexus-repositories.yaml"
}

function sync_repo_content {
    # sync helm charts
    helm-sync "${ROOTDIR}/helm/index.yaml" "${BUILDDIR}/helm"

    # sync container images
    skopeo-sync "${ROOTDIR}/docker/index.yaml" "${BUILDDIR}/docker"

    # Modify how docker images will be imported so helm charts will work without changes
    mkdir -p "${BUILDDIR}/docker/arti.dev.cray.com/cray"
    mv ${BUILDDIR}/docker/artifactory.algol60.net/*-docker/*stable/* "${BUILDDIR}/docker/arti.dev.cray.com/cray"
    rm -r "${BUILDDIR}/docker/artifactory.algol60.net"

    # sync uan repos from bloblet
    reposync "${BLOBLET_URL}/sle-15sp2" "${BUILDDIR}/rpms/sle-15sp2"
    reposync "${BLOBLET_URL}/sle-15sp3" "${BUILDDIR}/rpms/sle-15sp3"
}

function sync_install_content {
    rsync -aq "${ROOTDIR}/vendor/stash.us.cray.com/scm/shastarelm/release/lib/install.sh" "${BUILDDIR}/lib/install.sh"

    sed -e "s/@major@/${MAJOR}/g
            s/@minor@/${MINOR}/g
            s/@patch@/${PATCH}/g
            s/@version@/${VERSION}/g
            s/@name@/${NAME}/g" include/README > "${BUILDDIR}/README"

    sed -e "s/@major@/${MAJOR}/g
            s/@minor@/${MINOR}/g
            s/@patch@/${PATCH}/g
            s/@version@/${VERSION}/g
            s/@name@/${NAME}/g" include/INSTALL.tmpl > "${BUILDDIR}/INSTALL"

    rsync -aq "${ROOTDIR}/install.sh" "${BUILDDIR}/"
    rsync -aq "${ROOTDIR}/include/nexus-upload.sh" "${BUILDDIR}/lib/nexus-upload.sh"

    rsync -aq "${ROOTDIR}/validate-pre-install.sh" "${BUILDDIR}/"
}

function package_distribution {
    PACKAGE_NAME=${NAME}-${VERSION}
    tar -C $(realpath -m "${ROOTDIR}/dist") -zcvf $(dirname "$BUILDDIR")/${PACKAGE_NAME}.tar.gz $(basename $BUILDDIR)
}

# Definitions and sourced variables
ROOTDIR="$(dirname "${BASH_SOURCE[0]}")"
source "${ROOTDIR}/vars.sh"
source "${ROOTDIR}/vendor/stash.us.cray.com/scm/shastarelm/release/lib/release.sh"
requires rsync tar generate-nexus-config helm-sync skopeo-sync reposync vendor-install-deps sed realpath
BUILDDIR="$(realpath -m "$ROOTDIR/dist/${NAME}-${VERSION}")"

# initialize build directory
[[ -d "$BUILDDIR" ]] && rm -fr "$BUILDDIR"
mkdir -p "$BUILDDIR"
mkdir -p "${BUILDDIR}/lib"

# Create the Release Distribution
copy_manifests
copy_tests
copy_docs
sync_install_content
setup_nexus_repos
sync_repo_content

# Save cray/nexus-setup and quay.io/skopeo/stable images for use in install.sh
vendor-install-deps "$(basename "$BUILDDIR")" "${BUILDDIR}/vendor"

# Package the distribution into an archive
package_distribution
