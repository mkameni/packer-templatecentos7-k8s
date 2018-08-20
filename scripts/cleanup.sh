#!/usr/bin/env bash
set -x
echo "Packer | Cleanup..."
yum -y erase gtk2 libX11 hicolor-icon-theme avahi freetype bitstream-vera-fonts
rpm --rebuilddb
yum -y clean all

echo "Packer | Free disk..."
dd if=/dev/zero of=/EMPTY bs=1M
rm -f /EMPTY

journalctl --vacuum-time=1seconds
history -c && history -w
