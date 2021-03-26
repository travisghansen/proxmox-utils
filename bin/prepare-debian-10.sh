#!/bin/bash

set -x
set -e

export IMGID=9007
export BASE_IMG="debian-10-openstack-amd64.qcow2"
export IMG="debian-10-openstack-amd64-${IMGID}.qcow2"
export STORAGEID="bitness-nfs"

if [ ! -f "${BASE_IMG}" ];then
  wget https://cloud.debian.org/images/cloud/OpenStack/current-10/debian-10-openstack-amd64.qcow2
fi

if [ ! -f "${IMG}" ];then
  cp -f "${BASE_IMG}" "${IMG}"
fi

# prepare mounts
guestmount -a ${IMG} -m /dev/sda1 /mnt/tmp/
mount --bind /dev/ /mnt/tmp/dev/
mount --bind /proc/ /mnt/tmp/proc/

# get resolving working
mv /mnt/tmp/etc/resolv.conf /mnt/tmp/etc/resolv.conf.orig
cp -a --force /etc/resolv.conf /mnt/tmp/etc/resolv.conf

# install desired apps
chroot /mnt/tmp /bin/bash -c "apt-get update"
chroot /mnt/tmp /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y net-tools curl qemu-guest-agent nfs-common open-iscsi lsscsi sg3-utils multipath-tools scsitools"

# https://www.electrictoolbox.com/sshd-hostname-lookups/
sed -i 's:#UseDNS no:UseDNS no:' /mnt/tmp/etc/ssh/sshd_config

sed -i '/package-update-upgrade-install/d' /mnt/tmp/etc/cloud/cloud.cfg

cat > /mnt/tmp/etc/cloud/cloud.cfg.d/99_custom.cfg << '__EOF__'
#cloud-config

# Install additional packages on first boot
#
# Default: none
#
# if packages are specified, this apt_update will be set to true
#
# packages may be supplied as a single package name or as a list
# with the format [<package>, <version>] wherein the specifc
# package version will be installed.
#packages:
# - qemu-guest-agent
# - nfs-common

ntp:
  enabled: true

# datasource_list: [ NoCloud, ConfigDrive ]
__EOF__

cat > /mnt/tmp/etc/multipath.conf << '__EOF__'
defaults {
    user_friendly_names yes
    find_multipaths yes
}
__EOF__

# enable services
chroot /mnt/tmp systemctl enable open-iscsi.service || true
chroot /mnt/tmp systemctl enable multipath-tools.service || true

# restore systemd-resolved settings
mv /mnt/tmp/etc/resolv.conf.orig /mnt/tmp/etc/resolv.conf

# umount everything
umount /mnt/tmp/dev
umount /mnt/tmp/proc
umount /mnt/tmp

# create template
qm create ${IMGID} --memory 512 --net0 virtio,bridge=vmbr0
qm importdisk ${IMGID} ${IMG} ${STORAGEID} --format qcow2
qm set ${IMGID} --scsihw virtio-scsi-pci --scsi0 ${STORAGEID}:${IMGID}/vm-${IMGID}-disk-0.qcow2
qm set ${IMGID} --ide2 ${STORAGEID}:cloudinit
qm set ${IMGID} --boot c --bootdisk scsi0
qm set ${IMGID} --serial0 socket --vga serial0
qm template ${IMGID}

# set host cpu, ssh key, etc
qm set ${IMGID} --scsihw virtio-scsi-pci
qm set ${IMGID} --cpu host
qm set ${IMGID} --agent enabled=1
qm set ${IMGID} --autostart
qm set ${IMGID} --onboot 1
qm set ${IMGID} --ostype l26
qm set ${IMGID} --ipconfig0 "ip=dhcp"

