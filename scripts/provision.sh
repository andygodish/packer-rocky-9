#!/usr/bin/env bash
set -euo pipefail

dnf upgrade --refresh -y
install -d -m 0755 /etc/packer-rocky-9
install -m 0644 /tmp/packer-rocky-9-version.txt /etc/packer-rocky-9/version.txt
rm -f /tmp/packer-rocky-9-version.txt

cat > /etc/cloud/cloud.cfg.d/90-proxmox.cfg <<'CLOUD'
#cloud-config
preserve_hostname: false
disable_root: true
ssh_pwauth: false
users:
  - default
growpart:
  mode: auto
  devices: ['/']
  ignore_growroot_disabled: false
resize_rootfs: true
CLOUD

# Datasource and distro defaults are system settings, outside the user-data schema.
cat > /etc/cloud/cloud.cfg.d/91-proxmox-system.cfg <<'SYSTEM'
datasource_list: [NoCloud, ConfigDrive, None]
system_info:
  default_user:
    name: rocky
    lock_passwd: true
    gecos: Rocky Linux
    groups: [wheel]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
SYSTEM

cat > /etc/ssh/sshd_config.d/00-template.conf <<'SSH'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
SSH
restorecon -RF /etc/cloud /etc/ssh/sshd_config.d
sshd -t
cloud-init schema --config-file /etc/cloud/cloud.cfg.d/90-proxmox.cfg
python3 -c 'import yaml; yaml.safe_load(open("/etc/cloud/cloud.cfg.d/91-proxmox-system.cfg"))'
systemctl enable --now qemu-guest-agent sshd chronyd firewalld
systemctl enable cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service

# Verify the base contract before generalizing it.
test "$(getenforce)" = Enforcing
systemctl is-active --quiet qemu-guest-agent sshd chronyd firewalld
chronyc waitsync 12 0.1
chronyc tracking
firewall-cmd --list-all
rpm -q cloud-init cloud-utils-growpart qemu-guest-agent openssh-server chrony firewalld
if rpm -qa --qf '%{NAME}\n' | grep -Eq '^(ipa-server|freeipa-server)(-|$)'; then
  echo 'FreeIPA must not be installed in this reusable base' >&2
  exit 1
fi
test ! -e /etc/ipa/default.conf
dnf check
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
df -h /
