setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p1 rootfstype=ext4 rootwait rw
setenv bootcmd ext4load mmc 0:1 0x4fc00000 boot/boot.scr; ext4load mmc 0:1 0x40200000 boot/Image; ext4load mmc 0:1 0x4fa00000 boot/sun50i-h616-mangopi-mq-quad.dtb; booti 0x40200000 - 0x4fa00000
