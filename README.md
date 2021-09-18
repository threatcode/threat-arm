## Kali-ARM Build-Scripts

Kali Linux ARM build-scripts.

These are the same build scripts that we use to generate the pre-generated official Kali Linux ARM images images, found here: https://www.kali.org/get-kali/

There are additional scripts included in this repository, supporting more devices, but these will need to be built in order for them to be used.

For more information, please see: https://www.kali.org/docs/arm/

- - -

### Building

- These scripts are tested on Kali Linux x64 and x86 installations only _(We **recommend x64**)_
- Make sure you run the `./common.d/build-deps.sh` script before trying to build an image, as this installs all required dependencies
- You will need at **least 8GB of RAM or use SWAP file**

An example workflow to build a _[Raspberry Pi 4](https://www.kali.org/docs/arm/raspberry-pi-4/) Kali Linux image_ would look like:

```
cd ~/
git clone https://gitlab.com/kalilinux/build-scripts/kali-arm
cd ~/kali-arm/
sudo ./common.d/build-deps.sh
sudo ./rpi.sh
```

- Depending on your system hardware & network connectivity, will depend on how long it will take to build
- On x64 systems, after the script finishes running, you will have an image files located in `~/kali-arm/images/` called `kali-linux-2021.3-rpi-armhf.img.xz`
- On x86 systems, as they do not have enough RAM to compress the image, after the script finishes running, you will have an image file located in `~/kali-arm/images/` called `kali-linux-2021.3-rpi-armhf.img`
  - _Should you want to try and shrink the file to make it easier to distribute, you will need to use **your own preferred compression**_.

- - -

### Help

```
$ ./rpi.sh --help
# Architecture (arm64, armel, armhf)
./rpi.sh --arch arm64

# Desktop manager (xfce, gnome, kde, i3, lxde, mate, e17 or none)
./rpi.sh --desktop kde

# Enable debug & log file
./rpi.sh --debug

# Help screen (this)
./rpi.sh --help
$
```

- - -

### Custom Values

An example of using a custom local LAN mirror:

```
$ echo 'mirror="http://192.168.1.100/kali"' > ./builder.txt
...OR...
$ sed 's_^#__' ./builder.txt.example > ./builder.txt
```

- - -

Sat Sep 18 04:58:37 UTC 2021

