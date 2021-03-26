# install

These utils are meant to be run directly from a proxmox host.

- libguestfs-tools
- wget

# Tips

- ensure qemu-guest-agent is baked into the image (avoid installing with cloud-init)
- disable full updates of all packages on boot if possible
- support disk resizing *every* boot
- disable crazy nic names
  - https://www.freedesktop.org/wiki/Software/systemd/PredictableNetworkInterfaceNames/
- do not bake docker into the image
- take care to properly deal with resolv.conf
- support basic network storage systems with sane default (iscsi, multipath, nfs)
