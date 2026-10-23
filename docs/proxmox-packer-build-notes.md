# Proxmox Packer build and clone checks

This is a new builder; these are checks to run, not a record of a successful
homelab build. Validation alone does not exercise the installer or hypervisor.

## Before building

Use Packer on a machine reachable from the Proxmox LAN. During installation,
the guest needs outbound DNS/HTTPS and access to the HTTP port Packer advertises
in `inst.ks=http://.../ks.cfg`. Packer needs API access to Proxmox and SSH access
to the DHCP-addressed guest. Verify `local` supports ISO content and `local-lvm`
has room for a 40 GB disk, EFI state and cloud-init media.

The firmware is UEFI. The boot command selects the first GRUB menu entry,
edits its kernel line, appends DHCP and the Kickstart URL, and boots with
Ctrl-X. If an ISO release changes the GRUB layout, inspect the console before
adjusting those keystrokes. The Kickstart is specifically for the single SCSI
OS disk (`sda`) in the Packer build VM.

If SSH discovery times out, inspect the Proxmox console and installer logs:

```bash
cat /proc/cmdline
ip -br addr
ip route
tail -80 /tmp/anaconda.log
tail -80 /tmp/packaging.log
```

Confirm the advertised HTTP URL is reachable from the installer. The HTTP
server serves only the rendered Kickstart public key, never the private key,
API credentials or the repository directory.

## Before conversion

The provisioner checks SELinux enforcing, required services, synchronized
chrony, SSH syntax, cloud-init schema, RPM dependencies, and absence of
FreeIPA. Cloud-init is disabled only for the installer boot to avoid racing
Packer; cleanup removes that marker before conversion. Cleanup resets machine
ID, removes SSH host/build keys and installer network profiles, and cleans
cloud-init state. Packer then shuts down and converts the VM without another
boot.

A kernel update can require a reboot. The clone's first boot loads the updated
kernel; the provisioner does not reboot after generalization.

## Clone smoke test

After building, create a disposable full clone using Proxmox or the lifecycle
repo. Supply SSH public keys and temporary DHCP through cloud-init. Increase
its disk above 40 GB before boot to exercise filesystem growth. In the clone:

```bash
cat /etc/rocky-release
cat /etc/packer-rocky-9/version.txt
cloud-init status --long
hostnamectl
cat /etc/machine-id
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
sudo lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
sudo df -h /
sudo getenforce
sudo systemctl is-active qemu-guest-agent sshd chronyd firewalld
sudo chronyc tracking
sudo firewall-cmd --list-all
```

Confirm the root partition is the final partition and grows to use the added
disk space. Confirm a second disposable clone gets different machine and SSH
host keys. Check that password-based SSH is disabled and the temporary build
key is absent from `/home/rocky/.ssh/authorized_keys`. Confirm guest-agent
address discovery from Proxmox. Do this with disposable clones before the
identity server's final network design. A test clone is not a FreeIPA replica.

## Failed build cleanup

Packer normally removes failed temporary VMs. If interrupted, inspect its
output and the Proxmox VM list before manually deleting only the failed build
VM. `make cleanup-build-vm` prints the relevant commands; it never deletes
infrastructure. Do not reuse VM ID 107 without checking whether the earlier
manual attempt created it. The unused downloaded QCOW2 and old manual scripts
on the node are outside this project's build path.

References:

- [Packer Proxmox ISO builder](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/iso)
- [RHEL 9 Kickstart reference](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/automatically_installing_rhel/kickstart-commands-and-options-reference_rhel-installer)
