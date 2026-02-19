#!/bin/sh
# file: scripts/slac-sim-veth.sh
#
# SLAC sequence PC simulation using Linux veth pair (no PLC hardware).
# EV(pev) and EVSE(evse) communicate over virtual Ethernet; you can
# capture MAC-layer (HomePlug 0x88E1) traffic on the veth interfaces.
#
# Requirements: Linux, ip (iproute2), pev and evse in PATH.
# Run with sufficient privilege (e.g. sudo) for creating veth and raw sockets.

set -e

VETH_PEV="${SLAC_VETH_PEV:-veth_pev}"
VETH_EVSE="${SLAC_VETH_EVSE:-veth_evse}"

usage () {
	echo "Usage: $0 [start|stop|run|run-capture|status]"
	echo "  start        - create veth pair and bring interfaces up"
	echo "  stop         - remove veth pair"
	echo "  run          - start evse in background, then run pev"
	echo "  run-capture  - run with tcpdump capturing MAC-layer (0x88E1) traffic"
	echo "  status       - show veth interfaces"
	echo ""
	echo "To observe EV<->EVSE messages at MAC layer: use 'run-capture' or"
	echo "  in another terminal: tcpdump -i ${VETH_PEV} -e -XX ether proto 0x88e1"
	echo ""
	echo "Environment: SLAC_VETH_PEV, SLAC_VETH_EVSE"
	exit 0
}

do_start () {
	if ip link show "$VETH_PEV" >/dev/null 2>&1; then
		echo "veth already exists: $VETH_PEV / $VETH_EVSE"
		ip link show "$VETH_PEV" "$VETH_EVSE" 2>/dev/null || true
		return 0
	fi
	ip link add "$VETH_PEV" type veth peer name "$VETH_EVSE"
	ip link set "$VETH_PEV" up
	ip link set "$VETH_EVSE" up
	echo "Created and brought up: $VETH_PEV <-> $VETH_EVSE"
	ip link show "$VETH_PEV"
	ip link show "$VETH_EVSE"
}

do_stop () {
	if ! ip link show "$VETH_PEV" >/dev/null 2>&1; then
		echo "veth pair not found."
		return 0
	fi
	ip link set "$VETH_PEV" down 2>/dev/null || true
	ip link set "$VETH_EVSE" down 2>/dev/null || true
	ip link delete "$VETH_PEV" 2>/dev/null || true
	echo "Removed veth pair: $VETH_PEV / $VETH_EVSE"
}

do_run () {
	if ! ip link show "$VETH_PEV" >/dev/null 2>&1; then
		echo "Run '$0 start' first to create the veth pair."
		exit 1
	fi
	EVSE_PID=
	trap '[ -n "$EVSE_PID" ] && kill $EVSE_PID 2>/dev/null; exit' INT TERM
	echo "Starting evse on $VETH_EVSE (background)..."
	evse -i "$VETH_EVSE" -v &
	EVSE_PID=$!
	sleep 2
	echo "Starting pev on $VETH_PEV..."
	pev -i "$VETH_PEV" -v
	kill $EVSE_PID 2>/dev/null || true
}

do_run_capture () {
	if ! ip link show "$VETH_PEV" >/dev/null 2>&1; then
		echo "Run '$0 start' first."
		exit 1
	fi
	CAPDIR="${SLAC_CAP_DIR:-.}"
	CAPFILE="${CAPDIR}/slac_mac_$(date +%Y%m%d_%H%M%S).pcap"
	mkdir -p "$CAPDIR"
	EVSE_PID=
	TCPDUMP_PID=
	trap '[ -n "$TCPDUMP_PID" ] && kill $TCPDUMP_PID 2>/dev/null; [ -n "$EVSE_PID" ] && kill $EVSE_PID 2>/dev/null; exit' INT TERM
	echo "Capturing HomePlug (0x88E1) traffic to $CAPFILE ..."
	tcpdump -i "$VETH_PEV" -w "$CAPFILE" -U ether proto 0x88e1 2>/dev/null &
	TCPDUMP_PID=$!
	sleep 1
	echo "Starting evse on $VETH_EVSE (background)..."
	evse -i "$VETH_EVSE" -v &
	EVSE_PID=$!
	sleep 2
	echo "Starting pev on $VETH_PEV..."
	pev -i "$VETH_PEV" -v
	kill $EVSE_PID 2>/dev/null || true
	kill $TCPDUMP_PID 2>/dev/null || true
	echo "Capture saved: $CAPFILE (view with: tcpdump -r $CAPFILE -e -XX ether proto 0x88e1)"
}

do_status () {
	if ip link show "$VETH_PEV" >/dev/null 2>&1; then
		echo "veth pair: $VETH_PEV <-> $VETH_EVSE"
		ip -br link show "$VETH_PEV" "$VETH_EVSE"
	else
		echo "veth pair not present. Run: $0 start"
	fi
}

case "${1:-}" in
	start)  do_start ;;
	stop)   do_stop ;;
	run)    do_run ;;
	run-capture) do_run_capture ;;
	status) do_status ;;
	-h|--help) usage ;;
	*) echo "Usage: $0 start|stop|run|run-capture|status"; exit 1 ;;
esac
