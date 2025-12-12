### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Melt-Delta Kernel By Pzqqt && 酷安@初春在鹿野 
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

SHA1_STOCK="369217ccf4464067996017977eb1b6d6ab92dc0f"

KEYCODE_UP=42
KEYCODE_DOWN=41

ln -s ${bin}/kmod ${bin}/depmod
ln -s ${bin}/kmod ${bin}/modprobe

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
	ui_print "# 音量+ = 是, 音量- = 否."
	ui_print "# 请按键..."
	get_keycheck_result
	r_keycode=$?
	ui_print "#"
	if [ "$r_keycode" -eq "0" ]; then
		ui_print "- 你选择了: 是."
	else
		ui_print "- 你选择了: 否."
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
		abort "! 读取 super 分区大小失败 (by blockdev)!"
	block_device_size_lp=$(${bin}/lpdump 2>/dev/null | grep -m1 -E 'Size: [[:digit:]]+ bytes$' | awk '{print $2}') || \
		abort "! 读取 super 分区大小失败 (by lpdump)!"
	ui_print "- super 分区大小:"
	ui_print "  - Read by blockdev: $block_device_size"
	ui_print "  - Read by lpdump: $block_device_size_lp"
	[ "$block_device_size" == "9663676416" ] && [ "$block_device_size_lp" == "9663676416" ] || \
		abort "! super 分区大小不匹配!"
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

# Check firmware
if strings /dev/block/bootdevice/by-name/xbl_config${slot} | grep -q 'led_blink'; then
	ui_print "检测到 HyperOS 固件!"
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
				abort "! 无法挂载 modem partition!"
			modem_mount_path=${home}/_modem_mnt
		fi
	fi

	if strings "${modem_mount_path}/image/adsp2.b18" | grep -q 'audiostatus'; then
		ui_print "检测到新版本 adsp2 固件!"
		is_hyperos_fw_with_new_adsp2=true
		if strings "${modem_mount_path}/image/adsp2.b18" | grep -q 'max_life_vol'; then
			ui_print "检测到比新版本还新的 adsp2 固件!"
			is_hyperos_fw_with_newer_adsp2=true
		fi
	fi

	if [ -d "${home}/_modem_mnt" ]; then
		umount ${home}/_modem_mnt
		rmdir ${home}/_modem_mnt
	fi

	unset modem_mount_path
else
	ui_print "检测到 MIUI14 固件!"
	is_hyperos_fw=false
fi

if ! ${is_hyperos_fw}; then
	ui_print " " "抱歉! Melt-Delta Kernel 不支持 MIUI14 固件!"
	sleep 3
	abort "中止..."
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
	ui_print "无法通过 snapshotupdater_static 读取快照状态 rc=$rc."
	if ${BOOTMODE}; then
		ui_print "试试用其他 app 安装."
		ui_print "推荐 KernelFlasher:"
		ui_print "  https://github.com/capntrips/KernelFlasher/releases"
	fi
	abort "中止..."
fi
snapshot_status=$(${bin}/snapshotupdater_static dump 2>/dev/null | grep '^Update state:' | awk '{print $3}')
ui_print "当前快照状态: $snapshot_status"
if [ "$snapshot_status" != "none" ]; then
	ui_print " "
	ui_print "看起来你刚刚更新了 rom."
	ui_print "请先使用 TWRP 高级菜单中的 \"合并快照\" 功能"
	ui_print "以立即完成快照合并."
	abort "中止..."
fi
unset rc snapshot_status

# Check rom type
is_miui_rom=false
is_aospa_rom=false
is_oss_kernel_rom=false
if [ -f /system/framework/MiuiBooster.jar ] && keycode_select "你当前的 rom 是 HyperOS 吗? (我猜是的)"; then
	is_miui_rom=true
elif cat /system/build.prop | grep -qi 'aospa' && keycode_select "你当前的 rom 是 AOSPA 吗? (我猜是的)"; then
	is_aospa_rom=true
elif keycode_select "你的 rom 是基于 OSS 内核的吗?"; then
	is_oss_kernel_rom=true
fi

[ -f ${home}/Image.7z ] || abort "! 找不到 ${home}/Image.7z!"
ui_print " "
ui_print "- 正在解包内核镜像..."
${bin}/7za x ${home}/Image.7z -o${home}/ && [ -f ${home}/Image ] || abort "! 无法解包 ${home}/Image.7z!"
rm ${home}/Image.7z
[ "$(sha1 ${home}/Image)" == "$SHA1_STOCK" ] || abort "! 内核镜像已损坏!"

strings ${home}/Image 2>/dev/null | grep -E -m1 'Linux version.*#' > ${home}/vertmp

