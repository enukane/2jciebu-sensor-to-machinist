#!/bin/sh
SENSOR=1-1.4
echo -n "${SENSOR}" > /sys/bus/usb/drivers/usb/unbind
echo -n "${SENSOR}" > /sys/bus/usb/drivers/usb/bind
