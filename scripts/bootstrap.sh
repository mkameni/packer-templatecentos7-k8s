#!/usr/bin/env bash
set -x
sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers
yum -y install gcc make gcc-c++ kernel-devel-`uname -r` perl

echo 'Packer | Applying slow DNS fix...'
if [[ "${PACKER_BUILDER_TYPE}" =~ "virtualbox" ]]; then
  ## https://access.redhat.com/site/solutions/58625 (subscription required)
  # http://www.linuxquestions.org/questions/showthread.php?p=4399340#post4399340
  # add 'single-request-reopen' so it is included when /etc/resolv.conf is generated
  echo 'RES_OPTIONS="single-request-reopen"' >> /etc/sysconfig/network
  service network restart
  echo 'Packer | Slow DNS fix applied (single-request-reopen)'
else
  echo 'Packer | Slow DNS fix not required for this platform, skipping'
fi

echo 'Packer | Configuring sshd_config options...'
echo 'Packer | Turning off sshd DNS lookup to prevent timeout delay'
echo "UseDNS no" >> /etc/ssh/sshd_config
echo 'Packer | Disablng GSSAPI authentication to prevent timeout delay'
echo "GSSAPIAuthentication no" >> /etc/ssh/sshd_config


if [[ $UPDATE  =~ true || $UPDATE =~ 1 || $UPDATE =~ yes ]]; then
    echo "Packer | Applying updates..."
    yum -y update

    # reboot
    echo "Packer | Rebooting the machine..."
    reboot
    sleep 60
fi

echo 'Packer | Configuring settings for vagrant...'

SSH_USER=${SSH_USERNAME:-vagrant}
SSH_USER_HOME=${SSH_USER_HOME:-/home/${SSH_USER}}
VAGRANT_INSECURE_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key"

# Packer passes boolean user variables through as '1', but this might change in
# the future, so also check for 'true'.
if [ "$INSTALL_VAGRANT_KEY" = "true" ] || [ "$INSTALL_VAGRANT_KEY" = "1" ]; then
  # Add vagrant user (if it doesn't already exist)
  if ! id -u $SSH_USER >/dev/null 2>&1; then
      echo '==> Creating ${SSH_USER}'
      /usr/sbin/groupadd $SSH_USER
      /usr/sbin/useradd $SSH_USER -g $SSH_USER -G wheel
      echo '==> Giving ${SSH_USER} sudo powers'
      echo "${SSH_USER}"|passwd --stdin $SSH_USER
      echo "${SSH_USER}        ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers
  fi

  echo 'Packer | Installing Vagrant SSH key...'
  mkdir -pm 700 ${SSH_USER_HOME}/.ssh
  # https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant.pub
  echo "${VAGRANT_INSECURE_KEY}" > $SSH_USER_HOME/.ssh/authorized_keys
  chmod 0600 ${SSH_USER_HOME}/.ssh/authorized_keys
  chown -R ${SSH_USER}:${SSH_USER} ${SSH_USER_HOME}/.ssh
fi

echo "Packer | Set hostname..."
hostnamectl set-hostname templatecentos7-k8s

echo "Packer | Recording box generation date"
date > /etc/vagrant_box_build_date

echo "Packer | Customizing message of the day"
MOTD_FILE=/etc/motd
BANNER_WIDTH=64
PLATFORM_RELEASE=$(sed 's/^.\+ release \([.0-9]\+\).*/\1/' /etc/redhat-release)
PLATFORM_MSG=$(printf 'CentOS %s' "$PLATFORM_RELEASE")
BUILT_MSG=$(printf 'built %s' $(date +%Y-%m-%d))
printf '%0.1s' "-"{1..64} > ${MOTD_FILE}
printf '\n' >> ${MOTD_FILE}
printf '%2s%-30s%30s\n' " " "${PLATFORM_MSG}" "${BUILT_MSG}" >> ${MOTD_FILE}
printf '%0.1s' "-"{1..64} >> ${MOTD_FILE}
printf '\n' >> ${MOTD_FILE}

echo "Packer | Disable SELinux..."
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux

echo "Packer | Disable swap..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

echo "Packer | Enable br_netfilter..."
modprobe br_netfilter
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables
echo '1' > /proc/sys/net/bridge/bridge-nf-call-ip6tables

echo "Packer | Load modules ipvs..."
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4

echo "Packer | Check if the modules ares loaded..."
lsmod | grep -e ip_vs -e nf_conntrack_ipv4
