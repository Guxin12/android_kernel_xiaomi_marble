### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Melt Kernel By Pzqqt && Coolapk@初春在鹿野
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=marble
device.name2=marblein
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install

## boot shell variables
block=boot
is_slot_device=1
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=true

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

split_boot # skip ramdisk unpack

########## FLASH BOOT & VENDOR_DLKM START ##########

. ${home}/langs/en.lang
if ${BOOTMODE}; then
	case "$(getprop persist.sys.locale)" in
		zh*) . ${home}/langs/cn.lang;;
	esac
fi

SHA1_STOCK="0"

KEYCODE_UP=42
KEYCODE_DOWN=41

ln -s ${bin}/kmod ${bin}/depmod
ln -s ${bin}/kmod ${bin}/modinfo

extract_erofs() {
	local img_file=$1
	local out_dir=$2

	${bin}/extract.erofs -i "$img_file" -x -T8 -o "$out_dir" &> /dev/null
}

mkfs_erofs() {
	local work_dir=$1
	local out_file=$2
	local partition_name

	partition_name=$(basename "$work_dir")

	${bin}/mkfs.erofs \
		--mount-point "/${partition_name}" \
		--fs-config-file "${work_dir}/../config/${partition_name}_fs_config" \
		--file-contexts  "${work_dir}/../config/${partition_name}_file_contexts" \
		-z lz4hc \
		"$out_file" "$work_dir"
}

is_mounted() { mount | grep -q " $1 "; }

sha1() { ${bin}/magiskboot sha1 "$1"; }

apply_patch() {
	# apply_patch <src_path> <src_sha1> <dst_sha1> <bs_patch>
	local src_path=$1
	local src_sha1=$2
	local dst_sha1=$3
	local bs_patch=$4
	local file_sha1

	file_sha1=$(sha1 $src_path)
	[ "$file_sha1" == "$dst_sha1" ] && return 0
	[ "$file_sha1" == "$src_sha1" ] && ${bin}/hpatchz -f "$src_path" "$bs_patch" "$src_path" 
	[ "$(sha1 $src_path)" == "$dst_sha1" ] || abort "! $_LANG_FAILED_TO_PATCH $src_path!"
}

get_keycheck_result() {
	# Default behavior:
	# - press Vol+: return true (0)
	# - press Vol-: return false (1)

	local rc_1 rc_2

	while true; do
		# The first execution responds to the button press event,
		# the second execution responds to the button release event.
		${bin}/keycheck; rc_1=$?
		${bin}/keycheck; rc_2=$?
		[ "$rc_1" == "$rc_2" ] || continue
		case "$rc_2" in
			"$KEYCODE_UP") return 0;;
			"$KEYCODE_DOWN") return 1;;
		esac
	done
}

keycode_select() {
	local r_keycode

	ui_print " "
	while [ $# != 0 ]; do
		ui_print "# $1"
		shift
	done
	ui_print "#"
	ui_print "# $_LANG_KEYCHECK_PROMPT_1"
	ui_print "# $_LANG_KEYCHECK_PROMPT_2"
	get_keycheck_result
	r_keycode=$?
	ui_print "#"
	if [ "$r_keycode" -eq "0" ]; then
		ui_print "- $_LANG_KEYCHECK_RESULT_YES"
	else
		ui_print "- $_LANG_KEYCHECK_RESULT_NO"
	fi
	ui_print " "
	return $r_keycode
}

get_size() {
	local _path=$1
	local _size

	if [ -d "$_path" ]; then
		du -bs $_path | awk '{print $1}'
		return
	fi
	if [ -b "$_path" ]; then
		_size=$(blockdev --getsize64 $_path) && {
			echo $_size
			return
		}
	fi
	wc -c < $_path
}

bytes_to_mb() {
	echo $1 | awk '{printf "%.1fM", $1 / 1024 / 1024}'
}

check_super_device_size() {
	# Check super device size
	local block_device_size block_device_size_lp

	block_device_size=$(get_size /dev/block/by-name/super) || \
		abort "! $_LANG_FAILED_TO_GET_SUPER_SIZE_BLKDEV"
	block_device_size_lp=$(${bin}/lpdump 2>/dev/null | grep -m1 -E 'Size: [[:digit:]]+ bytes$' | awk '{print $2}') || \
		abort "! $_LANG_FAILED_TO_GET_SUPER_SIZE_LPDUMP"
	ui_print "- ${_LANG_SUPER_SIZE}:"
	ui_print "  - ${_LANG_SUPER_SIZE_BLKDEV}: $block_device_size"
	ui_print "  - ${_LANG_SUPER_SIZE_LPDUMP}: $block_device_size_lp"
	[ "$block_device_size" == "9663676416" ] && [ "$block_device_size_lp" == "9663676416" ] || \
		abort "! $_LANG_SUPER_SIZE_MISMATCH"
}

# copy_gpu_pwrlevels_conf <orig dtb file> <new dtb file>
copy_gpu_pwrlevels_conf() {
	local orig_dtb=$1
	local new_dtb=$2
	local KGSL_NODE="/soc/qcom,kgsl-3d0@3d00000"
	local PWRLEVELS_NODE="${KGSL_NODE}/qcom,gpu-pwrlevels"
	local node reg gpu_freq bus_freq bus_min bus_max level cx_level acd_level initial_pwrlevel

	# Clear the gpu frequency and voltage configuration of new_dtb
	for node in $(${bin}/fdtget "$new_dtb" "$PWRLEVELS_NODE" -l); do
		${bin}/fdtput "$new_dtb" -r "/soc/qcom,kgsl-3d0@3d00000/qcom,gpu-pwrlevels/${node}"
	done

	for node in $(${bin}/fdtget "$orig_dtb" /soc/qcom,kgsl-3d0@3d00000/qcom,gpu-pwrlevels -l | sort -r); do
		# Read
		      reg=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "reg" -tu)
		 gpu_freq=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,gpu-freq" -tu)
		 bus_freq=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-freq" -tu)
		  bus_min=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-min" -tu)
		  bus_max=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-max" -tu)
		    level=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,level" -tu)
		 cx_level=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,cx-level" -tu)
		acd_level=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,acd-level" -tx)

		# Write
		${bin}/fdtput "$new_dtb" -c "${PWRLEVELS_NODE}/${node}"
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,cx-level"  "$cx_level" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,acd-level" "$acd_level" -tx
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-max"   "$bus_max" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-min"   "$bus_min" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-freq"  "$bus_freq" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,level"     "$level" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,gpu-freq"  "$gpu_freq" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "reg" "$reg" -tu
	done

	initial_pwrlevel=$(${bin}/fdtget "$orig_dtb" "$KGSL_NODE" "qcom,initial-pwrlevel" -tu)
	${bin}/fdtput "$new_dtb" "$KGSL_NODE" "qcom,initial-pwrlevel" "$initial_pwrlevel" -tu
}

