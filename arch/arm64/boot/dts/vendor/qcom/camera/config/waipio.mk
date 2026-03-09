dtbo-$(CONFIG_ARCH_WAIPIO) := waipio-camera.dtbo
dtbo-$(CONFIG_ARCH_WAIPIO) += waipio-camera-overlay-v2.dtbo \
								waipio-camera-sensor-mtp.dtbo \
								waipio-camera-sensor-cdp.dtbo \
								waipio-camera-sensor-qrd.dtbo \
								zeus-sm8450-camera-sensor.dtbo \
								cupid-sm8450-camera-sensor.dtbo

dtbo-$(CONFIG_ARCH_DIWALI) += diwali-camera.dtbo
dtbo-$(CONFIG_ARCH_DIWALI) += diwali-camera-sensor-idp.dtbo
dtbo-$(CONFIG_ARCH_DIWALI) += diwali-camera-sensor-qrd.dtbo
dtbo-$(CONFIG_ARCH_DIWALI) += ziyi-sm7450-camera-sensor.dtbo

dtbo-$(CONFIG_ARCH_CAPE) += cape-camera.dtbo
dtbo-$(CONFIG_ARCH_CAPE) += cape-camera-sensor-mtp.dtbo \
				cape-camera-sensor-cdp.dtbo \
				cape-camera-sensor-qrd.dtbo \
				unicorn-sm8475-camera-sensor.dtbo \
				thor-sm8475-camera-sensor.dtbo \
				mayfly-sm8475-camera-sensor.dtbo \
				mondrian-sm8475-camera-sensor.dtbo \
				zizhan-sm8475-camera-sensor.dtbo \
				diting-sm8475-camera-sensor.dtbo

dtbo-$(CONFIG_ARCH_CAPE) += ukee-camera-sensor-mtp.dtbo \
				ukee-camera-sensor-cdp.dtbo \
				ukee-camera-sensor-qrd.dtbo \
				marble-sm7475-camera-sensor.dtbo
dtbo-$(CONFIG_ARCH_CAPE) += ukee-camera.dtbo
