#!/bin/bash

set -x
set -e

export IMGID=9006
export IMG="rancheros-openstack.img"
export STORAGEID="bitness-nfs"

if [ ! -f "${IMG}" ];then
  wget https://github.com/rancher/os/releases/download/v1.5.6/rancheros-openstack.img
fi

if [ ! -f "${IMG}.orig" ];then
  cp -f "${IMG}" "${IMG}.orig"
fi

guestmount -a ${IMG} -m /dev/sda1 /mnt/tmp/

cat > /mnt/tmp/var/lib/rancher/conf/cloud-config.d/proxmox.yml << '__EOF__'
#cloud-config

# Giant mess of qemu-guest-agent
# https://github.com/rancher/os-services/blob/master/q/qemu-guest-agent.yml
# https://github.com/qemu/qemu/blob/master/qga/commands-posix.c#L84
# https://github.com/rancher/os/issues/2822
# https://github.com/rancher/os/issues/2647
# https://ezunix.org/index.php?title=Prevent_suspending_when_the_lid_is_closed_on_a_laptop_in_RancherOS
#
# The problem is overly complicated because of 2 things:
# - qemu-ga is hard-coded to invoke /sbin/shutdown
# - the rancher qemu-guest-agent service mounts 'volumes_from'
#    which bind mount the above path, so it's impossible to use
#    the supported image, therefor we've replaced it with a generic
#    qemu-guest-agent image
#
# Also note, due to weirdness, we simply bind mount the system-docker
# binary into the contaier and exec ros in *another* container to
# actually trigger the reboot

runcmd:
- sudo rm -rf /var/lib/rancher/resizefs.done

# when the qemu-guest-agent issue is fixed, all agent-related garbage below
# can simply be replaced by this..
#- sudo ros service enable qemu-guest-agent
#- sudo ros service up qemu-guest-agent

# prevents nic from getting 2 addresses
network:
  config: disabled

rancher:
  resize_device: /dev/sda

  services:
    qemu-guest-agent:
      image: linuxkit/qemu-ga:v0.8
      command: /usr/bin/qemu-ga
      privileged: true
      restart: always
      labels:
        io.rancher.os.scope: system
        io.rancher.os.after: console
      pid: host
      ipc: host
      net: host
      uts: host
      volumes:
      - /dev:/dev
      - /usr/bin/ros:/usr/bin/ros
      - /var/run:/var/run
      - /usr/bin/system-docker:/usr/bin/system-docker
      - /home/rancher/overlay/qemu-guest-agent/etc/qemu/qemu-ga.conf:/etc/qemu/qemu-ga.conf
      - /home/rancher/overlay/qemu-guest-agent/sbin/shutdown:/sbin/shutdown
      volumes_from:
      - system-volumes
      - user-volumes

write_files:

  - path: /home/rancher/overlay/qemu-guest-agent/etc/qemu/qemu-ga.conf
    permissions: "0755"
    owner: root
    content: |
      [general]
      daemon=false
      method=virtio-serial
      path=/dev/virtio-ports/org.qemu.guest_agent.0
      pidfile=/var/run/qemu-ga.pid
      statedir=/var/run
      verbose=false
      blacklist=

  - path: /home/rancher/overlay/qemu-guest-agent/sbin/shutdown
    permissions: "0755"
    owner: root
    content: |
      #!/bin/sh

      ARGS=$(echo "${@}" | sed 's/+0/now/g')
      system-docker exec console ros entrypoint shutdown $ARGS

__EOF__

umount /mnt/tmp
sync

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

# has built-in dhcp somewhere else
#qm set ${IMGID} --ipconfig0 "ip=dhcp"
