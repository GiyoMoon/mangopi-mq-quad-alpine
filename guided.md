# Creating a bootable sd card image for the Mango Pi MQ-Quad
## Setup
```shell
apt update
apt install -y git vim make gcc pkg-config zlib1g-dev libusb-1.0-0-dev libfdt-dev libncurses-dev bison flex python3-setuptools swig python3-dev libssl-dev bc kmod rsync u-boot-tools gcc-aarch64-linux-gnu file wget cpio unzip fdisk dosfstools

cd /root
mkdir project
cd project

git clone --depth 1 https://github.com/linux-sunxi/sunxi-tools
cd sunxi-tools
make
cd ..
```

## Build u-boot
```shell
git clone  --depth 1 https://github.com/ARM-software/arm-trusted-firmware.git
cd arm-trusted-firmware
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=sun50i_h616 DEBUG=1 bl31
cd ..

git clone  --depth 1 git://git.denx.de/u-boot.git
cd u-boot
```
edit `drivers/power/axp305.c` and insert [this content](./config/axp305.c).
```
make CROSS_COMPILE=aarch64-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin orangepi_zero2_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- menuconfig
```
Disable `[ ] Networking support` and save config as `.config`.
For faster boot up, you can set the boot delay to `-2` under `Boot options -> Autoboot options -> Autoboot`
```
make CROSS_COMPILE=aarch64-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin
cd ..
```

## Build linux kernel

```shell
git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
cd linux
```
At the moment (kernel version <=6.3), the driver for the Wifi chip (RTL8723DS) is missing. We have to add it manually:
```shell
git clone --depth 1 https://github.com/lwfinger/rtw88
rm -r ./drivers/net/wireless/realtek/rtw88
cp -r ./rtw88/alt_rtl8821ce ./drivers/net/wireless/realtek/rtw88
```
Modify `drivers/net/wireless/realtek/rtw88/Kconfig` and delete the hypens around `--help--`.

Modify `drivers/net/wireless/realtek/rtw88/Makefile` and enable `CONFIG_RTL8723D` and `CONFIG_SDIO_HCI`.

edit `arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dts` and insert [this content](./config/sun50i-h616-orangepi-zero2.dts).
```shell
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- menuconfig
```
Enable the `Realtek 8723D SDIO or SPI WiFi` module under `Device Drivers` -> `Network device support` -> `Wireless LAN` -> `Realtek devices`. **IMPORTANT**: Set it to `*` and NOT `m`.
```shell
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(( $(nproc) * 2 )) Image dtbs modules
cd ..
```

## Creating a root file system with Alpine
This needs to be run on an arm alpine machine to generate arm executables. Easiest way is probably to run it in a docker container (`docker run --platform linux/arm64/v8 alpine`)
```shell
git clone --depth 1 https://github.com/alpinelinux/alpine-make-rootfs.git
cd alpine-make-rootfs/
# ./alpine-make-rootfs --branch v3.17 --packages 'openrc apk-tools wpa_supplicant openssh openntpd build-base vim make git' rootfs.tar
./alpine-make-rootfs --branch v3.17 --packages 'openrc apk-tools wireless-regdb chrony iwd openssh cloud-utils-growpart e2fsprogs-extra' rootfs.tar
cd ..
```

## Modifing root file system for a headless setup
```shell
mkdir image
cd image

mkdir rootfs
# rootfs.tar is from the step above
tar -xf ./rootfs.tar -C rootfs
ln -s /etc/init.d/modules ./rootfs/etc/runlevels/boot/modules
ln -s /etc/init.d/networking ./rootfs/etc/runlevels/boot/networking
ln -s /etc/init.d/iwd ./rootfs/etc/runlevels/boot/iwd
ln -s /etc/init.d/sshd ./rootfs/etc/runlevels/boot/sshd
ln -s /etc/init.d/openntpd ./rootfs/etc/runlevels/boot/openntpd
ln -s /etc/init.d/local ./rootfs/etc/runlevels/default/local
```
-Create `./rootfs/etc/local.d/init.start` and insert [this content](./config/rootfs_files/init.start). Make it executable with `chmod +x ./rootfs/etc/local.d/init.start`
- Create `./rootfs/etc/network/interfaces` and insert [this content](./config/rootfs_files/interfaces).
- Generate a password with `openssl passwd -6 {PASSWORD}` and insert it into `./rootfs/etc/shadow`. (Somehow, no password for root doesn't work in the serial console)
- Uncomment the line `ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100` in `./rootfs/etc/inittab` to enable the login console over serial.
- Set nameservers in `/etc/resolv.conf`
- Add `8723ds` to `./rootfs/etc/modules`
- Set motd in `./rootfs/etc/motd`
- Add `mangopi` to `./rootfs/etc/hostname`
- Set `PermitRootLogin yes` in `./rootfs/etc/ssh/sshd_config`
## Creating a bootable image
Note that this step won't work in a docker container, because loop devices don't exist there.

```shell
cp ../u-boot/u-boot-sunxi-with-spl.bin .
cp ../linux/arch/arm64/boot/Image .
cp ../linux/arch/arm64/boot/dts/allwinner/sun50i-h616-mangopi-mq-quad.dtb .
```
Create a `boot.cmd` file:
```cmd
setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw
setenv bootcmd fatload mmc 0:1 0x4fc00000 boot.scr; fatload mmc 0:1 0x40200000 Image; fatload mmc 0:1 0x4fa00000 sun50i-h616-mangopi-mq-quad.dtb; booti 0x40200000 - 0x4fa00000
```
```shell
mkimage -C none -A arm64 -T script -d boot.cmd boot.scr

dd if=/dev/zero of=./alpine.img bs=8K count=512

fdisk ./alpine.img <<EEOF
n
p
1
40960
+131072
n
p
2
172033

w
EEOF

# - -o: starting sector * sector size, --sizelimit: number of sectors * sector size
# - -o: 40960 * 512, --sizelimit: 131072 * 512
# - -o: 172033 * 512, --sizelimit: ? * 512
losetup -f ./alpine.img

dd if=./u-boot-sunxi-with-spl.bin of=/dev/loop0 bs=8K seek=1

losetup -f -o 20971520 --sizelimit 67109376 alpine.img
mkfs.fat /dev/loop1

losetup -f -o 88080896 --sizelimit 448790016 alpine.img
mkfs.ext4 /dev/loop2

mkdir /mnt/boot
mkdir /mnt/rootfs
mount /dev/loop1 /mnt/boot/
mount /dev/loop2 /mnt/rootfs/

cp ./Image /mnt/boot/
cp ./sun50i-h616-mangopi-mq-quad.dtb /mnt/boot/
cp ./boot.scr /mnt/boot/
cp -r ./rootfs/* /mnt/rootfs/

cd ../linux
make INSTALL_MOD_PATH=/mnt/rootfs modules_install
cd ../image

sync
umount /mnt/rootfs
umount /mnt/boot

losetup -d /dev/loop1
losetup -d /dev/loop2
losetup -d /dev/loop0
```

## Write image to sd card
```shell
dd if=./alpine.img of=/dev/mmcblk0
```

## UART over Raspbian
```shell
screen /dev/ttyAMA0 115200
# OR
picocom -b 115200 /dev/ttyAMA0
```
