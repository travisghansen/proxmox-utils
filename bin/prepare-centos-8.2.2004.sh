#!/bin/bash

# docker install
#dnf install docker-ce --nobest
#systemctl enable --now docker
#usermod -aG docker centos


export IMGID=9004
export IMG="CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2"
export STORAGEID="bitness-nfs"

if [ ! -f "${IMG}" ];then
  wget https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2
  #xz --decompress CentOS-8-Container-8.2.2004-20200611.2.x86_64.tar.xz
fi

if [ ! -f "${IMG}.orig" ];then
  cp -f "${IMG}" "${IMG}.orig"
fi

guestmount -a ${IMG} -m /dev/sda1 /mnt/tmp/

# https://www.reddit.com/r/homelab/comments/9s9bcc/proxmoxqemu_question_10023_dns_server/
# https://stackoverflow.com/questions/49826047/cloud-init-manage-resolv-conf
# https://www.centos.org/forums/viewtopic.php?t=66712

rm -rf /mnt/tmp/etc/resolv.conf

# https://www.electrictoolbox.com/sshd-hostname-lookups/
sed -i 's:#UseDNS yes:UseDNS no:' /mnt/tmp/etc/ssh/sshd_config

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
packages:
 - vim
 - screen
 - bash-completion
 - iscsi-initiator-utils
 - wget
 - telnet

ntp:
  enabled: true

# datasource_list: [ NoCloud, ConfigDrive ]
__EOF__


umount /mnt/tmp

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
qm set ${IMGID} --autostart 1
qm set ${IMGID} --onboot 1
qm set ${IMGID} --ostype l26
qm set ${IMGID} --ipconfig0 "ip=dhcp"