# Check vendor_dlkm partition status
[ -d /vendor_dlkm ] || mkdir /vendor_dlkm
is_mounted /vendor_dlkm || \
	mount /vendor_dlkm -o ro || mount /dev/block/mapper/vendor_dlkm${slot} /vendor_dlkm -o ro || \
		abort "! 无法挂载 /vendor_dlkm"

do_backup_flag=false
if [ ! -f /vendor_dlkm/lib/modules/vertmp ]; then
	do_backup_flag=true
fi
$BOOTMODE || umount /vendor_dlkm


# Fix unable to mount image as read-write in recovery
$BOOTMODE || setenforce 0

ui_print " "
ui_print "- 正在解包内核模块..."
modules_pkg=${home}/_modules_hyperos.7z
[ -f $modules_pkg ] || abort "! 找不到 ${modules_pkg}!"
${bin}/7za x $modules_pkg -o${home}/ && [ -d ${home}/_vendor_boot_modules ] && [ -d ${home}/_vendor_dlkm_modules ] || \
	abort "! 无法解包 ${modules_pkg}!"
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
if [ -n "$(ls /vendor/bin/hw/vendor.lineage.touch@* 2>/dev/null)" ]; then
	ui_print " "
	ui_print "- 检测到 Lineage OSS xiaomi touch HAL."
	ui_print "- 使用备选的触屏驱动."
	cp -f ${home}/_alt/xiaomi_touch_los/* ${home}/_vendor_dlkm_modules/
	sed -i \
	    's/\/vendor\/lib\/modules\/xiaomi_touch\.ko:/\/vendor\/lib\/modules\/xiaomi_touch\.ko:\ \/vendor\/lib\/modules\/panel_event_notifier\.ko/g' \
	    ${home}/_vendor_dlkm_modules/modules.dep
fi

# goodix_core.ko
if keycode_select \
    "是否总是启用 360HZ 触控采样率?" \
    " " \
    "提示:" \
    "总是启用 360HZ 触控采样率并不能提升你的日常" \
    "使用体验, 并且可能增加耗电." \
	" "; then
	echo "options goodix_core force_high_report_rate=y" >> $vendor_dlkm_modules_options_file
fi

# qti_battery_charger_main.ko
qti_battery_charger_mod_options=""
if keycode_select \
    "是否显示更真实的电量百分比?" \
    " " \
    "提示:" \
    "这有可能会导致设备难以充满电到 100%." \
    " "; then
	qti_battery_charger_mod_options="${qti_battery_charger_mod_options} report_real_capacity=y"
fi

do_fix_battery_usage=false
if ${is_oss_kernel_rom}; then
	do_fix_battery_usage=true
elif ${is_miui_rom} || ${is_aospa_rom}; then
	do_fix_battery_usage=false
elif keycode_select \
    "是否修复电池使用情况数据异常的问题?" \
    " " \
    "提示:" \
    "如果你发现系统设置中电池使用情况数据" \
    "无法正常显示, 请选择是." \
	" "; then
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
    "是否使用备选的有线耳机按键模式?" \
    " " \
    "提示:" \
    "如果你发现有线耳机的音量加减键不好使, 请选择是." \
    "如果你在使用 MIUI/HyperOS rom, 请选择否." \
    " "; then
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
    "是否使用开源的显示驱动?" \
    " " \
    "提示:" \
    "如果你不知道这意味着什么, 请选择否." \
	" "; then
	use_oss_msm_drm=true
fi
if ${use_oss_msm_drm}; then
	if [ -f /vendor/etc/displayconfig/display_id_4630946370515662721.xml ] || [ -f /vendor/etc/displayconfig/display_id_4630946480857061761.xml ]; then
		# https://github.com/cupid-development/android_device_xiaomi_marble/commit/eee64379280d5bc680e91371679d788b63fe5039
		cp -f ${home}/_alt/OSS-msm_drm-2.ko ${home}/_vendor_dlkm_modules/msm_drm.ko
	else
		cp -f ${home}/_alt/OSS-msm_drm.ko ${home}/_vendor_dlkm_modules/msm_drm.ko
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
    "是否使用开源的相机驱动?" \
    " " \
    "提示:" \
    "如果你不知道这意味着什么, 请选择否." \
	" "; then
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
	ui_print " " "- 检测到 Xiaomi stock IR HAL. 使用 stock 红外驱动."
	use_oss_ir_driver=false
elif [ -f /vendor/bin/hw/android.hardware.ir-service.xiaomi ] || [ -f /vendor/bin/hw/android.hardware.ir-service.lineage ]; then
	ui_print " " "- 检测到 Lineage OSS IR HAL. 使用 OSS 红外驱动."
	use_oss_ir_driver=true
elif keycode_select \
    "是否使用开源的红外驱动?" \
    " " \
    "提示:" \
    "如果你正在使用 AOSP rom 并且发现红外遥控" \
    "不好使, 请选择是." \
    "如果你在使用 MIUI/HyperOS rom, 请选择否." \
	" "; then
	use_oss_ir_driver=true
fi
if ${use_oss_ir_driver}; then
	cp -f ${home}/_alt/OSS-ir-spi.ko ${home}/_vendor_dlkm_modules/ir-spi.ko
fi
unset use_oss_ir_driver

# OSS zram.ko & zsmalloc.ko
if ${is_miui_rom}; then
	if ! keycode_select \
	    "是否使用开源的 ZRAM 内核模块?" \
	    " " \
	    "提示:" \
	    "使用开源的 ZRAM 内核模块意味着你将放弃小米" \
	    "针对 MIUI/HyperOS 的 ZRAM 的特殊优化." \
	    " " \
	    "如果你不知道这意味着什么, 请选择否." \
		" "; then
		cp -f ${home}/_alt/MI-zram.ko ${home}/_vendor_dlkm_modules/zram.ko
		cp -f ${home}/_alt/MI-zsmalloc.ko ${home}/_vendor_dlkm_modules/zsmalloc.ko
	fi
fi

unset vendor_dlkm_modules_options_file

KPM_Patch_State=false
include_patch=false
if [ -f "${bin}/patch_android" ]; then
    if keycode_select \
        "是否需要启用 KPM 内核模块功能" \
        " " \
        "提示:" \
        "该功能可能会提高耗电量." \
        "可能会带来内核不稳定导致的重启." \
        "若不需要请选 否." \
        " "; then
        include_patch=true
    fi
else
    ui_print " "
    ui_print "- 没有找到修补工具无法修补 KPM 功能"
fi

if ${include_patch}; then
KPM_RETRIES=0
MAX_RETRIES=3

while [ "$KPM_Patch_State" = false ] && [ "$KPM_RETRIES" -lt "$MAX_RETRIES" ]; do
    KPM_RETRIES=$((KPM_RETRIES + 1))
    ui_print "-----------------------------------------"
    ui_print "KPM补丁尝试次数: $KPM_RETRIES / $MAX_RETRIES"
    ui_print "可能会异常重启1~2次"

    IMG_SRC="${home}/Image"
    PATCH_BIN="${bin}/patch_android"
    
    ui_print "开始应用 KPM 补丁..."
    [ ! -f "$PATCH_BIN" ] && abort "ERROR：找不到补丁工具"
    
    TMPDIR="/data/local/tmp/kpm_patch_$(date +%Y%m%d_%H%M%S)_$$"
    mkdir -p "$TMPDIR" || abort "ERROR：创建临时目录失败"
    cp "$IMG_SRC" "$TMPDIR/" || abort "ERROR：复制 内核镜像失败 失败"
    cp "$PATCH_BIN" "$TMPDIR/" || abort "ERROR：复制 补丁工具 失败"
    chmod +x "$TMPDIR/patch_android"
    cd "$TMPDIR" || abort "ERROR: 切换到临时目录失败"
    
    ui_print "执行 补丁工具..."
    
    ./patch_android
    PATCH_EXIT_CODE=$?
    
    ui_print "补丁工具 执行返回码: $PATCH_EXIT_CODE"
    
    if [ "$PATCH_EXIT_CODE" -eq 0 ]; then
        [ ! -f "oImage" ] && abort "ERROR：oImage 未生成，补丁可能失败"
        mv oImage Image
        cp -rf Image "${home}" || abort "ERROR：复制补丁后 Image 到 原有目录并覆盖失败"
        ui_print "KPM 补丁应用完成"
        rm -rf "$TMPDIR"
        KPM_Patch_State=true
    else
        ui_print "ERROR：patch_android 执行失败 (返回码: $PATCH_EXIT_CODE)"
        rm -rf "$TMPDIR"
    fi
    
done

[ "$KPM_Patch_State" = false ] && abort "ERROR：KPM 补丁尝试 $MAX_RETRIES 次后仍然失败，中止刷入"
    
fi

# Disguised the GPU model as Adreno730v3
disguised_adreno730=false

if keycode_select \
    "是否伪装 GPU 型号为 Adreno730?" \
    " " \
    "提示:" \
    "骁龙 8+ Gen1 的 GPU 型号即为 Adreno730." \
    "将 GPU 型号伪装成 Adreno730 或许可以在" \
    "某些手游中解锁更高的画质或帧率," \
    "但副作用未知." \
	" "; then
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
	depmod_regen "${home}/_vendor_boot_modules" "/lib/modules/" || abort "! 无法重新生成模块依赖信息!"
fi
if ${need_depmod_regen_vendor_dlkm}; then
	depmod_regen "${home}/_vendor_dlkm_modules" "/vendor/lib/modules/" || abort "! 无法重新生成模块依赖信息!"
fi
unset need_depmod_regen_vendor_boot need_depmod_regen_vendor_dlkm

if ! keycode_select \
    "这是最后一个选项." \
    " " \
    "选择是以正式开始安装." \
    "选择否以取消安装." \
	" "; then
	abort "用户中止."
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
		ui_print "- 看起来你是第一次安装 Melt-Delta Kernel."

		if keycode_select "要备份当前的内核吗?"; then
			ui_print "- 正在备份 kernel, vendor_boot, vendor_dlkm"
			ui_print "  以及 dtbo 分区..."

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
			sync

			ui_print " "
			ui_print "- 当前的 kernel, vendor_boot, vendor_dlkm"
			ui_print "  以及 dtbo 已备份到:"
			ui_print "  $backup_package"
			ui_print "- 如果遇到意外情况, 或者想要恢复到原版内核,"
			ui_print "  请在 TWRP 或某些 app 中刷入它."
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

	ui_print "- 正在解包 /vendor_dlkm 分区..."
	extract_vendor_dlkm_dir=${home}/_extract_vendor_dlkm_$(random_strings 3)
	mkdir -p $extract_vendor_dlkm_dir
	vendor_dlkm_is_ext4=false
	extract_erofs ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir || vendor_dlkm_is_ext4=true
	sync

	if ${vendor_dlkm_is_ext4}; then
		ui_print "- /vendor_dlkm 似乎是 ext4 文件系统."
		mount ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir -o ro -t ext4 || \
			abort "! 不支持的文件系统!"
		vendor_dlkm_full_space=$(df -B1 | grep -E -m1 "$(basename $extract_vendor_dlkm_dir)\$" | awk '{print $2}')
		vendor_dlkm_used_space=$(df -B1 | grep -E -m1 "$(basename $extract_vendor_dlkm_dir)\$" | awk '{print $3}')
		vendor_dlkm_free_space=$(df -B1 | grep -E -m1 "$(basename $extract_vendor_dlkm_dir)\$" | awk '{print $4}')
		vendor_dlkm_stock_modules_size=$(get_size ${extract_vendor_dlkm_dir}/lib/modules)
		ui_print "- /vendor_dlkm 分区空间:"
		ui_print "  - 总空间: $(bytes_to_mb $vendor_dlkm_full_space)"
		ui_print "  - 已用空间: $(bytes_to_mb $vendor_dlkm_used_space)"
		ui_print "  - 可用空间: $(bytes_to_mb $vendor_dlkm_free_space)"
		umount $extract_vendor_dlkm_dir

		vendor_dlkm_new_modules_size=$(get_size ${home}/_vendor_dlkm_modules)
		vendor_dlkm_need_size=$((vendor_dlkm_used_space - vendor_dlkm_stock_modules_size + vendor_dlkm_new_modules_size + 10*1024*1024))
		if [ "$vendor_dlkm_need_size" -ge "$vendor_dlkm_full_space" ]; then
			# Resize vendor_dlkm image
			ui_print "- /vendor_dlkm 分区没有足够的可用空间!"
			ui_print "- 尝试扩容..."

			${bin}/e2fsck -f -y ${home}/vendor_dlkm.img
			if [ "$vendor_dlkm_need_size" -le $((128*1024*1024)) ]; then
				vendor_dlkm_resized_size="128M"
			else
				vendor_dlkm_resized_size=$(echo $vendor_dlkm_need_size | awk '{printf "%dM", ($1 / 1024 / 1024 + 1)}')
			fi
			${bin}/resize2fs ${home}/vendor_dlkm.img $vendor_dlkm_resized_size || \
				abort "! 扩容 vendor_dlkm 镜像失败!"
			ui_print "- 扩容后的 vendor_dlkm.img 镜像大小: ${vendor_dlkm_resized_size}."
			# e2fsck again
			${bin}/e2fsck -f -y ${home}/vendor_dlkm.img

			do_check_super_device_size=true
			unset vendor_dlkm_resized_size
		else
			ui_print "- /vendor_dlkm 分区有足够的可用空间."
		fi

		ui_print "- 尝试挂载 vendor_dlkm 镜像为读写..."
		mount ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir -o rw -t ext4 || \
			abort "! 无法挂载 vendor_dlkm 镜像为读写!"

		unset vendor_dlkm_full_space vendor_dlkm_used_space vendor_dlkm_free_space vendor_dlkm_stock_modules_size vendor_dlkm_new_modules_size vendor_dlkm_need_size
		extract_vendor_dlkm_modules_dir=${extract_vendor_dlkm_dir}/lib/modules
	else
		extract_vendor_dlkm_modules_dir=${extract_vendor_dlkm_dir}/vendor_dlkm/lib/modules
	fi

	ui_print "- 正在更新 /vendor_dlkm 镜像..."
	rm -f ${extract_vendor_dlkm_modules_dir}/*
	cp ${home}/_vendor_dlkm_modules/* ${extract_vendor_dlkm_modules_dir}/ || \
		abort "! 无法更新内核模块! 可用空间不够了?"
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
		ui_print "- 正在打包 /vendor_dlkm 镜像..."
		rm -f ${home}/vendor_dlkm.img
		mkfs_erofs ${extract_vendor_dlkm_dir}/vendor_dlkm ${home}/vendor_dlkm.img || \
			abort "! 无法打包 /vendor_dlkm 镜像!"
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
		ui_print "- 生成的镜像文件大小大于分区大小."
		ui_print "- 需要检查 super 分区..."
		check_super_device_size  # If the check here fails, it will be aborted directly.
		ui_print "- 通过!"
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

unset magisk_patched
rm ${home}/magisk_patched

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
	0) ui_print " " "- 成功修复 vendor_boot 分区!";;
	2) ;;  # The vendor_boot partition is normal and does not need to be repaired.
	*) abort "! 无法修复损坏的 vendor_boot 分区!";;
esac

# vendor_boot install
dump_boot

vendor_boot_modules_dir=${ramdisk}/lib/modules
rm ${vendor_boot_modules_dir}/*
cp ${home}/_vendor_boot_modules/* ${vendor_boot_modules_dir}/
set_perm 0 0 0644 ${vendor_boot_modules_dir}/*

${bin}/7za x ${home}/_dtb.7z -o${home}/ || abort "! 无法解包 _dtb.7z!"

if ${is_oss_kernel_rom}; then
	mv ${home}/dtbo-1.img ${home}/dtbo.img
	rm ${home}/dtbo-0.img
else
	mv ${home}/dtbo-0.img ${home}/dtbo.img
	rm ${home}/dtbo-1.img
fi

mkdir ${home}/_dtbs
cp ${split_img}/dtb ${home}/_dtbs/dtb
dtb_img_splitted=$(${bin}/dtp -i ${home}/_dtbs/dtb | awk '{print $NF}') || abort "! 分割 dtb 文件失败!"
ukee_dtb=
for dtb_file in $dtb_img_splitted; do
	if [ "$(${bin}/fdtget $dtb_file / model -ts)" == "Qualcomm Technologies, Inc. Ukee SoC" ]; then
		ukee_dtb="$dtb_file"
		break
	fi
done
[ -z "$ukee_dtb" ] && abort "! 找不到 Ukee dtb 文件!"

if ${disguised_adreno730}; then
	${bin}/fdtput ${home}/dtb "/soc/qcom,kgsl-3d0@3d00000" "qcom,gpu-model" "Adreno730v3" -ts
fi
unset disguised_adreno730

# Copy the gpu frequency and voltage configuration of old dtb to the new dtb
copy_gpu_pwrlevels_conf "$ukee_dtb" ${home}/dtb
sync

rm -rf ${home}/_dtbs

unset dtb_img_splitted ukee_dtb

write_boot  # Since dtbo.img exists in ${home}, the dtbo partition will also be flashed at this time

########## FLASH VENDOR_BOOT END ##########

unset is_miui_rom is_aospa_rom is_oss_kernel_rom is_hyperos_fw_with_new_adsp2 is_hyperos_fw_with_newer_adsp2

# Patch vbmeta
ui_print " "
for vbmeta_blk in /dev/block/by-name/vbmeta*; do
	ui_print "- Patching $(basename $vbmeta_blk) ..."
	${bin}/vbmeta-disable-verification $vbmeta_blk || {
		ui_print "! 无法打补丁到 ${vbmeta_blk}!"
		ui_print "- 如果安装完成后设备无法启动,"
		ui_print "  请在 TWRP 中手动禁用 AVB."
	}
done

ui_print " "
ui_print "内核源码和刷写工具感谢@Pzqqt"
ui_print "推荐添加QQ群获取最新版本"
ui_print "QQ群: 1050617767"

## end boot install