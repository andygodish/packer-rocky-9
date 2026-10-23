#!/usr/bin/env bash
set -euo pipefail

dnf clean all
rm -f /etc/cloud/cloud-init.disabled
cloud-init clean --logs --machine-id --seed --configs network

# Remove persistent installer DHCP profiles; cloud-init will create each clone's
# networking. Removing files leaves the current SSH connection usable.
find /etc/NetworkManager/system-connections -maxdepth 1 -type f -delete
find /var/lib/NetworkManager -maxdepth 1 -type f -name '*lease*' -delete
find /etc/ssh -maxdepth 1 -type f -name 'ssh_host_*' -delete
find /root /home -type f \( -name authorized_keys -o -name .bash_history \) -delete
rm -f /root/anaconda-ks.cfg /root/original-ks.cfg /root/ks-post.log
rm -f /var/lib/systemd/random-seed
journalctl --rotate
journalctl --vacuum-time=1s
sync
