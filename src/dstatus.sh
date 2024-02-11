#!/bin/bash

# dstatus - Status monitor for mwm
# Copyright (C) 2024 Matthias Kruk
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

	if (( level < 15 )); then
		pretty_level=$(pango_markup "red" "$level%")
	elif (( level < 50 )); then
		pretty_level=$(pango_markup "#c18716" "$level%")
	else
		pretty_level=$(pango_markup "green" "$level%")
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
			wifi_addr=$(pango_markup "green" "$wifi_addr")
			wifi_essid=$(printf "$wifi_essid")
			wifi_essid=$(pango_markup "green" "$wifi_essid")
			wifi_status="$wifi_addr|$wifi_essid"
		else
			wifi_status=$(pango_markup "red" "切断")
		fi

		printf '%s〔%s〕' "$wireless_label" "$wifi_status"
	fi

	if [[ -n "$wired_iface" ]]; then
		if wired_status=$(net_iface_get_address "$wired_iface" "inet"); then
			wired_status=$(head -n 1 <<< "$wired_status")
			wired_status=$(pango_markup "green" "$wired_status")
		else
			wired_status=$(pango_markup "red" "切断")
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

	local err

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

main() {
	local wired_iface
	local wireless_iface
	local date_format
	local wired_label
	local wireless_label
	local charging_label
	local discharging_label
	local -gx LANG

	if ! opt_parse "$@"; then
		return 1
	fi

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
