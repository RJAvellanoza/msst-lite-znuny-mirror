#!/bin/bash
# GoCD Build Orchestration Script for MSSTLite
# Version: 1.0 (2025-07-07)
# 
# This is the NEW pipeline build script that:
# 1. Orchestrates the use of setup.sh and build-package.sh for GoCD builds
#

echo "Preparing files for CI/CD package build..."

APP_BUILD_DIR="$1"
APP_CHECKOUT_DEST="$2"

rm -rf "$APP_BUILD_DIR"
mkdir -p "$APP_BUILD_DIR"

cp -r "$WRAPPER_WORKING_DIR/pipelines/$GO_PIPELINE_NAME"/* "$APP_BUILD_DIR"

ln -sf /opt/otrs "$APP_BUILD_DIR"/znuny-root

cd "$APP_BUILD_DIR"/"$APP_CHECKOUT_DEST"
chmod go+w .
yes | ./build-package.sh --no-install

/usr/bin/env perl /opt/otrs/bin/otrs.Console.pl Dev::Package::Build "$APP_BUILD_DIR"/"$APP_CHECKOUT_DEST"/package-definitions/znuny-users-groups.sopm .
/usr/bin/env perl /opt/otrs/bin/otrs.Console.pl Dev::Package::Build "$APP_BUILD_DIR"/"$APP_CHECKOUT_DEST"/TicketRestAPI.sopm .

cp "$APP_BUILD_DIR"/"$APP_CHECKOUT_DEST"/*.opm "$WRAPPER_WORKING_DIR/pipelines/$GO_PIPELINE_NAME"/