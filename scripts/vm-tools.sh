#!/usr/bin/env bash
set -x

SSH_USER=${SSH_USERNAME:-vagrant}
SSH_USER_HOME=${SSH_USER_HOME:-/home/${SSH_USER}}

function install_open_vm_tools {
    echo "Packer | Installing Open VM Tools"
    # Install open-vm-tools so we can mount shared folders
    yum install -y open-vm-tools
    # Add /mnt/hgfs so the mount works automatically with Vagrant
    mkdir /mnt/hgfs
}

function install_vmware_tools {
    echo "Packer | Installing VMware Tools"
    # Assuming the following packages are installed
    # apt-get install -y linux-headers-$(uname -r) build-essential perl

    cd /tmp
    mkdir -p /mnt/cdrom
    mount -o loop /home/${SSH_USERNAME}/linux.iso /mnt/cdrom

    VMWARE_TOOLS_PATH=$(ls /mnt/cdrom/VMwareTools-*.tar.gz)
    VMWARE_TOOLS_VERSION=$(echo "${VMWARE_TOOLS_PATH}" | cut -f2 -d'-')
    VMWARE_TOOLS_BUILD=$(echo "${VMWARE_TOOLS_PATH}" | cut -f3 -d'-')
    VMWARE_TOOLS_BUILD=$(basename ${VMWARE_TOOLS_BUILD} .tar.gz)
    echo "==> VMware Tools Path: ${VMWARE_TOOLS_PATH}"
    echo "==> VMWare Tools Version: ${VMWARE_TOOLS_VERSION}"
    echo "==> VMware Tools Build: ${VMWARE_TOOLS_BUILD}"

    tar zxf /mnt/cdrom/VMwareTools-*.tar.gz -C /tmp/
    VMWARE_TOOLS_MAJOR_VERSION=$(echo ${VMWARE_TOOLS_VERSION} | cut -d '.' -f 1)
    if [ "${VMWARE_TOOLS_MAJOR_VERSION}" -lt "10" ]; then
        /tmp/vmware-tools-distrib/vmware-install.pl -d
    else
        /tmp/vmware-tools-distrib/vmware-install.pl -f
    fi

    rm /home/${SSH_USERNAME}/linux.iso
    umount /mnt/cdrom
    rmdir /mnt/cdrom
    rm -rf /tmp/VMwareTools-*

    VMWARE_TOOLBOX_CMD_VERSION=$(vmware-toolbox-cmd -v)
    echo "Packer | Installed VMware Tools ${VMWARE_TOOLBOX_CMD_VERSION}"
}

if [[ $PACKER_BUILDER_TYPE =~ vmware ]]; then
    echo "Packer | Installing VMware Tools"
    cat /etc/redhat-release
    if grep -q -i "release 6" /etc/redhat-release ; then
        # Uninstall fuse to fake out the vmware install so it won't try to
        # enable the VMware blocking filesystem
        yum erase -y fuse
    fi
    # Assume that we've installed all the prerequisites:
    # kernel-headers-$(uname -r) kernel-devel-$(uname -r) gcc make perl
    # from the install media via ks.cfg

    # On RHEL 5, add /sbin to PATH because vagrant does a probe for
    # vmhgfs with lsmod sans PATH
    if grep -q -i "release 5" /etc/redhat-release ; then
        echo "export PATH=$PATH:/usr/sbin:/sbin" >> $SSH_USER_HOME/.bashrc
    fi

    KERNEL_VERSION="$(uname -r)"
    KERNEL_MAJOR_VERSION="${KERNEL_VERSION%%.*}"
    KERNEL_MINOR_VERSION_START="${KERNEL_VERSION#*.}"
    KERNEL_MINOR_VERSION="${KERNEL_MINOR_VERSION_START%%.*}"
    echo "Kernel version ${KERNEL_MAJOR_VERSION}.${KERNEL_MINOR_VERSION}"
    if [ "${KERNEL_MAJOR_VERSION}" -ge "4" ] && [ "${KERNEL_MINOR_VERSION}" -ge "1" ]; then
      install_open_vm_tools
    else
      install_vmware_tools
    fi

    echo "Packer | Removing packages needed for building guest tools"
    yum -y remove gcc cpp libmpc mpfr kernel-devel kernel-headers
fi

if [[ $PACKER_BUILDER_TYPE =~ virtualbox ]]; then
    echo "Packer | Installing VirtualBox guest additions"
    # Assume that we've installed all the prerequisites:
    # kernel-headers-$(uname -r) kernel-devel-$(uname -r) gcc make perl
    # from the install media via ks.cfg

    VBOX_VERSION=$(cat $SSH_USER_HOME/.vbox_version)
    mount -o loop $SSH_USER_HOME/VBoxGuestAdditions_$VBOX_VERSION.iso /mnt
    sh /mnt/VBoxLinuxAdditions.run --nox11
    umount /mnt
    rm -rf $SSH_USER_HOME/VBoxGuestAdditions_$VBOX_VERSION.iso
    rm -f $SSH_USER_HOME/.vbox_version

    if [[ $VBOX_VERSION = "4.3.10" ]]; then
        ln -s /opt/VBoxGuestAdditions-4.3.10/lib/VBoxGuestAdditions /usr/lib/VBoxGuestAdditions
    fi

    echo "Packer | Removing packages needed for building guest tools"
    yum -y remove gcc libmpc mpfr kernel-devel kernel-headers
    if grep -v -q -i "release 5" /etc/redhat-release ; then
        yum -y remove cpp perl
    fi
fi
