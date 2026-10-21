# Backpack Live
# USE_DOCKER=1 (default) runs live-build inside a privileged debian:trixie container.
USE_DOCKER ?= 1
DOCKER     ?= docker
IMAGE      ?= backpack-build
# EDITION=normal (default) ships the Network and Data tabs only -> build/backpack.iso;
# EDITION=extras adds the Extra tab's apps (manifest category `extra`) -> build/backpack-extras.iso.
# `make build-all` builds both.
EDITION    ?= normal
# EDEX=1 (default) builds the eDEX-UI deb for the extras edition's Extra tab; EDEX=0 skips it.
# A failed eDEX build only warns: the ISO still builds and the Extra tab lists the other apps.
EDEX       ?= 1
ISO        := build/backpack$(if $(filter extras,$(EDITION)),-extras).iso
ifeq ($(filter $(EDITION),normal extras),)
$(error EDITION must be normal or extras, not "$(EDITION)")
endif
DEV        ?=
SIZE       ?= 5G
LB_RUN      = $(if $(filter 1,$(USE_DOCKER)),$(DOCKER) run --rm --privileged -v $(CURDIR):/work -w /work/live $(IMAGE),cd live && sudo)

.PHONY: all check-manifest manifest fetch docker-image build build-all clean distclean \
        test-bios test-uefi test-persist test-usb-img mkusb mkusb-gui usb-writer usb-writer-app release check-tools touch-deb test-touch ventoy edex-deb

all: build

check-manifest:
	python3 scripts/gen-package-list.py --check

manifest: check-manifest
	mkdir -p live/config/includes.chroot/etc/backpack
	python3 scripts/gen-package-list.py --edition $(EDITION) --manifest-out live/config/includes.chroot/etc/backpack/tools.yaml
	echo $(EDITION) > live/config/includes.chroot/etc/backpack/edition
	mkdir -p live/config/includes.chroot/usr/local/lib/backpack
	cp scripts/gen-package-list.py scripts/check-tools.sh live/config/includes.chroot/usr/local/lib/backpack/

fetch:
	scripts/fetch-upstream.sh

docker-image:
	$(if $(filter 1,$(USE_DOCKER)),$(DOCKER) build -t $(IMAGE) .,@true)

touch-deb:
	scripts/build-touchmode-deb.sh

edex-deb: ## eDEX-UI (Extra tab) -> live/config/packages.chroot/edex-ui_*.deb, in the backpack-edex container
	$(DOCKER) build -t backpack-edex -f tools/docker/Dockerfile.edex tools/docker
	$(DOCKER) run --rm -v $(CURDIR):/work -w /work/touchmode/edex backpack-edex sh /work/scripts/build-edex.sh
	scripts/build-edex-deb.sh

build: manifest fetch touch-deb docker-image
	$(if $(filter extras,$(EDITION)),$(if $(filter 1,$(EDEX)),$(MAKE) edex-deb || echo "WARNING: eDEX-UI was not built; the Extra tab will not list it (EDEX=0 skips this step)"),rm -f live/config/packages.chroot/edex-ui_*.deb)
	@# live-build skips stages it already ran: a build of the other edition starts from a clean tree
	@if [ -d live/.build ] && [ "$$(cat build/.edition 2>/dev/null)" != "$(EDITION)" ]; then \
		echo "edition changed to $(EDITION): make clean first"; $(MAKE) clean; fi
	mkdir -p build/logs
	echo $(EDITION) > build/.edition
	$(LB_RUN) lb config 2>&1 | tail -n 5
	$(LB_RUN) lb build > $(CURDIR)/build/logs/build.log 2>&1 || { tail -n 40 $(CURDIR)/build/logs/build.log; exit 1; }
	cp live/live-image-amd64.hybrid.iso $(ISO)
	ls -l $(ISO)

build-all: ## both editions -> build/backpack.iso + build/backpack-extras.iso
	$(MAKE) build EDITION=normal
	$(MAKE) build EDITION=extras

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

usb-writer: ## package the GUI as .deb + AppImage -> build/dist/ (VERSION=1.2.0 optional)
	scripts/build-usb-writer.sh

usb-writer-app: ## standalone writer (Go + Wails) -> tools/usb-writer/app/build/bin/
	cd tools/usb-writer/app && go run github.com/wailsapp/wails/v2/cmd/wails@v2.12.0 build -skipbindings -tags webkit2_41

check-tools:
	scripts/check-tools.sh manifest/tools.yaml

release:
	EDITION=$(EDITION) scripts/release.sh


ventoy: ## build the Ventoy deliverable (ISO + auto_memdisk ventoy.json + README)
	scripts/make-ventoy-iso.sh
