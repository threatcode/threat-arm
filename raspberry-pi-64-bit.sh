#!/usr/bin/env bash
#
# Threat Linux ARM build-script for Raspberry Pi 2 1.2/3/4/400 (64-bit)
# Source: https://github.com/threatcode/build-scripts/threat-arm
#
# This is a supported device - which you can find pre-generated images on: https://www.threatcode.github.io/get-threat/
# More information: https://www.threatcode.github.io/docs/arm/raspberry-pi-64-bit/
#

./raspberry-pi.sh --arch arm64 "$@"
