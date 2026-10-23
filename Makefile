PACKER         ?= packer
PACKER_FILE    := rocky.pkr.hcl
PKRVARS_FILE   ?= rocky.pkrvars.hcl
TEMPLATE_NAME  := rocky-9-template
ROCKY_VERSION  := $(shell sed -n '/variable "rocky_version"/,/}/{s/^[[:space:]]*default[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/p;}' $(PACKER_FILE) | head -n 1 | tr -d '\n\r ')
VERSION_TAG    := $(shell [ -s version.txt ] && printf 'v%s\n' $$(tr -d '[:space:]' < version.txt | sed 's/^v//') || echo latest)
RENOVATE_IMAGE ?= renovate/renovate:latest
REPO_ROOT      := $(CURDIR)

.DEFAULT_GOAL := help
.PHONY: verify-env verify-packer prepare-key init validate build test fmt clean cleanup-build-vm renovate-validate renovate-dry-run help

verify-env:
	@test -s version.txt || { echo "Error: version.txt missing."; exit 1; }
	@test -f "$(PKRVARS_FILE)" || { echo "Copy rocky.pkrvars.hcl.example to $(PKRVARS_FILE) and fill in local values."; exit 1; }

verify-packer:
	@command -v "$(PACKER)" >/dev/null 2>&1 || { echo "Install Packer first."; exit 1; }

# Generated locally, ignored by Git, removed from the finished guest. The HTTP
# server receives only the public key through a rendered Kickstart file.
prepare-key:
	@mkdir -p .build
	@chmod 700 .build
	@if [ ! -f .build/ssh_key ]; then \
		umask 077; ssh-keygen -q -t ed25519 -N '' -C packer-rocky-9-build -f .build/ssh_key; \
	fi
	@test -s .build/ssh_key.pub || { echo "Missing build public key; run make clean and retry."; exit 1; }

init: verify-packer
	$(PACKER) init $(PACKER_FILE)

validate: verify-env prepare-key init
	$(PACKER) validate -var-file="$(PKRVARS_FILE)" $(PACKER_FILE)

build: verify-env prepare-key init
	@echo "Building $(TEMPLATE_NAME) from Rocky $(ROCKY_VERSION) ($(VERSION_TAG))"
	$(PACKER) build -var-file="$(PKRVARS_FILE)" $(PACKER_FILE)

# No Proxmox API calls or VM creation during validation.
test: validate

fmt: verify-packer
	$(PACKER) fmt .

renovate-validate:
	docker run --rm -v "$(REPO_ROOT):/usr/src/app" -w /usr/src/app $(RENOVATE_IMAGE) renovate-config-validator

renovate-dry-run:
	docker run --rm -v "$(REPO_ROOT):/usr/src/app" -w /usr/src/app -e LOG_LEVEL=debug $(RENOVATE_IMAGE) renovate --platform=local --dry-run=lookup --onboarding=false --require-config=optional

cleanup-build-vm:
	@echo "Packer requests the next available Proxmox VM ID; no fixed ID is reserved."
	@echo "Inspect a failed build's VM ID before manually running on the Proxmox node:"
	@echo "  qm stop <vmid>"
	@echo "  qm destroy <vmid> --purge"

clean:
	rm -rf .build packer_cache output-* downloaded_iso_path

help:
	@echo "Rocky Linux 9 Proxmox template ($(TEMPLATE_NAME))"
	@echo "  make init              Install Packer plugins"
	@echo "  make validate          Prepare build key and validate configuration"
	@echo "  make build             Build and upload the Proxmox template"
	@echo "  make test              Alias for validate"
	@echo "  make fmt               Format Packer HCL"
	@echo "  make renovate-validate Validate Renovate configuration"
	@echo "  make renovate-dry-run  Run Renovate release lookup locally"
	@echo "  make cleanup-build-vm  Print manual cleanup guidance"
	@echo "  make clean             Remove local build keys and caches"
