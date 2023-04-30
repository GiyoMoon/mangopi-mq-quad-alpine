#!/bin/sh

apt update
apt install -y git vim make gcc pkg-config zlib1g-dev libusb-1.0-0-dev libfdt-dev libncurses-dev bison flex python3-setuptools swig python3-dev libssl-dev bc kmod rsync u-boot-tools gcc-aarch64-linux-gnu file wget cpio unzip fdisk dosfstools

# Clean up previous builds
rm -rf ./build
umount /mnt/rootfs
umount /mnt/boot
rm -rf /mnt/rootfs
rm -rf /mnt/boot
losetup -d /dev/loop*

mkdir ./build
cd build

# Build bl31 for u-boot
git clone  --depth 1 https://github.com/ARM-software/arm-trusted-firmware.git
cd arm-trusted-firmware
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=sun50i_h616 DEBUG=1 bl31
cd ..

# Build u-boot
git clone  --depth 1 git://git.denx.de/u-boot.git
cd u-boot
cp ../../config/u-boot/.config .
rm drivers/power/axp305.c
cp ../../config/u-boot/axp305.c drivers/power/
make CROSS_COMPILE=aarch64-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin -j$(( $(nproc) * 2 ))
cd ..

# Build linux kernel
git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
cd linux

# Include driver for rtl8723ds
git clone --depth 1 https://github.com/lwfinger/rtl8723ds ./drivers/net/wireless/realtek/rtl8723ds
sed -i 's/---help---/help/g' ./drivers/net/wireless/realtek/rtl8723ds/Kconfig
sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" ./drivers/net/wireless/realtek/rtl8723ds/Makefile
echo "obj-\$(CONFIG_RTL8723DS) += rtl8723ds/" >> ./drivers/net/wireless/realtek/Makefile
sed -i '/source "drivers\/net\/wireless\/realtek\/rtw89\/Kconfig"/a source "drivers\/net\/wireless\/realtek\/rtl8723ds\/Kconfig"' ./drivers/net/wireless/realtek/Kconfig

# Custom device tree reference for Mango Pi
cp ../../config/linux/sun50i-h616-mangopi-mq-quad.dts arch/arm64/boot/dts/allwinner/
echo "dtb-\$(CONFIG_ARCH_SUNXI) += sun50i-h616-mangopi-mq-quad.dtb" >> ./arch/arm64/boot/dts/allwinner/Makefile


make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
sed -i 's/# CONFIG_RTL8723DS is not set/CONFIG_RTL8723DS=m/g' .config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(( $(nproc) * 2 )) Image dtbs modules
cd ..

# Create image file
mkdir image
cd image
cp ../../config/rootfs/rootfs.tar .

mkdir rootfs
tar -xf ./rootfs.tar -C rootfs

ln -s /etc/init.d/modules ./rootfs/etc/runlevels/default/modules
ln -s /etc/init.d/networking ./rootfs/etc/runlevels/default/networking
ln -s /etc/init.d/sshd ./rootfs/etc/runlevels/default/sshd
ln -s /etc/init.d/local ./rootfs/etc/runlevels/default/local
ln -s /etc/init.d/openntpd ./rootfs/etc/runlevels/default/openntpd

cp ../../config/rootfs/init.start ./rootfs/etc/local.d/init.start
chmod +x ./rootfs/etc/local.d/init.start
cp ../../config/rootfs/interfaces ./rootfs/etc/network/interfaces

# use "mango" as the default password
sed -i 's/root:\*::/root:\$6\$mSPRFE858cuEKuxn\$57wp7wsfP8gi\.NouKnhlYAgWmyRKU6e3kNgroD8BXsarjnnlqWBr82uUs9PF\/1Nb3j7vlGjDLoWhgTGjSJDsm0::/g' ./rootfs/etc/shadow

sed -i 's/#ttyS0::respawn:\/sbin\/getty -L ttyS0 115200 vt100/ttyS0::respawn:\/sbin\/getty -L ttyS0 115200 vt100/g' ./rootfs/etc/inittab

sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' ./rootfs/etc/ssh/sshd_config

cp ../../config/rootfs/resolv.conf ./rootfs/etc/resolv.conf
echo "8723ds" >> ./rootfs/etc/modules
echo "Welcome to Alpine on Mango Pi!" >> ./rootfs/etc/motd
echo "mangopi" >> ./rootfs/etc/hostname

cp ../u-boot/u-boot-sunxi-with-spl.bin .
cp ../linux/arch/arm64/boot/Image .
cp ../linux/arch/arm64/boot/dts/allwinner/sun50i-h616-mangopi-mq-quad.dtb .
cp ../../config/image/boot.cmd .

mkimage -C none -A arm64 -T script -d boot.cmd boot.scr

dd if=/dev/zero of=./alpine.img bs=1M count=512

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

cp ./alpine.img ../../
