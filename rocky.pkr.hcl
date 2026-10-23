packer {
  required_version = ">= 1.11.0"
  required_plugins {
    proxmox = {
      version = "~> 1.2"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL"
}

variable "proxmox_username" {
  type        = string
  description = "Proxmox API username"
}

variable "proxmox_password" {
  type        = string
  sensitive   = true
  description = "Proxmox API password; supply locally or through PKR_VAR_proxmox_password"
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node name"
}

variable "proxmox_insecure" {
  type        = bool
  description = "Skip API TLS verification for the homelab's self-signed certificate"
  default     = true
}

# renovate: datasource=custom.rocky-releases depName=rocky-minimal-x86_64 versioning=loose
variable "rocky_version" {
  type        = string
  description = "Rocky Linux 9 minimal installer ISO version"
  default     = "9.8"
  validation {
    condition     = can(regex("^9\\.[0-9]+$", var.rocky_version))
    error_message = "This project builds Rocky Linux 9 only."
  }
}

variable "rocky_iso_checksum" {
  type        = string
  description = "SHA256 checksum for the pinned Rocky minimal installer ISO"
  default     = "sha256:d338032cd1cdd41c67139f2f71b4c832c8e4a21943106519db9c7137df7a63d4"
  validation {
    condition     = can(regex("^sha256:[0-9a-f]{64}$", var.rocky_iso_checksum))
    error_message = "Supply the official ISO SHA256 in sha256:<64 hex digits> format."
  }
}

variable "vm_datastore" {
  type        = string
  description = "Storage for the template disk, EFI variables and cloud-init drive"
  default     = "local-lvm"
}

variable "iso_datastore" {
  type        = string
  description = "Storage supporting ISO content"
  default     = "local"
}

variable "network_bridge" {
  type        = string
  description = "LAN bridge used for temporary DHCP during the build"
  default     = "vmbr0"
}

locals {
  rocky_iso_name = "Rocky-${var.rocky_version}-x86_64-minimal.iso"
  rocky_iso_url  = "https://dl.rockylinux.org/pub/rocky/9/isos/x86_64/${local.rocky_iso_name}"
}

source "proxmox-iso" "rocky" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = var.proxmox_insecure

  vm_name              = "rocky-9-template"
  template_description = "Rocky Linux ${var.rocky_version} minimal OS base; no FreeIPA installation"

  boot_iso {
    iso_url          = local.rocky_iso_url
    iso_checksum     = var.rocky_iso_checksum
    iso_storage_pool = var.iso_datastore
    unmount          = true
  }

  memory   = 4096
  cores    = 2
  sockets  = 1
  cpu_type = "host"
  os       = "l26"
  bios     = "ovmf"
  machine  = "q35"

  efi_config {
    efi_storage_pool  = var.vm_datastore
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  qemu_agent      = true
  scsi_controller = "virtio-scsi-single"
  onboot          = false

  network_adapters {
    model  = "virtio"
    bridge = var.network_bridge
  }

  disks {
    type         = "scsi"
    disk_size    = "40G"
    storage_pool = var.vm_datastore
    format       = "raw"
  }

  cloud_init              = true
  cloud_init_storage_pool = var.vm_datastore

  http_content = {
    "/ks.cfg" = templatefile("${path.root}/http/ks.cfg.pkrtpl", {
      ssh_public_key = trimspace(file("${path.root}/.build/ssh_key.pub"))
    })
  }
  boot_wait         = "10s"
  boot_key_interval = "100ms"
  boot_command = [
    "<up><wait>e<wait>",
    "<down><down><end> inst.text ip=dhcp inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
    "<leftCtrlOn>x<leftCtrlOff>"
  ]

  ssh_username         = "rocky"
  ssh_private_key_file = "${path.root}/.build/ssh_key"
  ssh_timeout          = "45m"
}

build {
  sources = ["source.proxmox-iso.rocky"]

  provisioner "file" {
    source      = "version.txt"
    destination = "/tmp/packer-rocky-9-version.txt"
  }

  provisioner "shell" {
    execute_command = "sudo -n bash '{{ .Path }}'"
    script          = "scripts/provision.sh"
  }

  # Final operation before Packer shuts down and converts the VM to a template.
  provisioner "shell" {
    execute_command = "sudo -n bash '{{ .Path }}'"
    script          = "scripts/cleanup.sh"
  }
}
