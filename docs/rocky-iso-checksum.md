# Updating the Rocky ISO pin

Renovate updates the Rocky version and README ISO row, not the checksum.
Obtain the matching published checksum before building:

```bash
curl --fail --location \
  https://dl.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.8-x86_64-minimal.iso.CHECKSUM
```

For another release, substitute that version in the filename. Read the exact
`SHA256 (Rocky-VERSION-x86_64-minimal.iso) = HASH` line. Update
`rocky_iso_checksum` in `rocky.pkr.hcl`, the README checksum row and the commented
example override. Use `sha256:HASH`. Packer verifies the ISO against this pin.
Run `make validate` afterward.

The initial 9.8 checksum is:

```text
d338032cd1cdd41c67139f2f71b4c832c8e4a21943106519db9c7137df7a63d4
```

Sources:

- [Official Rocky 9 ISO directory](https://dl.rockylinux.org/pub/rocky/9/isos/x86_64/)
- [Rocky 9.8 minimal ISO checksum](https://dl.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.8-x86_64-minimal.iso.CHECKSUM)

The build pins the HTTPS-published SHA256. Detached-signature verification is
not automated in this project.
