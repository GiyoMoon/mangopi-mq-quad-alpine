<div align="center"> <img src="./assets/logo_rounded.png" width=250 /></div>
<h1 align="center">MangoPi MQ-Quad Alpine</h1>
This repository provides configs and a script to compile the Linux kernel + Alpine Linux as the root filesystem for the MangoPi MQ-Quad.

## Build script
### Prerequisites
- Uses `apt` to install the required packages, should work on Ubuntu and Debian, I only tested it on Debian
- The scripts needs access to the `/dev/loop*` files to create the image
- It uses `/mnt/boot` and `/mnt/rootfs` as mounting points, make sure these folders are unused
### Running the script
⚠️ You run this script at your own risk.
```shell
git clone https://github.com/GiyoMoon/mangopi-mq-quad-alpine.git
cd mangopi-mq-quad-alpine
chmod +x ./build_image.sh
./build_image.sh
```
The [build script](./build_image.sh) does the following:
- Build u-boot
- Build Linux kernel
  - Includes the `rtl8723ds` wifi driver, which is currently not in mainline
- Create image with Alpine Linux as the root filesystem
  - Configures wifi
    - It configures a static IP address, make sure [`interfaces`](./config/rootfs/interfaces) and [`resolv.conf`](./config/rootfs/resolv.conf) matches your network configuration
    - Set your SSID and password in [`init.start`](./config/rootfs/init.start)
  - Set `mango` as the default password for root (Had issues when trying to log in over UART with no password)
  - Enable SSH and allow root login

When finished, you should see `alpine.img` in the root of this repository.

## Todo
Not everything works yet. I'm trying to do/fix everything on this list.
- [ ] Documentation of the script
- [ ] Rewrite the device tree
  - [ ] Get SPI working
  - [ ] Get HDMI working
  - [ ] Get the act LED working
- [ ] Get SSH working
- [x] Fix filesystem
  - [x] Correctly mount partition 1 to `/boot`
  - [x] Make partition 1 take up full SD card space
- [ ] Make sure that Alpine runs in diskless mode

If you need anything else, feel free to open an issue and I will have a look.