random_strings() {
	local len=$1

	cat /dev/urandom | tr -dc 'a-zA-Z' | head -c $len
}

depmod_regen() {
	local modules_dir=$1
	local real_modules_path=$2
	local temp_dir temp_mods_dir rc

	[ "${real_modules_path: -1}" == '/' ] || real_modules_path="${real_modules_path}/"
	temp_dir=${home}/_tmp_modules_$(random_strings 3)
	temp_mods_dir=${temp_dir}/lib/modules/1.1  # "1.1" is a fake version
	mkdir -p "$temp_mods_dir"
	cp ${modules_dir}/*.ko ${temp_mods_dir}/

	${bin}/depmod -b "$temp_dir" "1.1"
	rc=$?
	if [ $rc != 0 ]; then
		rm -rf "$temp_dir"
		return $rc
	fi

	cp -f ${temp_mods_dir}/modules.alias ${modules_dir}/modules.alias
	cp -f ${temp_mods_dir}/modules.softdep ${modules_dir}/modules.softdep
	sed -e "s| | ${real_modules_path}|g" -e "s|^|${real_modules_path}|g" ${temp_mods_dir}/modules.dep > ${modules_dir}/modules.dep

	rm -rf "$temp_dir"
}

ui_print " ";

# Check firmware
if strings /dev/block/bootdevice/by-name/xbl_config${slot} | grep -q 'led_blink'; then
	ui_print "$_LANG_HOS_FIRMWARE_DETECTED"
	is_hyperos_fw=true
	is_hyperos_fw_with_new_adsp2=false
	is_hyperos_fw_with_newer_adsp2=false
	if is_mounted /vendor/firmware_mnt && [ -d /vendor/firmware_mnt/image ]; then
		modem_mount_path=/vendor/firmware_mnt
	else
		for blk in /dev/block/by-name/modem${slot} /dev/block/bootdevice/by-name/modem${slot} "$(readlink /dev/block/bootdevice/by-name/modem${slot})"; do
			if mount | grep -qE "^${blk} "; then
				modem_mount_path=$(mount | grep -E "^${blk} " | awk '{print $3}')
				break
			fi
		done
		if [ -z "$modem_mount_path" ]; then
			mkdir ${home}/_modem_mnt
			mount /dev/block/bootdevice/by-name/modem${slot} ${home}/_modem_mnt -o ro || \
				abort "! $_LANG_FAILED_TO_MOUNT modem partition!"
			modem_mount_path=${home}/_modem_mnt
		fi
	fi

	if strings "${modem_mount_path}/image/adsp2.b18" | grep -q 'audiostatus'; then
		ui_print "$_LANG_NEW_ADSP2_FIRMWARE_DETECTED"
		is_hyperos_fw_with_new_adsp2=true
		if strings "${modem_mount_path}/image/adsp2.b18" | grep -q 'max_life_vol'; then
			ui_print "$_LANG_NEWER_ADSP2_FIRMWARE_DETECTED"
			is_hyperos_fw_with_newer_adsp2=true
		fi
	fi

	if [ -d "${home}/_modem_mnt" ]; then
		umount ${home}/_modem_mnt
		rmdir ${home}/_modem_mnt
	fi

	unset modem_mount_path
else
	ui_print "$_LANG_MIUI14_FIRMWARE_DETECTED"
	is_hyperos_fw=false
fi

if ! ${is_hyperos_fw}; then
	ui_print " " "$_LANG_MIUI14_FIRMWARE_NOT_SUPPORT"
	sleep 3
	abort "$_LANG_ABORTING"
fi
unset is_hyperos_fw

# Staging unmodified partition images
mkdir -p ${home}/_orig
cp ${home}/boot.img ${home}/_orig/boot.img

# Check snapshot status
# Technical details: https://blog.xzr.moe/archives/30/
${bin}/snapshotupdater_static dump &>/dev/null
rc=$?
if [ "$rc" != 0 ]; then
	ui_print " "
	ui_print "$_LANG_FAILED_TO_GET_SNAPSHOT_STATUS rc=$rc."
	if ${BOOTMODE}; then
		ui_print "$_LANG_FAILED_TO_GET_SNAPSHOT_STATUS_PROMPT_1"
		ui_print "$_LANG_FAILED_TO_GET_SNAPSHOT_STATUS_PROMPT_2"
		ui_print "$_LANG_FAILED_TO_GET_SNAPSHOT_STATUS_PROMPT_3"
	fi
	abort "$_LANG_ABORTING"
fi
snapshot_status=$(${bin}/snapshotupdater_static dump 2>/dev/null | grep '^Update state:' | awk '{print $3}')
ui_print "${_LANG_CURRENT_SNAPSHOT_STATUS}: $snapshot_status"
if [ "$snapshot_status" != "none" ]; then
	ui_print " "
	ui_print "$_LANG_CURRENT_SNAPSHOT_STATUS_PROMPT_1"
	ui_print "$_LANG_CURRENT_SNAPSHOT_STATUS_PROMPT_2"
	ui_print "$_LANG_CURRENT_SNAPSHOT_STATUS_PROMPT_3"
	abort "$_LANG_ABORTING"
fi
unset rc snapshot_status

# Check rom type
is_miui_rom=false
is_aospa_rom=false
is_oss_kernel_rom=false
if [ -f /system/framework/MiuiBooster.jar ] && keycode_select "$_LANG_GUESS_ROM_MIUI"; then
	is_miui_rom=true
elif grep -qiE 'aospa|neoteric' /system/build.prop && keycode_select "$_LANG_GUESS_ROM_AOSPA"; then
	is_aospa_rom=true
elif keycode_select "$_LANG_GUESS_ROM_OSS_KERNEL"; then
	is_oss_kernel_rom=true
fi

[ -f ${home}/Image.7z ] || abort "! $_LANG_CANNOT_FOUND ${home}/Image.7z!"
ui_print " "
ui_print "- $_LANG_UNPACKING_KERNEL_IMAGE"
${bin}/7za x ${home}/Image.7z -o${home}/ && [ -f ${home}/Image ] || abort "! $_LANG_FAILED_TO_UNPACK ${home}/Image.7z!"
rm ${home}/Image.7z
[ "$(sha1 ${home}/Image)" == "$SHA1_STOCK" ] || abort "! $_LANG_KERNEL_IMAGE_CORRUPTED"

strings ${home}/Image 2>/dev/null | grep -E -m1 'Linux version.*#' > ${home}/vertmp

# Check vendor_dlkm partition status
[ -d /vendor_dlkm ] || mkdir /vendor_dlkm
is_mounted /vendor_dlkm || \
	mount /vendor_dlkm -o ro || mount /dev/block/mapper/vendor_dlkm${slot} /vendor_dlkm -o ro || \
		abort "! $_LANG_FAILED_TO_MOUNT /vendor_dlkm"

do_backup_flag=false
if [ ! -f /vendor_dlkm/lib/modules/vertmp ]; then
	do_backup_flag=true
fi
is_lineageos_xiaomi_touch=false
if ${bin}/modinfo /vendor_dlkm/lib/modules/xiaomi_touch.ko | grep -qi lineage; then
	is_lineageos_xiaomi_touch=true
fi
$BOOTMODE || umount /vendor_dlkm

ui_print " "
ui_print "- $_LANG_UNPACKING_KERNEL_MODULES"
modules_pkg=${home}/_modules_hyperos.7z
[ -f $modules_pkg ] || abort "! $_LANG_CANNOT_FOUND ${modules_pkg}!"
${bin}/7za x $modules_pkg -o${home}/ && [ -d ${home}/_vendor_boot_modules ] && [ -d ${home}/_vendor_dlkm_modules ] || \
	abort "! $_LANG_FAILED_TO_UNPACK ${modules_pkg}!"
if ${is_hyperos_fw_with_newer_adsp2}; then
	cp -f ${home}/_alt/NEW2-qti_battery_charger_main.ko ${home}/_vendor_dlkm_modules/qti_battery_charger_main.ko
	cp -f ${home}/_alt/NEW2-qti_battery_charger_main.ko ${home}/_vendor_boot_modules/qti_battery_charger_main.ko
elif ${is_hyperos_fw_with_new_adsp2}; then
	cp -f ${home}/_alt/NEW-qti_battery_charger_main.ko ${home}/_vendor_dlkm_modules/qti_battery_charger_main.ko
	cp -f ${home}/_alt/NEW-qti_battery_charger_main.ko ${home}/_vendor_boot_modules/qti_battery_charger_main.ko
fi
unset modules_pkg

remove_vendor_boot_modules() {
	while [ $# != 0 ]; do
		rm ${home}/_vendor_boot_modules/${1}.ko
		sed -i "/^${1}\.ko/d" ${home}/_vendor_boot_modules/modules.load
		sed -i "/^${1}\.ko/d" ${home}/_vendor_boot_modules/modules.load.recovery
		shift
	done
}

remove_vendor_dlkm_modules() {
	while [ $# != 0 ]; do
		rm ${home}/_vendor_dlkm_modules/${1}.ko
		sed -i "/^${1}\.ko/d" ${home}/_vendor_dlkm_modules/modules.load
		shift
	done
}

need_depmod_regen_vendor_boot=false
need_depmod_regen_vendor_dlkm=false

vendor_dlkm_modules_options_file=${home}/_vendor_dlkm_modules/modules.options
[ -f $vendor_dlkm_modules_options_file ] || touch $vendor_dlkm_modules_options_file

# xiaomi_touch.ko
if ${is_lineageos_xiaomi_touch}; then
	ui_print " "
	ui_print "- $_LANG_DETECTED_OSS_XIAOMI_TOUCH_PROMPT_1"
	ui_print "- $_LANG_DETECTED_OSS_XIAOMI_TOUCH_PROMPT_2"
	cp -f ${home}/_alt/xiaomi_touch_los/panel_event_notifier.ko ${home}/_vendor_boot_modules/
	cp -f ${home}/_alt/xiaomi_touch_los/* ${home}/_vendor_dlkm_modules/
	need_depmod_regen_vendor_boot=true
	need_depmod_regen_vendor_dlkm=true
fi
unset is_lineageos_xiaomi_touch

# goodix_core.ko
if keycode_select \
    "$_LANG_SELECT_360HZ" \
    " " \
    "$_LANG_NOTES" \
    "$_LANG_SELECT_360HZ_PROMPT_1" \
    "$_LANG_SELECT_360HZ_PROMPT_2"; then
	echo "options goodix_core force_high_report_rate=y" >> $vendor_dlkm_modules_options_file
fi

# qti_battery_charger_main.ko
qti_battery_charger_mod_options=""
if keycode_select \
    "$_LANG_SELECT_REAL_BATTERY" \
    " " \
    "$_LANG_NOTES" \
    "$_LANG_SELECT_REAL_BATTERY_PROMPT_1" \
    "$_LANG_SELECT_REAL_BATTERY_PROMPT_2"; then
	qti_battery_charger_mod_options="${qti_battery_charger_mod_options} report_real_capacity=y"
fi

do_fix_battery_usage=false
if ${is_oss_kernel_rom}; then
	do_fix_battery_usage=true
elif ${is_miui_rom} || ${is_aospa_rom}; then
	do_fix_battery_usage=false
elif keycode_select \
    "$_LANG_SELECT_FIX_BATTERY_USAGE" \
    " " \
    "$_LANG_NOTES" \
    "$_LANG_SELECT_FIX_BATTERY_USAGE_PROMPT_1" \
    "$_LANG_SELECT_FIX_BATTERY_USAGE_PROMPT_2"; then
	do_fix_battery_usage=true
fi
if ${do_fix_battery_usage}; then
	qti_battery_charger_mod_options="${qti_battery_charger_mod_options} fix_battery_usage=y"
fi
unset do_fix_battery_usage

if [ -n "${qti_battery_charger_mod_options}" ]; then
	qti_battery_charger_mod_options=$(echo "$qti_battery_charger_mod_options" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	echo "options qti_battery_charger_main ${qti_battery_charger_mod_options}" >> $vendor_dlkm_modules_options_file
fi
unset qti_battery_charger_mod_options

# Alternative wired headset buttons mode
use_wired_btn_altmode=false
if ${is_miui_rom}; then
	use_wired_btn_altmode=false
elif ${is_oss_kernel_rom} || ${is_aospa_rom}; then
	use_wired_btn_altmode=true
elif keycode_select \
    "$_LANG_SELECT_WIRED_BTN_ALTMODE" \
    " " \
    "$_LANG_NOTES" \
    "$_LANG_SELECT_WIRED_BTN_ALTMODE_PROMPT_1" \
    "$_LANG_SELECT_WIRED_BTN_ALTMODE_PROMPT_2" \
    "$_LANG_SELECT_WIRED_BTN_ALTMODE_PROMPT_3"; then
	use_wired_btn_altmode=true
fi
if ${use_wired_btn_altmode}; then
	echo "options machine_dlkm waipio_wired_btn_altmode=y" >> $vendor_dlkm_modules_options_file
fi
unset use_wired_btn_altmode

# OSS msm_drm.ko
use_oss_msm_drm=false
if ${is_oss_kernel_rom} || ${is_aospa_rom} || [ -f /vendor/bin/sensor-notifier ]; then
	use_oss_msm_drm=true
elif ! ${is_miui_rom}; then  # For roms ported from other OS
	use_oss_msm_drm=false
elif keycode_select \
    "$_LANG_SELECT_OSS_MSM_DRM" \
    " " \
    "$_LANG_NOTES" \
    "$_LANG_SELECT_OSS_MSM_DRM_PROMPT_1"; then
	use_oss_msm_drm=true
fi
if ${use_oss_msm_drm}; then
	if [ -f /vendor/etc/displayconfig/display_id_4630946370515662721.xml ] || [ -f /vendor/etc/displayconfig/display_id_4630946480857061761.xml ]; then
		# https://github.com/cupid-development/android_device_xiaomi_marble/commit/eee64379280d5bc680e91371679d788b63fe5039
		cp -f ${home}/_alt/OSS-msm_drm-2.ko ${home}/_vendor_dlkm_modules/msm_drm.ko
		cp -f ${home}/_alt/OSS-msm_drm-2.ko ${home}/_vendor_boot_modules/msm_drm.ko
	else
		cp -f ${home}/_alt/OSS-msm_drm.ko ${home}/_vendor_dlkm_modules/msm_drm.ko
		cp -f ${home}/_alt/OSS-msm_drm.ko ${home}/_vendor_boot_modules/msm_drm.ko
	fi
fi
unset use_oss_msm_drm

# OSS camera.ko
use_oss_camera_driver=false
if ${is_oss_kernel_rom} || ${is_aospa_rom}; then
	use_oss_camera_driver=true
elif ! ${is_miui_rom}; then  # For roms ported from other OS
	use_oss_camera_driver=false
elif keycode_select \
    "$_LANG_SELECT_OSS_CAMERA" \
    " " \
    "$_LANG_NOTES" \
    "$_LANG_SELECT_OSS_CAMERA_PROMPT_1"; then
	use_oss_camera_driver=true
fi
if ${use_oss_camera_driver}; then
	cp -f ${home}/_alt/OSS-camera.ko ${home}/_vendor_dlkm_modules/camera.ko
fi
unset use_oss_camera_driver

# OSS ir-spi.ko
use_oss_ir_driver=false
if ${is_miui_rom}; then
	use_oss_ir_driver=false
elif [ -n "$(ls /vendor/bin/hw/android.hardware.ir@* 2>/dev/null)" ]; then
	ui_print " " "- $_LANG_IR_HAL_XIAOMI"
	use_oss_ir_driver=false
elif [ -f /vendor/bin/hw/android.hardware.ir-service.xiaomi ] || [ -f /vendor/bin/hw/android.hardware.ir-service.lineage ]; then
	ui_print " " "- $_LANG_IR_HAL_LOS_OSS"
	use_oss_ir_driver=true
elif keycode_select \
    "$_LANG_SELECT_OSS_IR" \
    " " \
    "$_LANG_NOTES" \
    "$_LANG_SELECT_OSS_IR_PROMPT_1" \
    "$_LANG_SELECT_OSS_IR_PROMPT_2" \
    "$_LANG_SELECT_OSS_IR_PROMPT_3"; then
	use_oss_ir_driver=true
fi
if ${use_oss_ir_driver}; then
	cp -f ${home}/_alt/OSS-ir-spi.ko ${home}/_vendor_dlkm_modules/ir-spi.ko
	cp -f ${home}/_alt/OSS-ir-spi.ko ${home}/_vendor_boot_modules/ir-spi.ko
fi
unset use_oss_ir_driver

# OSS zram.ko & zsmalloc.ko
if ${is_miui_rom}; then
	if ! keycode_select \
	    "$_LANG_SELECT_OSS_ZRAM" \
	    " " \
	    "$_LANG_NOTES" \
	    "$_LANG_SELECT_OSS_ZRAM_PROMPT_1" \
	    "$_LANG_SELECT_OSS_ZRAM_PROMPT_2" \
	    "$_LANG_SELECT_OSS_ZRAM_PROMPT_3" \
	    "$_LANG_SELECT_OSS_ZRAM_PROMPT_4"; then
		cp -f ${home}/_alt/MI-zram.ko     ${home}/_vendor_dlkm_modules/zram.ko
		cp -f ${home}/_alt/MI-zram.ko     ${home}/_vendor_boot_modules/zram.ko
		cp -f ${home}/_alt/MI-zsmalloc.ko ${home}/_vendor_dlkm_modules/zsmalloc.ko
		cp -f ${home}/_alt/MI-zsmalloc.ko ${home}/_vendor_boot_modules/zsmalloc.ko
	fi
fi

unset vendor_dlkm_modules_options_file

# ==================================================
# KPM 内核模块补丁
# ==================================================

# 询问用户是否启用 KPM
ui_print " "
ui_print "=========================================="
ui_print "        $_LANG_KPM_16"
ui_print "=========================================="
ui_print " "
ui_print "$_LANG_KPM_17"
ui_print "$_LANG_KPM_17_1"
ui_print "$_LANG_KPM_17_2"
ui_print "$_LANG_KPM_17_3"
ui_print " "

enable_kpm=false
if keycode_select \
    "$_LANG_KPM_18" \
    " " \
    "$_LANG_NOTES" \
    "$_LANG_KPM_18_1" \
    "$_LANG_KPM_18_2"; then
    enable_kpm=true
else
    ui_print "$_LANG_KPM_18_3"
    ui_print "$_LANG_KPM_19"
fi

if $enable_kpm; then
    ui_print " "
    ui_print "$_LANG_KPM_19_1"
    ui_print "=========================================="

    patch_bin="${bin}/patch_android"
    original_image="${home}/Image"
    max_retries=3
    attempt=1
    patch_success=false

    # 验证必要文件
    if [ ! -f "$patch_bin" ] || [ ! -f "$original_image" ]; then
        abort "! $_LANG_KPM_4 $_LANG_KPM_5 $_LANG_FAILED"
    fi

    while [ $attempt -le $max_retries ] && ! $patch_success; do
        ui_print " "
        ui_print "${_LANG_KPM_6} [$attempt/$max_retries]"
        ui_print "$_LANG_KPM_7"

        # 创建临时目录
        temp_dir="/data/local/tmp/kpm_patch_$(date +%Y%m%d_%H%M%S)_$$"
        if ! mkdir -p "$temp_dir"; then
            ui_print "! ${_LANG_KPM_8}: $temp_dir"
            attempt=$((attempt + 1))
            sleep 2
            continue
        fi

        ui_print "- ${_LANG_KPM_9}: $(basename "$temp_dir")"

        # 复制文件
        if ! cp "$original_image" "$temp_dir/Image" || ! cp "$patch_bin" "$temp_dir/patch_android"; then
            ui_print "! ${_LANG_FAILED_TO_EXTRACT}"
            rm -rf "$temp_dir"
            attempt=$((attempt + 1))
            sleep 2
            continue
        fi

        chmod +x "$temp_dir/patch_android"

        # 执行补丁工具
        ui_print "- $_LANG_KPM_1"
        cd "$temp_dir" || {
            rm -rf "$temp_dir"
            attempt=$((attempt + 1))
            sleep 2
            continue
        }

        output=$("$temp_dir/patch_android" 2>&1)
        exit_code=$?

        ui_print "- ${_LANG_KPM_2}: $exit_code"
        if [ $exit_code -ne 0 ] && [ -n "$output" ]; then
            ui_print "! $_LANG_KPM_3"
            echo "$output" | while IFS= read -r line; do
                ui_print "   $line"
            done
        fi

        # 检查生成文件
        if [ ! -f "$temp_dir/oImage" ]; then
            ui_print "! $_LANG_KPM_11"
            rm -rf "$temp_dir"
            attempt=$((attempt + 1))
            sleep 2
            continue
        fi

        # 替换原始镜像
        if mv "$temp_dir/oImage" "$temp_dir/Image" && \
           cp "$temp_dir/Image" "$original_image"; then
            ui_print "- $_LANG_KPM_12"
            patch_success=true
        else
            ui_print "! $_LANG_KPM_13"
        fi

        rm -rf "$temp_dir"

        if ! $patch_success; then
            attempt=$((attempt + 1))
            sleep 2
        fi
    done

    if $patch_success; then
        ui_print " "
        ui_print "$_LANG_KPM_19_2"
        ui_print "=========================================="
    else
        ui_print " "
        ui_print "! ${_LANG_KPM_15} $max_retries ${_LANG_KPM_15_1}"
        ui_print "! $_LANG_KPM_19_3"
        ui_print "=========================================="
        abort "$_LANG_KPM_19_4"
    fi
fi
# ===== End KPM =====

# ===== Optional: perfmgr.ko 来自酷安@AviderMin=====
include_perfmgr=false

if [ -f "${home}/_extra_modules/perfmgr.ko" ]; then
    if keycode_select \
        "$_LANG_SELECT_PERFMGR" \
        "$_LANG_SELECT_PERFMGR_1" \
        " " \
        "$_LANG_NOTES" \
        "$_LANG_SELECT_PERFMGR_2" \
        "$_LANG_SELECT_PERFMGR_3" \
        "$_LANG_SELECT_PERFMGR_4" \
        " "; then
        include_perfmgr=true
    fi
else
    ui_print " "
    ui_print "- $_LANG_SELECT_PERFMGR_5"
fi

if ${include_perfmgr}; then
    # 确保目标目录存在 / Ensure target directory exists
    mkdir -p "${home}/_vendor_boot_modules"

    # 复制 perfmgr.ko 到 vendor_boot_modules / Copy perfmgr.ko to vendor_boot_modules
    cp -f "${home}/_extra_modules/perfmgr.ko" "${home}/_vendor_boot_modules/" \
        || abort "! $_LANG_FAILED_TO_EXTRACT perfmgr.ko"

    # 追加 modules.dep 依赖 / Append dependencies to modules.dep
    dep_line="/lib/modules/perfmgr.ko: /lib/modules/qcom-dcvs.ko /lib/modules/dcvs_fp.ko /lib/modules/qcom_rpmh.ko /lib/modules/cmd-db.ko /lib/modules/qcom_ipc_logging.ko /lib/modules/minidump.ko /lib/modules/smem.ko /lib/modules/sched-walt.ko /lib/modules/qcom-cpufreq-hw.ko /lib/modules/metis.ko /lib/modules/mi_schedule.ko"
    [ -f "${home}/_vendor_boot_modules/modules.dep" ] || touch "${home}/_vendor_boot_modules/modules.dep"
    if ! grep -q "^/lib/modules/perfmgr\.ko:" "${home}/_vendor_boot_modules/modules.dep"; then
        [ -s "${home}/_vendor_boot_modules/modules.dep" ] && echo "" >> "${home}/_vendor_boot_modules/modules.dep"
        echo "$dep_line" >> "${home}/_vendor_boot_modules/modules.dep"
    fi

    # 追加到 modules.load / Append to modules.load
    [ -f "${home}/_vendor_boot_modules/modules.load" ] || touch "${home}/_vendor_boot_modules/modules.load"
    if ! grep -q "^perfmgr\.ko$" "${home}/_vendor_boot_modules/modules.load"; then
        [ -s "${home}/_vendor_boot_modules/modules.load" ] && echo "" >> "${home}/_vendor_boot_modules/modules.load"
        echo "perfmgr.ko" >> "${home}/_vendor_boot_modules/modules.load"
    fi

    ui_print "- perfmgr.ko $_LANG_SELECT_PERFMGR_6"
fi
# ===== End perfmgr.ko =====

# Disguised the GPU model as Adreno730v3
disguised_adreno730=false
if keycode_select \
    "$_LANG_SELECT_DISGUISED_ADRENO730" \
    " " \
    "$_LANG_NOTES" \
    "$_LANG_SELECT_DISGUISED_ADRENO730_PROMPT_1" \
    "$_LANG_SELECT_DISGUISED_ADRENO730_PROMPT_2" \
    "$_LANG_SELECT_DISGUISED_ADRENO730_PROMPT_3" \
    "$_LANG_SELECT_DISGUISED_ADRENO730_PROMPT_4"; then
	disguised_adreno730=true
fi

# Do not load some Xiaomi special modules in AOSP roms
if ! ${is_miui_rom}; then
	# millet related modules
	remove_vendor_dlkm_modules millet_core millet_binder millet_hs millet_oem_cgroup millet_pkg millet_sig binder_gki
	# OSS sched-walt
	cp -f ${home}/_alt/OSS-sched-walt.ko ${home}/_vendor_boot_modules/sched-walt.ko
	remove_vendor_boot_modules metis mi_schedule migt
	remove_vendor_dlkm_modules migt
	# Others
	remove_vendor_boot_modules extend_reclaim mi_freqwdg perf_helper xlogchar
	remove_vendor_dlkm_modules binderinfo binder_prio mi_freqwdg miicmpfilter perf_helper xlogchar

	need_depmod_regen_vendor_boot=true
	need_depmod_regen_vendor_dlkm=true
fi

if ${need_depmod_regen_vendor_boot}; then
	depmod_regen "${home}/_vendor_boot_modules" "/lib/modules/" || abort "! $_LANG_DEPMOD_REGEN_FAILED"
fi
if ${need_depmod_regen_vendor_dlkm}; then
	depmod_regen "${home}/_vendor_dlkm_modules" "/vendor/lib/modules/" || abort "! $_LANG_DEPMOD_REGEN_FAILED"
fi
unset need_depmod_regen_vendor_boot need_depmod_regen_vendor_dlkm

if ! keycode_select \
    "$_LANG_SELECT_LAST" \
    " " \
    "$_LANG_SELECT_LAST_PROMPT_1" \
    "$_LANG_SELECT_LAST_PROMPT_2"; then
	abort "$_LANG_SELECT_LAST_ABORT"
fi

ui_print " "
if true; then  # I don't want to adjust the indentation of the code block below, so leave it as is.
	do_check_super_device_size=false

	# Dump vendor_dlkm partition image
	dd if=/dev/block/mapper/vendor_dlkm${slot} of=${home}/vendor_dlkm.img
	cp ${home}/vendor_dlkm.img ${home}/_orig/vendor_dlkm.img
	vendor_dlkm_block_size=$(get_size /dev/block/mapper/vendor_dlkm${slot})

	# Backup kernel and vendor_dlkm image
	if ${do_backup_flag}; then
		ui_print "- $_LANG_BACKUP_KERNEL_NOTE"

		if keycode_select "$_LANG_SELECT_BACKUP_KERNEL"; then
			ui_print "- $_LANG_BACKUP_KERNEL_DOING_PROMPT_1"
			ui_print "  $_LANG_BACKUP_KERNEL_DOING_PROMPT_2"

			backup_package=/sdcard/Melt-Delta-restore-kernel-$(file_getprop /system/build.prop ro.build.version.incremental)-$(date +"%Y%m%d-%H%M%S").zip

			${bin}/7za a -tzip -bd $backup_package \
				${home}/META-INF ${bin} ${home}/LICENSE ${home}/_restore_anykernel.sh \
				${split_img}/kernel \
				${home}/vendor_dlkm.img \
				/dev/block/bootdevice/by-name/vendor_boot${slot} \
				/dev/block/bootdevice/by-name/dtbo${slot}
			${bin}/7za rn -bd $backup_package kernel Image
			${bin}/7za rn -bd $backup_package _restore_anykernel.sh anykernel.sh
			${bin}/7za rn -bd $backup_package vendor_boot${slot} vendor_boot.img
			${bin}/7za rn -bd $backup_package dtbo${slot} dtbo.img
			# Remove unused binaries
			${bin}/7za d  -bd $backup_package \
				tools/7za tools/hpatchz tools/dtp tools/lpdump \
				tools/e2fsck tools/mkfs.erofs tools/extract.erofs \
				tools/fdtget tools/fdtput tools/keycheck \
				tools/kmod tools/depmod tools/modinfo tools/resize2fs \
				tools/vbmeta-disable-verification tools/vendor_boot_fix
			sync

			ui_print " "
			ui_print "- $_LANG_BACKUP_KERNEL_DONE_PROMPT_1"
			ui_print "  $_LANG_BACKUP_KERNEL_DONE_PROMPT_2"
			ui_print "  $backup_package"
			ui_print "- $_LANG_BACKUP_KERNEL_DONE_PROMPT_3"
			ui_print "  $_LANG_BACKUP_KERNEL_DONE_PROMPT_4"
			ui_print "  $_LANG_BACKUP_KERNEL_DONE_PROMPT_5"
			ui_print " "
			touch ${home}/do_backup_flag

			if ! $BOOTMODE && [ ! -d /twres ]; then
				ui_print "============================================================"
				ui_print "! Warning: Please transfer the backup file just generated to"
				ui_print "! another device via ADB, as it will be lost after reboot!"
				ui_print "============================================================"
				ui_print " "
				sleep 3
			fi

			unset backup_package
		fi
	fi

	ui_print "- $_LANG_VENDOR_DLKM_UNPACKING"
	extract_vendor_dlkm_dir=${home}/_extract_vendor_dlkm_$(random_strings 3)
	mkdir -p $extract_vendor_dlkm_dir
	vendor_dlkm_is_ext4=false
	extract_erofs ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir || vendor_dlkm_is_ext4=true
	sync

	if ${vendor_dlkm_is_ext4}; then
		ui_print "- $_LANG_VENDOR_DLKM_IS_EXT4"

		# Fix unable to mount image as read-write
		if ${BOOTMODE}; then
			fix_sepolicy_rule='allow kernel { app_data_file tmpfs } file { read write }'
			if [ -x /data/adb/ksu/bin/ksud ]; then
				/data/adb/ksu/bin/ksud sepolicy patch "$fix_sepolicy_rule"
			else
				${bin}/magiskpolicy --live "$fix_sepolicy_rule"
			fi
			unset fix_sepolicy_rule
		else
			setenforce 0
		fi
		sleep 1

		mount ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir -o ro -t ext4 || \
			abort "! $_LANG_VENDOR_DLKM_UNSUPPORTED"
		vendor_dlkm_full_space=$(df -B1 | grep -E -m1 "$(basename $extract_vendor_dlkm_dir)\$" | awk '{print $2}')
		vendor_dlkm_used_space=$(df -B1 | grep -E -m1 "$(basename $extract_vendor_dlkm_dir)\$" | awk '{print $3}')
		vendor_dlkm_free_space=$(df -B1 | grep -E -m1 "$(basename $extract_vendor_dlkm_dir)\$" | awk '{print $4}')
		vendor_dlkm_stock_modules_size=$(get_size ${extract_vendor_dlkm_dir}/lib/modules)
		ui_print "- ${_LANG_VENDOR_DLKM_SPACE}:"
		ui_print "  - ${_LANG_VENDOR_DLKM_SPACE_TOTAL}: $(bytes_to_mb $vendor_dlkm_full_space)"
		ui_print "  - ${_LANG_VENDOR_DLKM_SPACE_USED}: $(bytes_to_mb $vendor_dlkm_used_space)"
		ui_print "  - ${_LANG_VENDOR_DLKM_SPACE_FREE}: $(bytes_to_mb $vendor_dlkm_free_space)"
		umount $extract_vendor_dlkm_dir

		vendor_dlkm_new_modules_size=$(get_size ${home}/_vendor_dlkm_modules)
		vendor_dlkm_need_size=$((vendor_dlkm_used_space - vendor_dlkm_stock_modules_size + vendor_dlkm_new_modules_size + 10*1024*1024))
		if [ "$vendor_dlkm_need_size" -ge "$vendor_dlkm_full_space" ]; then
			# Resize vendor_dlkm image
			ui_print "- $_LANG_VENDOR_DLKM_RESIZE_PROMPT_1"
			ui_print "- $_LANG_VENDOR_DLKM_RESIZE_PROMPT_2"

			${bin}/e2fsck -f -y ${home}/vendor_dlkm.img
			if [ "$vendor_dlkm_need_size" -le $((128*1024*1024)) ]; then
				vendor_dlkm_resized_size="128M"
			else
				vendor_dlkm_resized_size=$(echo $vendor_dlkm_need_size | awk '{printf "%dM", ($1 / 1024 / 1024 + 1)}')
			fi
			${bin}/resize2fs ${home}/vendor_dlkm.img $vendor_dlkm_resized_size || \
				abort "! $_LANG_VENDOR_DLKM_RESIZE_FAILED"
			ui_print "- ${_LANG_VENDOR_DLKM_RESIZED}: ${vendor_dlkm_resized_size}."
			# e2fsck again
			${bin}/e2fsck -f -y ${home}/vendor_dlkm.img

			do_check_super_device_size=true
			unset vendor_dlkm_resized_size
		else
			ui_print "- $_LANG_VENDOR_DLKM_RESIZE_NO_NEED"
		fi

		ui_print "- $_LANG_VENDOR_DLKM_MOUNT_RW"

		mount ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir -o rw -t ext4 || \
			abort "! $_LANG_VENDOR_DLKM_MOUNT_RW_FAILED"

		unset vendor_dlkm_full_space vendor_dlkm_used_space vendor_dlkm_free_space vendor_dlkm_stock_modules_size vendor_dlkm_new_modules_size vendor_dlkm_need_size
		extract_vendor_dlkm_modules_dir=${extract_vendor_dlkm_dir}/lib/modules
	else
		extract_vendor_dlkm_modules_dir=${extract_vendor_dlkm_dir}/vendor_dlkm/lib/modules
	fi

	ui_print "- $_LANG_VENDOR_DLKM_UPDATEING"
	rm -f ${extract_vendor_dlkm_modules_dir}/*
	cp ${home}/_vendor_dlkm_modules/* ${extract_vendor_dlkm_modules_dir}/ || \
		abort "! $_LANG_VENDOR_DLKM_UPDATE_FAILED"
	cp ${home}/vertmp ${extract_vendor_dlkm_modules_dir}/vertmp
	sync

	if ${vendor_dlkm_is_ext4}; then
		set_perm 0 0 0644 ${extract_vendor_dlkm_modules_dir}/*
		chcon u:object_r:vendor_file:s0 ${extract_vendor_dlkm_modules_dir}/*
		umount $extract_vendor_dlkm_dir
	else
		for f in "${extract_vendor_dlkm_modules_dir}"/*; do
			echo "vendor_dlkm/lib/modules/$(basename $f) 0 0 0644" >> ${extract_vendor_dlkm_dir}/config/vendor_dlkm_fs_config
		done
		echo '/vendor_dlkm/lib/modules/.+ u:object_r:vendor_file:s0' >> ${extract_vendor_dlkm_dir}/config/vendor_dlkm_file_contexts
		ui_print "- $_LANG_VENDOR_DLKM_REPACKING"
		rm -f ${home}/vendor_dlkm.img
		mkfs_erofs ${extract_vendor_dlkm_dir}/vendor_dlkm ${home}/vendor_dlkm.img || \
			abort "! $_LANG_VENDOR_DLKM_REPACK_FAILED"
		rm -rf ${extract_vendor_dlkm_dir}

		if [ "$(get_size ${home}/vendor_dlkm.img)" -gt "$vendor_dlkm_block_size" ]; then
			do_check_super_device_size=true
		else
			# Fill the erofs image file to the same size as the vendor_dlkm partition
			truncate -c -s $vendor_dlkm_block_size ${home}/vendor_dlkm.img
		fi
	fi

	if ${do_check_super_device_size}; then
		ui_print " "
		ui_print "- $_LANG_SUPER_SIZE_NEED_CHECK_PROMPT_1"
		ui_print "- $_LANG_SUPER_SIZE_NEED_CHECK_PROMPT_2"
		check_super_device_size  # If the check here fails, it will be aborted directly.
		ui_print "- $_LANG_SUPER_SIZE_NEED_CHECK_PASS"
	fi

	unset do_check_super_device_size vendor_dlkm_block_size vendor_dlkm_is_ext4 extract_vendor_dlkm_dir extract_vendor_dlkm_modules_dir
fi

unset do_backup_flag

flash_boot # skip ramdisk repack
flash_generic vendor_dlkm

########## FLASH BOOT & VENDOR_DLKM END ##########

# Remove files no longer needed to avoid flashing again.
rm ${home}/Image
rm ${home}/boot.img
rm ${home}/boot-new.img
rm ${home}/vendor_dlkm.img

touch ${home}/rollback_if_abort_flag

########## FLASH VENDOR_BOOT START ##########

## vendor_boot shell variables
block=vendor_boot
is_slot_device=1
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=true

# reset for vendor_boot patching
reset_ak

# Try to fix vendor_ramdisk size and vendor_ramdisk table entry information that was corrupted by old versions of magiskboot.
${bin}/vendor_boot_fix "$block"
case $? in
	0) ui_print " " "- $_LANG_VENDOR_BOOT_FIX_SUCCESS";;
	2) ;;  # The vendor_boot partition is normal and does not need to be repaired.
	*) abort "! $_LANG_VENDOR_BOOT_FIX_FAILED";;
esac

# vendor_boot install
dump_boot

vendor_boot_modules_dir=${ramdisk}/lib/modules
rm ${vendor_boot_modules_dir}/*
cp ${home}/_vendor_boot_modules/* ${vendor_boot_modules_dir}/
set_perm 0 0 0644 ${vendor_boot_modules_dir}/*

${bin}/7za x ${home}/_dtb.7z -o${home}/ || abort "! $_LANG_FAILED_TO_UNPACK _dtb.7z!"

if ${is_oss_kernel_rom}; then
	mv ${home}/dtbo-1.img ${home}/dtbo.img
	rm ${home}/dtbo-0.img
else
	mv ${home}/dtbo-0.img ${home}/dtbo.img
	rm ${home}/dtbo-1.img
fi

mkdir ${home}/_dtbs
cp ${split_img}/dtb ${home}/_dtbs/dtb
dtb_img_splitted=$(${bin}/dtp -i ${home}/_dtbs/dtb | awk '{print $NF}') || abort "! $_LANG_DTB_SPLIT_FAILED"
ukee_dtb=
for dtb_file in $dtb_img_splitted; do
	if [ "$(${bin}/fdtget $dtb_file / model -ts)" == "Qualcomm Technologies, Inc. Ukee SoC" ]; then
		ukee_dtb="$dtb_file"
		break
	fi
done
[ -z "$ukee_dtb" ] && abort "! $_LANG_DTB_NOT_FOUND_UKEE"

if ${disguised_adreno730}; then
	${bin}/fdtput ${home}/dtb "/soc/qcom,kgsl-3d0@3d00000" "qcom,gpu-model" "Adreno730v3" -ts
fi
unset disguised_adreno730

# Copy the gpu frequency and voltage configuration of old dtb to the new dtb
if [ "$(sha1 $ukee_dtb)" != "$(sha1 ${home}/dtb)" ]; then
	copy_gpu_pwrlevels_conf "$ukee_dtb" ${home}/dtb
	sync
fi

rm -rf ${home}/_dtbs

unset dtb_img_splitted ukee_dtb

write_boot  # Since dtbo.img exists in ${home}, the dtbo partition will also be flashed at this time

########## FLASH VENDOR_BOOT END ##########

unset is_miui_rom is_aospa_rom is_oss_kernel_rom is_hyperos_fw_with_new_adsp2 is_hyperos_fw_with_newer_adsp2

# Patch vbmeta
ui_print " "
for vbmeta_blk in /dev/block/by-name/vbmeta*; do
	ui_print "- $_LANG_PATCHING $(basename $vbmeta_blk) ..."
	${bin}/vbmeta-disable-verification $vbmeta_blk || {
		ui_print "! $_LANG_FAILED_TO_PATCH ${vbmeta_blk}!"
		ui_print "- $_LANG_VBMETA_FAILED_PROMPT_1"
		ui_print "  $_LANG_VBMETA_FAILED_PROMPT_2"
	}
done

## end boot install
