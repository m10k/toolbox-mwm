#!/bin/bash

# dstatus - Status monitor for mwm
# Copyright (C) 2024-2025 Matthias Kruk
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

is_charging() {
	local state

	if ! state=$(acpi_ac_get_state "AC"); then
		return 1
	fi

	if [[ "$state" == "0" ]]; then
		return 1
	fi

	return 0
}

get_pwr_status() {
	local charging_label="$1"
	local discharging_label="$2"

	local label
	local level
	local pretty_level

	if ! level=$(acpi_battery_get_level "BAT0"); then
		return 1
	fi

	if (( level < threshold["battery_low"] )); then
		pretty_level=$(pango_markup "${color["battery_low"]}" "$level%")
	elif (( level < threshold["battery_medium"] )); then
		pretty_level=$(pango_markup "${color["battery_medium"]}" "$level%")
	else
		pretty_level=$(pango_markup "${color["battery_high"]}" "$level%")
	fi

	if is_charging; then
		label="$charging_label"
	else
		label="$discharging_label"
	fi

	printf '%s〔%s〕\n' "$label" "$pretty_level"
	return 0
}

pango_markup() {
	local fg="$1"
	local str="$2"

	printf '<span foreground="%s">%s</span>\n' "$fg" "$str"
}

get_net_status() {
	local wired_iface="$1"
	local wired_label="$2"
	local wireless_iface="$3"
	local wireless_label="$4"

	local wifi_addr
	local wifi_essid
	local wifi_status
	local wired_status

	if [[ -n "$wireless_iface" ]]; then
		if wifi_addr=$(net_iface_get_address "$wireless_iface" "inet") &&
		   wifi_essid=$(net_iface_get_essid "$wireless_iface"); then
			wifi_addr=$(head -n 1 <<< "$wifi_addr")
			wifi_addr=$(pango_markup "${color["network_address"]}" "$wifi_addr")
			wifi_essid=$(printf "$wifi_essid")
			wifi_essid=$(pango_markup "${color["network_name"]}" "$wifi_essid")
			wifi_status="$wifi_addr|$wifi_essid"
		else
			wifi_status=$(pango_markup "${color["network_disconnected"]}" "切断")
		fi

		printf '%s〔%s〕' "$wireless_label" "$wifi_status"
	fi

	if [[ -n "$wired_iface" ]]; then
		if wired_status=$(net_iface_get_address "$wired_iface" "inet"); then
			wired_status=$(head -n 1 <<< "$wired_status")
			wired_status=$(pango_markup "${color["network_address"]}" "$wired_status")
		else
			wired_status=$(pango_markup "${color["network_disconnected"]}" "切断")
		fi

		printf '%s〔%s〕' "$wired_label" "$wired_status"
	fi

	printf '\n'
	return 0
}

get_clk_status() {
	local format="$1"

	date +"$format"
}

update_status() {
	local wired_iface="$1"
	local wired_label="$2"
	local wireless_iface="$3"
	local wireless_label="$4"
	local date_format="$5"
	local charging_label="$6"
	local discharging_label="$7"

	local pwr_status
	local net_status

	if ! pwr_status=$(get_pwr_status "$charging_label" "$discharging_label"); then
		pwr_status=""
	fi

	if ! net_status=$(get_net_status "$wired_iface"    \
	                                 "$wired_label"    \
	                                 "$wireless_iface" \
	                                 "$wireless_label"); then
		net_status=""
	fi

	if ! clk_status=$(get_clk_status "$date_format"); then
		clk_status="??:??"
	fi

	if ! xsetroot -name "$net_status$pwr_status$clk_status"; then
		return 1
	fi

	return 0
}

_start() {
	local wired_iface="$1"
	local wired_label="$2"
	local wireless_iface="$3"
	local wireless_label="$4"
	local date_format="$5"
	local charging_label="$6"
	local discharging_label="$7"

	while inst_running; do
		update_status "$wired_iface"       \
		              "$wired_label"       \
		              "$wireless_iface"    \
		              "$wireless_label"    \
		              "$date_format"       \
		              "$charging_label"    \
		              "$discharging_label"
		sleep 5
	done

	return 0
}

try_conf_get() {
	local -n dst="$1"
	local name="$2"
	local config="$3"

	local value

	if value=$(conf_get "$name" "$config"); then
		dst="$value"
		return 0
	fi

	return 1
}

main() {
	local wired_iface
	local wireless_iface
	local date_format
	local wired_label
	local wireless_label
	local charging_label
	local discharging_label
	local -gx LANG

	declare -A threshold
	declare -A color
	local name

	color["battery_low"]="red"
	color["battery_medium"]="#c18716"
	color["battery_high"]="green"
	color["network_name"]="blue"
	color["network_address"]="blue"
	color["network_disconnected"]="red"

	threshold["battery_low"]=15
	threshold["battery_medium"]=50

	if ! opt_parse "$@"; then
		return 1
	fi

	for name in "${!color[@]}"; do
		try_conf_get color["$name"] "$name" "colors"
	done

	for name in "${threshold[@]}"; do
		try_conf_get threshold["$name"] "$name" "thresholds"
	done

	if ! LANG=$(conf_get "locale"); then
		LANG="C"
	fi

	wired_iface=$(conf_get "wired_iface")
	wireless_iface=$(conf_get "wireless_iface")

	if ! date_format=$(conf_get "date_format"); then
		date_format="%Y-%m-%d〔%a〕%H:%M"
	fi

	if ! wired_label=$(conf_get "wired_label"); then
		wired_label="$wired_iface"
	fi

	if ! wireless_label=$(conf_get "wireless_label"); then
		wireless_label="$wireless_iface"
	fi

	if ! charging_label=$(conf_get "charging_label"); then
		charging_label="AC"
	fi

	if ! discharging_label=$(conf_get "discharging_label"); then
		discharging_label="BAT"
	fi

	inst_singleton _start "$wired_iface"       \
	                      "$wired_label"       \
	                      "$wireless_iface"    \
	                      "$wireless_label"    \
	                      "$date_format"       \
	                      "$charging_label"    \
	                      "$discharging_label"
	return 0
}

{
	if ! . toolbox.sh; then
		echo "Could not load toolbox" 1>&2
		exit 1
	fi

	if ! include "log" "opt" "conf" "sem" "inst" "acpi/battery" "acpi/ac" "net/iface"; then
		echo "Could not include modules" 1>&2
		exit 1
	fi

	main "$@"
	exit "$?"
}
