#!/usr/bin/env bash
#
# Threat Linux ARM build-script for Radxa Zero (64-bit)
# Source: https://github.com/threatcode/build-scripts/threat-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.threatcode.github.io/docs/arm/radxa-zero/
#

# Hardware model
hw_model=${hw_model:-"radxa-zero-emmc"}

# Architecture
architecture=${architecture:-"arm64"}

# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load default base_image configs
source ./common.d/base_image.sh

include radxa_zero emmc
