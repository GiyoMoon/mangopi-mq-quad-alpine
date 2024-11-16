#!/bin/sh

# Install required packages
apt update
apt install -y git make gcc bison flex python3-dev python3-setuptools swig libssl-dev bc u-boot-tools fdisk kmod gcc-aarch64-linux-gnu
# Useful, but not required by the script
apt install -y vim libncurses-dev

# Clean up previous builds
rm ./alpine.img
rm -rf ./build
umount /mnt/alpine
rm -rf /mnt/alpine

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
rm drivers/power/axp305.c
cp ../../config/u-boot/axp305.c drivers/power/
make CROSS_COMPILE=aarch64-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin orangepi_zero2_defconfig
sed -i 's/CONFIG_NET=y/# CONFIG_NET is not set/g' .config
sed -i 's/CONFIG_BOOTDELAY=2/CONFIG_BOOTDELAY=-2/g' .config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin -j$(( $(nproc) * 2 ))
cd ..

# Build linux kernel
git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
cd linux

# Include driver for rtw88
rm -rf ./drivers/net/wireless/realtek/rtw88
git clone --depth 1 https://github.com/GiyoMoon/rtw88.git ./drivers/net/wireless/realtek/rtw88

# Custom device tree reference for Mango Pi
cp ../../config/linux/sun50i-h616-mangopi-mq-quad.dts arch/arm64/boot/dts/allwinner/
echo "dtb-\$(CONFIG_ARCH_SUNXI) += sun50i-h616-mangopi-mq-quad.dtb" >> ./arch/arm64/boot/dts/allwinner/Makefile

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
# Disable all modules except rtw88
sed -i -e '/=m/ s/^/# /; s/=m/ is not set/g' .config
sed -i 's/# CONFIG_RTW88 is not set/CONFIG_RTW88=m/g' .config
sed -i 's/# CONFIG_CFG80211 is not set/CONFIG_CFG80211=m/g' .config
sed -i 's/# CONFIG_MAC80211 is not set/CONFIG_MAC80211=m/g' .config
sed -i 's/# CONFIG_RFKILL is not set/CONFIG_RFKILL=m/g' .config
sed -i 's/# CONFIG_IPV6 is not set/CONFIG_IPV6=m/g' .config

# Enable crypto modules, required for iwd
sed -i 's/# CONFIG_CRYPTO_USER_API_HASH is not set/CONFIG_CRYPTO_USER_API_HASH=y/g' .config
sed -i 's/# CONFIG_CRYPTO_USER_API_SKCIPHER is not set/CONFIG_CRYPTO_USER_API_SKCIPHER=y/g' .config
sed -i 's/# CONFIG_KEY_DH_OPERATIONS is not set/CONFIG_KEY_DH_OPERATIONS=y/g' .config
sed -i 's/# CONFIG_CRYPTO_ECB is not set/CONFIG_CRYPTO_ECB=m/g' .config
sed -i 's/# CONFIG_CRYPTO_MD5 is not set/CONFIG_CRYPTO_MD5=m/g' .config
sed -i 's/# CONFIG_CRYPTO_CBC is not set/CONFIG_CRYPTO_CBC=m/g' .config
sed -i 's/# CONFIG_CRYPTO_DES is not set/CONFIG_CRYPTO_DES=m/g' .config
sed -i 's/# CONFIG_CRYPTO_CMAC is not set/CONFIG_CRYPTO_CMAC=m/g' .config

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(( $(nproc) * 2 )) Image dtbs modules
cd ..

# Create image file
mkdir image
cd image
cp ../../config/rootfs/rootfs.tar .

mkdir rootfs
tar -xf ./rootfs.tar -C rootfs

# Services which should start at boot
ln -s /etc/init.d/modules ./rootfs/etc/runlevels/boot/modules
ln -s /etc/init.d/networking ./rootfs/etc/runlevels/boot/networking
ln -s /etc/init.d/iwd ./rootfs/etc/runlevels/boot/iwd
ln -s /etc/init.d/chronyd ./rootfs/etc/runlevels/default/chronyd
ln -s /etc/init.d/sshd ./rootfs/etc/runlevels/default/sshd
ln -s /etc/init.d/local ./rootfs/etc/runlevels/default/local

cp ../../config/rootfs/init.start ./rootfs/etc/local.d/init.start
chmod +x ./rootfs/etc/local.d/init.start
cp ../../config/rootfs/interfaces ./rootfs/etc/network/interfaces

# use "mango" as the default password
sed -i 's/root:\*::/root:\$6\$mSPRFE858cuEKuxn\$57wp7wsfP8gi\.NouKnhlYAgWmyRKU6e3kNgroD8BXsarjnnlqWBr82uUs9PF\/1Nb3j7vlGjDLoWhgTGjSJDsm0::/g' ./rootfs/etc/shadow

sed -i 's/#ttyS0::respawn:\/sbin\/getty -L ttyS0 115200 vt100/ttyS0::respawn:\/sbin\/getty -L ttyS0 115200 vt100/g' ./rootfs/etc/inittab

sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' ./rootfs/etc/ssh/sshd_config

cp ../../config/rootfs/resolv.conf ./rootfs/etc/resolv.conf
echo "rtw_8723ds" >> ./rootfs/etc/modules
echo "Welcome to Alpine on Mango Pi!" > ./rootfs/etc/motd
echo "mangopi" > ./rootfs/etc/hostname

cp ../u-boot/u-boot-sunxi-with-spl.bin .
cp ../linux/arch/arm64/boot/Image .
cp ../linux/arch/arm64/boot/dts/allwinner/sun50i-h616-mangopi-mq-quad.dtb .
cp ../../config/image/boot.cmd .

mkimage -C none -A arm64 -T script -d boot.cmd boot.scr

# Total size of the image = 100MB = 104857600 bytes = 204800 sectors
# One sector is 512 bytes big
#
# 664509 bytes      ./u-boot-sunxi-with-spl.bin
# = 1298 sectors + 2048 = 3346 sector offset for partition 1

dd if=/dev/zero of=./alpine.img bs=1M count=140

fdisk ./alpine.img <<EEOF
n
p
1
3346

w
EEOF

imageloop=$(losetup -f --show ./alpine.img)

dd if=./u-boot-sunxi-with-spl.bin of=$imageloop bs=8K seek=1

partitionloop=$(losetup -f --show -o 1713152 alpine.img)
mkfs.ext4 $partitionloop

mkdir /mnt/alpine
mount $partitionloop /mnt/alpine/

mkdir /mnt/alpine/boot
cp ./Image /mnt/alpine/boot/
cp ./sun50i-h616-mangopi-mq-quad.dtb /mnt/alpine/boot/
cp ./boot.scr /mnt/alpine/boot/

cp -r ./rootfs/* /mnt/alpine/

cd ../linux
make INSTALL_MOD_PATH=/mnt/alpine modules_install
mkdir /mnt/alpine/lib/firmware/rtw88
cp ./drivers/net/wireless/realtek/rtw88/rtw8723d_fw.bin /mnt/alpine/lib/firmware/rtw88
cd ../image

# Mount devpts to enable pty
echo "devpts          /dev/pts        devpts  rw        0 0" > /mnt/alpine/etc/fstab

sync
umount /mnt/alpine

losetup -d $imageloop
losetup -d $partitionloop

cp ./alpine.img ../../
