# syntax=docker/dockerfile:1

FROM node:12-buster as wwwstage

ARG KASMWEB_RELEASE="54b9bac920267e902af3c9dfca4c0f64cff92f41"

RUN \
  echo "**** build clientside ****" && \
  export QT_QPA_PLATFORM=offscreen && \
  export QT_QPA_FONTDIR=/usr/share/fonts && \
  mkdir /src && \
  cd /src && \
  wget https://github.com/kasmtech/noVNC/tarball/${KASMWEB_RELEASE} -O - \
    | tar  --strip-components=1 -xz && \
  npm install && \
  npm run-script build

RUN \
  echo "**** organize output ****" && \
  mkdir /build-out && \
  cd /src && \
  rm -rf node_modules/ && \
  cp -R ./* /build-out/ && \
  cd /build-out && \
  rm *.md && \
  rm AUTHORS && \
  cp index.html vnc.html && \
  mkdir Downloads


FROM ghcr.io/linuxserver/baseimage-ubuntu:jammy as buildstage

ARG KASMVNC_RELEASE="d49d07b88113d28eb183ca7c0ca59990fae1153c"

COPY --from=wwwstage /build-out /www

RUN \
  echo "**** install build deps ****" && \
  apt-get update && \
  apt-get build-dep -y \
    libxfont-dev \
    xorg-server && \
  apt-get install -y \
    autoconf \
    automake \
    cmake \
    git \
    grep \
    libavcodec-dev \
    libdrm-dev \
    libepoxy-dev \
    libgbm-dev \
    libgif-dev \
    libgnutls28-dev \
    libgnutls28-dev \
    libjpeg-dev \
    libjpeg-turbo8-dev \
    libpciaccess-dev \
    libpng-dev \
    libssl-dev \
    libtiff-dev \
    libtool \
    libwebp-dev \
    libx11-dev \
    libxau-dev \
    libxcursor-dev \
    libxcursor-dev \
    libxcvt-dev \
    libxdmcp-dev \
    libxext-dev \
    libxkbfile-dev \
    libxrandr-dev \
    libxrandr-dev \
    libxshmfence-dev \
    libxtst-dev \
    meson \
    nettle-dev \
    tar \
    tightvncserver \
    wget \
    wayland-protocols \
    xinit \
    xserver-xorg-dev

RUN \
  echo "**** build libjpeg-turbo ****" && \
  mkdir /jpeg-turbo && \
  JPEG_TURBO_RELEASE=$(curl -sX GET "https://api.github.com/repos/libjpeg-turbo/libjpeg-turbo/releases/latest" \
  | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  curl -o \
  /tmp/jpeg-turbo.tar.gz -L \
    "https://github.com/libjpeg-turbo/libjpeg-turbo/archive/${JPEG_TURBO_RELEASE}.tar.gz" && \
  tar xf \
  /tmp/jpeg-turbo.tar.gz -C \
    /jpeg-turbo/ --strip-components=1 && \
  cd /jpeg-turbo && \
  MAKEFLAGS=-j`nproc` \
  CFLAGS="-fpic" \
  cmake -DCMAKE_INSTALL_PREFIX=/usr/local -G"Unix Makefiles" && \
  make && \
  make install

RUN \
  echo "**** build kasmvnc ****" && \
  git clone https://github.com/kasmtech/KasmVNC.git src && \
  cd /src && \
  git checkout -f ${KASMVNC_release} && \
  sed -i \
    -e '/find_package(FLTK/s@^@#@' \
    -e '/add_subdirectory(tests/s@^@#@' \
    CMakeLists.txt && \
  cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DBUILD_VIEWER:BOOL=OFF \
    -DENABLE_GNUTLS:BOOL=OFF \
    . && \
  make -j4 && \
  echo "**** build xorg ****" && \
  XORG_VER="1.20.14" && \
  XORG_PATCH=$(echo "$XORG_VER" | grep -Po '^\d.\d+' | sed 's#\.##') && \
  wget --no-check-certificate \
    -O /tmp/xorg-server-${XORG_VER}.tar.gz \
    "https://www.x.org/archive/individual/xserver/xorg-server-${XORG_VER}.tar.gz" && \
  tar --strip-components=1 \
    -C unix/xserver \
    -xf /tmp/xorg-server-${XORG_VER}.tar.gz && \
  cd unix/xserver && \
  patch -Np1 -i ../xserver${XORG_PATCH}.patch && \
  patch -s -p0 < ../CVE-2022-2320-v1.20.patch && \
  autoreconf -i && \
  ./configure --prefix=/opt/kasmweb \
    --with-xkb-path=/usr/share/X11/xkb \
    --with-xkb-output=/var/lib/xkb \
    --with-xkb-bin-directory=/usr/bin \
    --with-default-font-path="/usr/share/fonts/X11/misc,/usr/share/fonts/X11/cyrillic,/usr/share/fonts/X11/100dpi/:unscaled,/usr/share/fonts/X11/75dpi/:unscaled,/usr/share/fonts/X11/Type1,/usr/share/fonts/X11/100dpi,/usr/share/fonts/X11/75dpi,built-ins" \
    --with-sha1=libcrypto \
    --without-dtrace --disable-dri \
    --disable-static \
    --disable-xinerama \
    --disable-xvfb \
    --disable-xnest \
    --disable-xorg \
    --disable-dmx \
    --disable-xwin \
    --disable-xephyr \
    --disable-kdrive \
    --disable-config-hal \
    --disable-config-udev \
    --disable-dri2 \
    --enable-glx \
    --disable-xwayland \
    --enable-dri3 && \
  find . -name "Makefile" -exec sed -i 's/-Werror=array-bounds//g' {} \; && \
  make -j4

RUN \
  echo "**** generate final output ****" && \
  cd /src && \
  mkdir -p xorg.build/bin && \
  cd xorg.build/bin/ && \
  ln -s /src/unix/xserver/hw/vnc/Xvnc Xvnc && \
  cd .. && \
  mkdir -p man/man1 && \
  touch man/man1/Xserver.1 && \
  cp /src/unix/xserver/hw/vnc/Xvnc.man man/man1/Xvnc.1 && \
  mkdir lib && \
  cd lib && \
  ln -s /usr/lib/x86_64-linux-gnu/dri dri && \
  cd /src && \
  mkdir -p builder/www && \
  cp -ax /www/* builder/www/ && \
  cp builder/www/index.html builder/www/vnc.html && \
  make servertarball && \
  mkdir /build-out && \
  tar xzf \
    kasmvnc-Linux*.tar.gz \
    -C /build-out/ && \
  rm -Rf /build-out/usr/local/man

# nodejs builder
FROM ghcr.io/linuxserver/baseimage-ubuntu:jammy as nodebuilder
ARG KCLIENT_RELEASE

RUN \
  echo "**** install build deps ****" && \
  apt-get update && \
  apt-get install -y \
    gnupg && \
  curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
  echo 'deb https://deb.nodesource.com/node_18.x jammy main' \
    > /etc/apt/sources.list.d/nodesource.list && \
  apt-get update && \
  apt-get install -y \
    g++ \
    gcc \
    libpam0g-dev \
    libpulse-dev \
    make \
    nodejs
	
RUN \
  echo "**** grab source ****" && \
  mkdir -p /kclient && \
  if [ -z ${KCLIENT_RELEASE+x} ]; then \
    KCLIENT_RELEASE=$(curl -sX GET "https://api.github.com/repos/linuxserver/kclient/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  fi && \
  curl -o \
  /tmp/kclient.tar.gz -L \
    "https://github.com/linuxserver/kclient/archive/${KCLIENT_RELEASE}.tar.gz" && \
  tar xf \
  /tmp/kclient.tar.gz -C \
    /kclient/ --strip-components=1

RUN \
  echo "**** install node modules ****" && \
  cd /kclient && \
  npm install && \
  rm -f package-lock.json

FROM alpine:3.17 as rootfs-stage

# environment
ENV REL=jammy
ENV ARCH=amd64

# install packages
RUN \
  apk add --no-cache \
    bash \
    curl \
    tzdata \
    xz

# grab base tarball
RUN \
  mkdir /root-out && \
  curl -o \
    /rootfs.tar.gz -L \
    https://partner-images.canonical.com/core/${REL}/current/ubuntu-${REL}-core-cloudimg-${ARCH}-root.tar.gz && \
  tar xf \
    /rootfs.tar.gz -C \
    /root-out && \
  rm -rf \
    /root-out/var/log/*

# set version for s6 overlay
ARG S6_OVERLAY_VERSION="3.1.6.2"
ARG S6_OVERLAY_ARCH="x86_64"

# add s6 overlay
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz

# add s6 optional symlinks
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-symlinks-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-arch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-symlinks-arch.tar.xz

# Runtime stage
FROM scratch
# Make all NVIDIA GPUs visible by default
ARG NVIDIA_VISIBLE_DEVICES=all
# Use noninteractive mode to skip confirmation when installing packages
ARG DEBIAN_FRONTEND=noninteractive
# All NVIDIA driver capabilities should preferably be used, check `NVIDIA_DRIVER_CAPABILITIES` inside the container if things do not work
ENV NVIDIA_DRIVER_CAPABILITIES all
# Enable AppImage execution in a container
ENV APPIMAGE_EXTRACT_AND_RUN 1
# System defaults that should not be changed
ENV DISPLAY :0
ENV XDG_RUNTIME_DIR /tmp/runtime-user
ENV PULSE_SERVER unix:/run/pulse/native
ENV LD_LIBRARY_PATH /usr/lib/x86_64-linux-gnu:/usr/lib/i386-linux-gnu${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}


COPY --from=rootfs-stage /root-out/ /
ARG BUILD_DATE
ARG VERSION
ARG MODS_VERSION="v3"
ARG PKG_INST_VERSION="v1"
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="TheLamer"

ADD --chmod=744 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/docker-mods.${MODS_VERSION}" "/docker-mods"
ADD --chmod=744 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/package-install.${PKG_INST_VERSION}" "/etc/s6-overlay/s6-rc.d/init-mods-package-install/run"

# set environment variables
ARG DEBIAN_FRONTEND="noninteractive"
ENV HOME="/root" \
  LANGUAGE="en_US.UTF-8" \
  LANG="en_US.UTF-8" \
  TERM="xterm" \
  S6_CMD_WAIT_FOR_SERVICES_MAXTIME="0" \
  S6_VERBOSITY=1 \
  S6_STAGE2_HOOK=/docker-mods \
  VIRTUAL_ENV=/lsiopy \
  PATH="/lsiopy/bin:$PATH"

# copy sources
COPY sources.list /etc/apt/

RUN \
  echo "**** Ripped from Ubuntu Docker Logic ****" && \
  set -xe && \
  echo '#!/bin/sh' \
    > /usr/sbin/policy-rc.d && \
  echo 'exit 101' \
    >> /usr/sbin/policy-rc.d && \
  chmod +x \
    /usr/sbin/policy-rc.d && \
  dpkg-divert --local --rename --add /sbin/initctl && \
  cp -a \
    /usr/sbin/policy-rc.d \
    /sbin/initctl && \
  sed -i \
    's/^exit.*/exit 0/' \
    /sbin/initctl && \
  echo 'force-unsafe-io' \
    > /etc/dpkg/dpkg.cfg.d/docker-apt-speedup && \
  echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
    > /etc/apt/apt.conf.d/docker-clean && \
  echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
    >> /etc/apt/apt.conf.d/docker-clean && \
  echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' \
    >> /etc/apt/apt.conf.d/docker-clean && \
  echo 'Acquire::Languages "none";' \
    > /etc/apt/apt.conf.d/docker-no-languages && \
  echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' \
    > /etc/apt/apt.conf.d/docker-gzip-indexes && \
  echo 'Apt::AutoRemove::SuggestsImportant "false";' \
    > /etc/apt/apt.conf.d/docker-autoremove-suggests && \
  mkdir -p /run/systemd && \
  echo 'docker' \
    > /run/systemd/container && \
  echo "**** install apt-utils and locales ****" && \
  apt-get update && \
  apt-get upgrade -y && \
  apt-get install -y \
    apt-utils \
    locales && \
  echo "**** install packages ****" && \
  apt-get install -y \
    cron \
    curl \
    gnupg \
    jq \
    netcat \
    tzdata && \
  echo "**** generate locale ****" && \
  locale-gen en_US.UTF-8 && \
  mkdir -p \
    /app \
    /config \
    /defaults \
    /lsiopy && \
  echo "**** cleanup ****" && \
  apt-get autoremove && \
  apt-get clean && \
  rm -rf \
    /tmp/* \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /var/log/*

# set version label
ARG BUILD_DATE
ARG VERSION
ARG KASMBINS_RELEASE="1.15.0"
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"
LABEL "com.kasmweb.image"="true"

# env
ENV DISPLAY=:1 \
    PERL5LIB=/usr/local/bin \
    OMP_WAIT_POLICY=PASSIVE \
    GOMP_SPINCOUNT=0 \
    START_DOCKER=true \
    PULSE_RUNTIME_PATH=/defaults \
    NVIDIA_DRIVER_CAPABILITIES=all

# copy over build output
COPY --from=nodebuilder /kclient /kclient
COPY --from=buildstage /build-out/ /

RUN \
  echo "**** enable locales ****" && \
  sed -i \
    '/locale/d' \
    /etc/dpkg/dpkg.cfg.d/excludes && \
  echo "**** install deps ****" && \
  apt-get update && \
  apt-get install -y \
    gnupg && \
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
  echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu jammy stable" > \
    /etc/apt/sources.list.d/docker.list && \
  curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
  echo 'deb https://deb.nodesource.com/node_18.x jammy main' \
    > /etc/apt/sources.list.d/nodesource.list && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    ca-certificates \
    containerd.io \
    cups \
    cups-client \
    cups-pdf \
    docker-ce \
    docker-ce-cli \
    docker-compose-plugin \
    dbus-x11 \
    ffmpeg \
    file \
    fonts-noto-color-emoji \
    fonts-noto-core \
    fuse-overlayfs \
    intel-media-va-driver \
    libdatetime-perl \
    libfontenc1 \
    libfreetype6 \
    libgbm1 \
    libgcrypt20 \
    libgl1-mesa-dri \
    libglu1-mesa \
    libgnutls30 \
    libgomp1 \
    libhash-merge-simple-perl \
    libjpeg-turbo8 \
    liblist-moreutils-perl \
    libp11-kit0 \
    libpam0g \
    libpixman-1-0 \
    libscalar-list-utils-perl \
    libswitch-perl \
    libtasn1-6 \
    libtry-tiny-perl \
    libwebp7 \
    libx11-6 \
    libxau6 \
    libxcb1 \
    libxcursor1 \
    libxdmcp6 \
    libxext6 \
    libxfixes3 \
    libxfont2 \
    libxinerama1 \
    libxshmfence1 \
    libxtst6 \
    libyaml-tiny-perl \
    locales-all \
    mesa-va-drivers \
    nginx \
    nodejs \
    openbox \
    openssh-client \
    openssl \
    pciutils \
    perl \
    procps \
    pulseaudio \
    pulseaudio-utils \
    python3 \
    software-properties-common \
    ssl-cert \
    sudo \
    tar \
    util-linux \
    x11-apps \
    x11-common \
    x11-utils \
    x11-xkb-utils \
    x11-xkb-utils \
    x11-xserver-utils \
    xauth \
    xdg-utils \
    xfonts-base \
    xkb-data \
    xserver-common \
    xserver-xorg-core \
    xserver-xorg-video-amdgpu \
    xserver-xorg-video-ati \
    xserver-xorg-video-intel \
    xserver-xorg-video-nouveau \
    xserver-xorg-video-qxl \
    xterm \
    xutils \
    zlib1g && \
  echo "**** printer config ****" && \
  sed -i -r \
    -e "s:^(Out\s).*:\1/config/PDF:" \
    /etc/cups/cups-pdf.conf && \
  echo "**** filesystem setup ****" && \
  ln -s /usr/local/share/kasmvnc /usr/share/kasmvnc && \
  ln -s /usr/local/etc/kasmvnc /etc/kasmvnc && \
  ln -s /usr/local/lib/kasmvnc /usr/lib/kasmvncserver && \
  echo "**** openbox tweaks ****" && \
  sed -i \
    -e 's/NLIMC/NLMC/g' \
    -e '/debian-menu/d' \
    -e 's|</applications>|  <application class="*"><maximized>yes</maximized></application>\n</applications>|' \
    -e 's|</keyboard>|  <keybind key="C-S-d"><action name="ToggleDecorations"/></keybind>\n</keyboard>|' \
    /etc/xdg/openbox/rc.xml && \
  echo "**** user perms ****" && \
  sed -e 's/%sudo	ALL=(ALL:ALL) ALL/%sudo ALL=(ALL:ALL) NOPASSWD: ALL/g' \
    -i /etc/sudoers && \
  echo "**** kasm support ****" && \
  mkdir -p /var/run/pulse && \
  chown root:root /var/run/pulse && \
  mkdir -p /kasmbins && \
  curl -s https://kasm-ci.s3.amazonaws.com/kasmbins-amd64-${KASMBINS_RELEASE}.tar.gz \
    | tar xzvf - -C /kasmbins/ && \
  chmod +x /kasmbins/* && \
  chown -R root:root /kasmbins && \
  chown root:root /usr/share/kasmvnc/www/Downloads && \
  echo "**** dind support ****" && \
  useradd -U dockremap && \
  usermod -G dockremap dockremap && \
  echo 'dockremap:165536:65536' >> /etc/subuid && \
  echo 'dockremap:165536:65536' >> /etc/subgid && \
  curl -o \
  /usr/local/bin/dind -L \
    https://raw.githubusercontent.com/moby/moby/master/hack/dind && \
  chmod +x /usr/local/bin/dind && \
  echo 'hosts: files dns' > /etc/nsswitch.conf && \
  echo "**** locales ****" && \
  for LOCALE in $(curl -sL https://raw.githubusercontent.com/thelamer/lang-stash/master/langs); do \
    localedef -i $LOCALE -f UTF-8 $LOCALE.UTF-8; \
  done && \
  echo "**** theme ****" && \
  curl -s https://raw.githubusercontent.com/thelamer/lang-stash/master/theme.tar.gz \
    | tar xzvf - -C /usr/share/themes/Clearlooks/openbox-3/ && \
  echo "**** cleanup ****" && \
  apt-get autoclean && \
  rm -rf \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/*


# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"
ARG DEBIAN_FRONTEND="noninteractive"

# title
ENV TITLE="Ubuntu KDE"

# Install locales to prevent X11 errors
RUN apt-get clean && \
    apt-get update && apt-get install -y locales && \
    rm -rf /var/lib/apt/lists/* && \
    locale-gen en_US.UTF-8

ENV TZ UTC
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y \
    software-properties-common \
    alsa-base \
    alsa-utils \
    apt-transport-https \
    apt-utils \
    build-essential \
    ca-certificates \
    cups-filters \
    cups-common \
    cups-pdf \
    curl \
    file \
    wget \
    bzip2 \
    gzip \
    p7zip-full \
    xz-utils \
    zip \
    unzip \
    zstd \
    gcc \
    git \
    jq \
    make \
    python3 \
    python3-cups \
    python3-numpy \
    python3-pip \
    mlocate \
    nano \
    vim \
    htop \
    fonts-dejavu-core \
    fonts-freefont-ttf \
    fonts-noto \
    fonts-noto-cjk \
    fonts-noto-cjk-extra \
    fonts-noto-color-emoji \
    fonts-noto-hinted \
    fonts-noto-mono \
    fonts-opensymbol \
    fonts-symbola \
    fonts-ubuntu \
    libpulse0 \
    pulseaudio \
    supervisor \
    net-tools \
    libglvnd-dev \
    libglvnd-dev:i386 \
    libgl1-mesa-dev \
    libgl1-mesa-dev:i386 \
    libegl1-mesa-dev \
    libegl1-mesa-dev:i386 \
    libgles2-mesa-dev \
    libgles2-mesa-dev:i386 \
    libglvnd0 \
    libglvnd0:i386 \
    libgl1 \
    libgl1:i386 \
    libglx0 \
    libglx0:i386 \
    libegl1 \
    libegl1:i386 \
    libgles2 \
    libgles2:i386 \
    libglu1 \
    libglu1:i386 \
    libsm6 \
    libsm6:i386 \
    vainfo \
    vdpauinfo \
    pkg-config \
    mesa-utils \
    mesa-utils-extra \
    va-driver-all \
    xserver-xorg-input-all \
    xserver-xorg-video-all \
    mesa-vulkan-drivers \
    libvulkan-dev \
    libvulkan-dev:i386 \
    libxau6 \
    libxau6:i386 \
    libxdmcp6 \
    libxdmcp6:i386 \
    libxcb1 \
    libxcb1:i386 \
    libxext6 \
    libxext6:i386 \
    libx11-6 \
    libx11-6:i386 \
    libxv1 \
    libxv1:i386 \
    libxtst6 \
    libxtst6:i386 \
    xdg-utils \
    dbus-x11 \
    libdbus-c++-1-0v5 \
    xkb-data \
    x11-xkb-utils \
    x11-xserver-utils \
    x11-utils \
    x11-apps \
    xauth \
    xbitmaps \
    xinit \
    xfonts-base \
    libxrandr-dev \
    vulkan-tools && \
    rm -rf /var/lib/apt/lists/* && \
    # Configure EGL manually
    mkdir -p /usr/share/glvnd/egl_vendor.d/ && \
    echo "{\n\
    \"file_format_version\" : \"1.0.0\",\n\
    \"ICD\": {\n\
    \"library_path\": \"libEGL_nvidia.so.0\"\n\
    }\n\
    }" > /usr/share/glvnd/egl_vendor.d/10_nvidia.json

# Configure Vulkan manually
RUN VULKAN_API_VERSION=$(dpkg -s libvulkan1 | grep -oP 'Version: [0-9|\.]+' | grep -oP '[0-9]+(\.[0-9]+)(\.[0-9]+)') && \
    mkdir -p /etc/vulkan/icd.d/ && \
    echo "{\n\
    \"file_format_version\" : \"1.0.0\",\n\
    \"ICD\": {\n\
    \"library_path\": \"libGLX_nvidia.so.0\",\n\
    \"api_version\" : \"${VULKAN_API_VERSION}\"\n\
    }\n\
    }" > /etc/vulkan/icd.d/nvidia_icd.json

ARG VIRTUALGL_VERSION=3.1
# Install VirtualGL and make libraries available for preload
ARG VIRTUALGL_URL="https://sourceforge.net/projects/virtualgl/files"
RUN curl -fsSL -O "${VIRTUALGL_URL}/virtualgl_${VIRTUALGL_VERSION}_amd64.deb" && \
    curl -fsSL -O "${VIRTUALGL_URL}/virtualgl32_${VIRTUALGL_VERSION}_amd64.deb" && \
    apt-get update && apt-get install -y ./virtualgl_${VIRTUALGL_VERSION}_amd64.deb ./virtualgl32_${VIRTUALGL_VERSION}_amd64.deb && \
    rm -f "virtualgl_${VIRTUALGL_VERSION}_amd64.deb" "virtualgl32_${VIRTUALGL_VERSION}_amd64.deb" && \
    rm -rf /var/lib/apt/lists/* && \
    chmod u+s /usr/lib/libvglfaker.so && \
    chmod u+s /usr/lib/libdlfaker.so && \
    chmod u+s /usr/lib32/libvglfaker.so && \
    chmod u+s /usr/lib32/libdlfaker.so && \
    chmod u+s /usr/lib/i386-linux-gnu/libvglfaker.so && \
    chmod u+s /usr/lib/i386-linux-gnu/libdlfaker.so

# Anything below this line should be always kept the same between docker-nvidia-glx-desktop and docker-nvidia-egl-desktop

# Install KDE and other GUI packages
ENV XDG_CURRENT_DESKTOP KDE
ENV KWIN_COMPOSE N
# Use sudoedit to change protected files instead of using sudo on kate
ENV SUDO_EDITOR kate

# prevent Ubuntu's firefox stub from being installed
COPY /root/etc/apt/preferences.d/firefox-no-snap /etc/apt/preferences.d/firefox-no-snap

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /kclient/public/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  add-apt-repository -y ppa:mozillateam/ppa && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y \
    dolphin \
    firefox \
    gwenview \
    kde-config-gtk-style \
    kdialog \
    kfind \
    khotkeys \
    kio-extras \
    knewstuff-dialog \
    konsole \
    ksystemstats \
    kwin-addons \
    kwin-x11 \
    kwrite \
    kde-plasma-desktop \
    kwin-addons \
    kwin-x11 \
    kdeadmin \
    akregator \
    ark \
    baloo-kf5 \
    breeze-cursor-theme \
    breeze-icon-theme \
    debconf-kde-helper \
    colord-kde \
    desktop-file-utils \
    filelight \
    gwenview \
    hspell \
    kaddressbook \
    kaffeine \
    kate \
    kcalc \
    kcharselect \
    kdeconnect \
    kde-spectacle \
    kde-config-screenlocker \
    kde-config-updates \
    kdf \
    kget \
    kgpg \
    khelpcenter \
    khotkeys \
    kimageformat-plugins \
    kinfocenter \
    kio-extras \
    kleopatra \
    kmail \
    kmenuedit \
    kmix \
    knotes \
    kontact \
    kopete \
    korganizer \
    krdc \
    ktimer \
    kwalletmanager \
    librsvg2-common \
    okular \
    okular-extra-backends \
    plasma-dataengines-addons \
    plasma-discover \
    plasma-runners-addons \
    plasma-wallpapers-addons \
    plasma-widgets-addons \
    plasma-workspace-wallpapers \
    qtvirtualkeyboard-plugin \
    sonnet-plugins \
    sweeper \
    systemsettings \
    xdg-desktop-portal-kde \
    kubuntu-restricted-extras \
    kubuntu-wallpapers \
    pavucontrol-qt \
    transmission-qt \
    plasma-workspace \
    qml-module-qt-labs-platform \
    systemsettings && \
  echo "**** kde tweaks ****" && \
  sed -i \
    's/applications:org.kde.discover.desktop,/applications:org.kde.konsole.desktop,/g' \
    /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml && \
  apt-get install --install-recommends -y \
      libreoffice \
      libreoffice-style-breeze && \
  rm -rf /var/lib/apt/lists/* && \
  # Fix KDE startup permissions issues in containers
  cp -f /usr/lib/x86_64-linux-gnu/libexec/kf5/start_kdeinit /tmp/ && \
  rm -f /usr/lib/x86_64-linux-gnu/libexec/kf5/start_kdeinit && \
  cp -r /tmp/start_kdeinit /usr/lib/x86_64-linux-gnu/libexec/kf5/start_kdeinit && \
  rm -f /tmp/start_kdeinit && \
  echo "**** cleanup ****" && \
  apt-get autoclean && \
  rm -rf \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/*


# install package
RUN apt-get update && apt-get install -y \
        build-essential \
        curl \
        sudo \
        less \
        apt-utils \
        tzdata \
        git \
        tmux \
        bash-completion \
        command-not-found \
        libglib2.0-0 \
        vim \
        emacs \
        ssh \
        rsync \
        python3 \
        python3-pip \
        python3-dev \
        sed \
        ca-certificates \
        wget \
        gpg \
        gpg-agent \
        gpgconf \
        gpgv \
        locales \
        unzip \
        net-tools \
        software-properties-common \
        apt-transport-https \
        lsb-release \
        autoconf \
        gnupg \
        lsb-release \
        less \
        emacs \
        tmux \
        bash-completion \
        command-not-found \
        software-properties-common \
        xdg-user-dirs \
        iproute2 \
        init \
        systemd \
        locales \
        net-tools \
        iputils-ping \
        curl \
        wget \
        telnet \
        less \
        vim \
        sudo \
        tzdata \
        locales \
        g++ \
        cmake \
        libdbus-1-dev && \
    rm -rf /var/lib/apt/lists/*

# install ROS2 Humble
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null
RUN apt-get update && apt-get install -y \
    ros-humble-desktop-full \
    ros-dev-tools

# install colcon and rosdep
RUN apt-get update && apt-get install -y \
    python3-colcon-common-extensions \
    python3-rosdep

RUN rosdep init 

# install Chrome
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list

RUN apt-get update && apt-get install -y \
    google-chrome-stable && rm /etc/apt/sources.list.d/google.list

# install nodejs 18
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
RUN apt-get update && apt-get install -y nodejs


RUN userdel -r $(getent passwd 1000 | cut -d: -f1)

# add local files
COPY /root /

RUN rm -rf /config
RUN mkdir /config

# ports and volumes
EXPOSE 3000

ENTRYPOINT ["/init"]