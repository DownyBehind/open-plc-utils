#!/bin/sh
# file: scripts/slac-sim-watch.sh
#
# Live observation of EV <-> EVSE MAC-layer (HomePlug 0x88E1) traffic on the
# SLAC simulation veth interface. Run in a separate terminal after
# scripts/slac-sim-veth.sh start and while pev/evse are running.
#
# Usage: sudo ./scripts/slac-sim-watch.sh [veth_pev]
# Default interface: veth_pev (or SLAC_VETH_PEV)

IFACE="${1:-${SLAC_VETH_PEV:-veth_pev}}"

echo "Watching HomePlug AV (ether proto 0x88E1) on $IFACE. Ctrl+C to stop."
exec tcpdump -i "$IFACE" -e -XX ether proto 0x88e1
