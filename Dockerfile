# Build container for Backpack Live (live-build needs a Debian trixie userland; run --privileged).
FROM debian:trixie
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      live-build debootstrap squashfs-tools xorriso dosfstools mtools \
      debian-archive-keyring ca-certificates curl gnupg \
      python3 python3-yaml rsync cpio \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work/live
