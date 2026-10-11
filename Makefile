# Backpack Live
# USE_DOCKER=1 (default) runs live-build inside a privileged debian:trixie container.
USE_DOCKER ?= 1
DOCKER     ?= docker
IMAGE      ?= backpack-build
ISO        := build/backpack.iso
DEV        ?=
SIZE       ?= 5G
LB_RUN      = $(if $(filter 1,$(USE_DOCKER)),$(DOCKER) run --rm --privileged -v $(CURDIR):/work -w /work/live $(IMAGE),cd live && sudo)

.PHONY: all check-manifest manifest fetch docker-image build clean distclean \
        test-bios test-uefi test-persist test-usb-img mkusb mkusb-gui release check-tools touch-deb test-touch

all: build

check-manifest:
	python3 scripts/gen-package-list.py --check

manifest: check-manifest
	python3 scripts/gen-package-list.py
	mkdir -p live/config/includes.chroot/etc/backpack
	cp manifest/tools.yaml live/config/includes.chroot/etc/backpack/tools.yaml
	mkdir -p live/config/includes.chroot/usr/local/lib/backpack
	cp scripts/gen-package-list.py scripts/check-tools.sh live/config/includes.chroot/usr/local/lib/backpack/

fetch:
	scripts/fetch-upstream.sh

docker-image:
	$(if $(filter 1,$(USE_DOCKER)),$(DOCKER) build -t $(IMAGE) .,@true)

touch-deb:
	scripts/build-touchmode-deb.sh

build: manifest fetch touch-deb docker-image
	mkdir -p build/logs
	$(LB_RUN) lb config 2>&1 | tail -n 5
	$(LB_RUN) lb build > build/logs/build.log 2>&1 || { tail -n 40 build/logs/build.log; exit 1; }
	cp live/live-image-amd64.hybrid.iso $(ISO)
	ls -l $(ISO)

clean:
	$(LB_RUN) lb clean 2>/dev/null || true
	rm -f live/config/binary live/config/bootstrap live/config/chroot live/config/common live/config/source
	rm -rf live/.build

distclean: clean
	$(LB_RUN) lb clean --purge 2>/dev/null || true
	rm -rf build/

test-bios:
	scripts/test-qemu.sh --headless

test-uefi:
	scripts/test-qemu.sh --headless --uefi

test-usb-img:
	scripts/mkusb.sh --image build/test-usb.img --size $(SIZE) --yes

test-persist:
	scripts/test-persist.sh

test-touch:
	scripts/test-qemu.sh --headless --touch --direct --append "backpack.ui=touch backpack.demo=fping" --tag touch --keep-alive 20

mkusb:
	@test -n "$(DEV)" || { echo "usage: make mkusb DEV=/dev/sdX [SIZE=5G] [KEEP=1]"; exit 1; }
	sudo scripts/mkusb.sh --size $(SIZE) $(if $(KEEP),--keep-persistence) $(DEV)

mkusb-gui:
	scripts/mkusb-gui.py

check-tools:
	scripts/check-tools.sh manifest/tools.yaml

release:
	scripts/release.sh


ventoy: ## build the Ventoy deliverable (ISO + auto_memdisk ventoy.json + README)
	scripts/make-ventoy-iso.sh
