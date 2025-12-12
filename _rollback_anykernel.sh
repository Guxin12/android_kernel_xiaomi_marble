### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Rollback kernel
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

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
no_block_display=true
. tools/ak3-core.sh
unset no_block_display

for partition in boot vendor_dlkm; do
	if [ -f ${home}/_orig/${partition}.img ]; then
		mv -f ${home}/_orig/${partition}.img ${home}/${partition}.img
		rm -f ${home}/${partition}_flashed
		flash_generic ${partition}
	fi
done

## end boot install
