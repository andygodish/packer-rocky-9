# Rocky Linux 9 Packer Template

Builds a pinned Rocky Linux 9 OS template for Proxmox using Packer.

This project follows `packer-ubuntu-2604`: it owns template build inputs and the
Proxmox template artifact. Long-lived VM deployment belongs in `tofu-proxmox`.
FreeIPA installation and its hostname, realm, DNS and static IP decisions happen
only after cloning. This project creates no identity server or user directory.

## Runtime Contract

| Requirement | Value |
| --- | --- |
| Builder | Packer `proxmox-iso`, Kickstart |
| Rocky ISO | `Rocky-9.8-x86_64-minimal.iso` |
| ISO checksum | `sha256:d338032cd1cdd41c67139f2f71b4c832c8e4a21943106519db9c7137df7a63d4` |
| Proxmox artifact | VM template |
| Template name | `rocky-9-template` |
| Template disk | `40G` raw on `local-lvm` |
| Template memory | `4096` MB, ballooning disabled |
| Template CPU | `2` cores, `host` CPU type |
| Firmware / machine | UEFI with enrolled Secure Boot keys / q35 |
| Network | VirtIO on `vmbr0`, temporary DHCP |
| Cloud-init | NoCloud/ConfigDrive, drive on `local-lvm` |
| Clone initialization | Unique machine ID and SSH host keys; root partition/filesystem growth |
| Swap | 4 GB partition |
| Default guest login | `rocky`, locked password; supply SSH keys when cloning |
| Time | chrony, UTC; synchronization checked during build |
| Security | SELinux enforcing, firewalld active, SSH only |
| Included tooling | QEMU guest agent, SSH server, cloud-init, basic network tools |

Packer downloads and verifies the installer ISO, serves a generated Kickstart
file from its HTTP server, installs Rocky in a temporary VM, updates and
verifies the OS, generalizes its identity, and converts it to a template.
The minimal ISO supplies the installer; BaseOS and AppStream packages come from
the official Rocky 9 HTTPS repositories. Package versions follow those
repositories at build time. FreeIPA, Docker, Kubernetes and build tools are not
installed in the guest.

The previously downloaded GenericCloud QCOW2 is not used by this ISO builder.
There is no fixed VM ID, static IP, domain, DNS resolver or pinned MAC address.
Rebuilding creates another template; it does not replace an existing artifact.
Before cloning by name, keep exactly one intended template with that name.

## Local Configuration

Run from a builder on the Proxmox LAN, as with the Ubuntu project. The installer
must reach Packer's HTTP server, and Packer must reach the guest's SSH service.
The existing Ubuntu build notes identified a VM on this LAN as the reliable
builder location; a NATed development container may not work without routing.

```bash
cp rocky.pkrvars.hcl.example rocky.pkrvars.hcl
# Fill in Proxmox API URL, username, password and node locally.
make validate
make build
```

`rocky.pkrvars.hcl` is ignored. Alternatively omit its password assignment and
supply `PKR_VAR_proxmox_password` through your local secret manager. Avoid
placing credentials in command arguments or shell history. Local defaults
allow a self-signed Proxmox API certificate; set `proxmox_insecure = false` when
the builder trusts the certificate.

`make validate` creates a local temporary Ed25519 key pair under ignored
`.build/`. Only its public key appears in the served Kickstart file. Packer
uses the private key to connect as `rocky`; cleanup removes the authorized key
from the finished guest. No default password or personal SSH key is baked in.
Run `make clean` after building to remove the local key and caches.

## Versioning and Renovate

`version.txt` is the local release source, beginning at `9.8-0`. `upver.yaml`
tracks `rocky_version` in `rocky.pkr.hcl`; the copied release workflow opens
version/changelog PRs and creates Git tags with one leading `v`, such as
`v9.8-0`. The built guest records its version at
`/etc/packer-rocky-9/version.txt`.

`renovate.json` discovers minimal ISO releases in the official Rocky 9 index.
It updates the HCL version pin and README ISO row, allows minor releases within
Rocky 9, and does not automerge or switch to Rocky 10. As in the Ubuntu project,
checksums need a manual update when the ISO version changes. Follow
[the checksum procedure](docs/rocky-iso-checksum.md) before building a Renovate
update. Keep local version/checksum overrides unset so they cannot shadow a
new pin. ISO URLs may move to Rocky's vault when older media is retired.

```bash
make renovate-validate
make renovate-dry-run
make test
make fmt
```

The CI workflow validates using example API values; it never builds a VM.
`make test` aliases Packer validation. A real build and clone smoke test still
need to be run manually on the homelab. See
[build and clone checks](docs/proxmox-packer-build-notes.md).

## Cloning and FreeIPA

Use a full clone through `tofu-proxmox`. Supply a unique hostname and your SSH
public keys through Proxmox cloud-init; there is no password-based fallback.
Keep an initial `freeipa-01` clone powered off until you decide its DNS domain,
FQDN, static address, subnet/gateway, resolvers, Kerberos realm and whether
FreeIPA manages DNS. Avoid `.local`.

Keep SELinux enforcing and the firewall enabled when installing FreeIPA from
Rocky packages on the clone. Do not run `ipa-server-install` in this project.
Keycloak/UniFi integrations, replicas, application backups and restore testing
remain later work. Proxmox VM backups remain useful alongside FreeIPA-aware
backups after installation.
