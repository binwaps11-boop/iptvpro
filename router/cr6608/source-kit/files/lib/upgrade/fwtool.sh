# SmartAP owner policy: accept only images with valid metadata and a signature
# chained to /etc/opkg/keys. This file is sourced by sysupgrade.
REQUIRE_IMAGE_SIGNATURE=1
REQUIRE_IMAGE_METADATA=1
export REQUIRE_IMAGE_SIGNATURE REQUIRE_IMAGE_METADATA

fwtool_check_signature() {
	[ $# -gt 1 ] && return 1

	[ ! -x /usr/bin/ucert ] && {
		if [ "$REQUIRE_IMAGE_SIGNATURE" = 1 ]; then
			return 1
		else
			return 0
		fi
	}

	if ! fwtool -q -s /tmp/sysupgrade.ucert "$1"; then
		v "Image signature not present"
		[ "$REQUIRE_IMAGE_SIGNATURE" = 1 -a "$FORCE" != 1 ] && {
			v "Use sysupgrade -F to override this check when downgrading or flashing to vendor firmware"
		}
		[ "$REQUIRE_IMAGE_SIGNATURE" = 1 ] && return 1
		return 0
	fi

	fwtool -q -T -s /dev/null "$1" | \
		ucert -V -m - -c "/tmp/sysupgrade.ucert" -P /etc/opkg/keys

	return $?
}

fwtool_check_image() {
	[ $# -gt 1 ] && return 1

	. /usr/share/libubox/jshn.sh

	if ! fwtool -q -i /tmp/sysupgrade.meta "$1"; then
		v "Image metadata not present"
		[ "$REQUIRE_IMAGE_METADATA" = 1 -a "$FORCE" != 1 ] && {
			v "Use sysupgrade -F to override this check when downgrading or flashing to vendor firmware"
		}
		[ "$REQUIRE_IMAGE_METADATA" = 1 ] && return 1
		return 0
	fi

	json_load "$(cat /tmp/sysupgrade.meta)" || {
		v "Invalid image metadata"
		return 1
	}
	[ -s /tmp/sysinfo/oem_name ] && oem="$(cat /tmp/sysinfo/oem_name)"
	device="$(cat /tmp/sysinfo/board_name)"
	devicecompat="$(uci -q get system.@system[0].compat_version)"
	[ -n "$devicecompat" ] || devicecompat="1.0"

	json_get_var imagecompat compat_version
	json_get_var compatmessage compat_message
	[ -n "$imagecompat" ] || imagecompat="1.0"

	local supported=supported_devices
	[ "$imagecompat" != "1.0" ] && supported=new_supported_devices
	json_select $supported || return 1

	json_get_keys dev_keys
	for k in $dev_keys; do
		json_get_var dev "$k"
		if [ "$dev" = "$device" ] || [ "$dev" = "$oem" ]; then
			if [ "${devicecompat%.*}" != "${imagecompat%.*}" ]; then
				v "The device is supported, but this image is incompatible for sysupgrade based on the image version ($devicecompat->$imagecompat)."
				[ -n "$compatmessage" ] && v "$compatmessage"
				return 1
			fi

			if (([ "${devicecompat#.*}" != "${imagecompat#.*}" ] || [ "$dev" = "$oem" ])) && [ "$SAVE_CONFIG" = "1" ]; then
				[ "$dev" = "$oem" ] && devicecompat="Openwrt " && imagecompat=" OEM"
				[ "$IGNORE_MINOR_COMPAT" = 1 ] && return 0
				v "The device is supported, but the config is incompatible to the new image ($devicecompat->$imagecompat). Please upgrade without keeping config (sysupgrade -n)."
				[ -n "$compatmessage" ] && v "$compatmessage"
				return 1
			fi

			return 0
		fi
	done

	v "Device $device not supported by this image"
	local devices="Supported devices:"
	for k in $dev_keys; do
		json_get_var dev "$k"
		devices="$devices $dev"
	done
	v "$devices"

	return 1
}
