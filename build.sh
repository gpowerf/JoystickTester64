#!/bin/bash
# Build the Joystick Tester 64 app and package it into a D64 image
set -e
cd "$(dirname "$0")"

echo "== Assembling joystick tester..."
acme -f cbm -o joytest.gui -l joytest.sym joysticktester.asm

echo "== Creating disk image..."
rm -f joytest.d64
c1541 -format "joytest,64" d64 joytest.d64
c1541 joytest.d64 -write joytest.gui joytest.gui

echo "== Disk contents:"
c1541 joytest.d64 -list

echo "== Done: joytest.d64"