# syntax=docker/dockerfile:1

############## picons stage ##############
# built by https://github.com/linuxserver/picons-builder
FROM ghcr.io/linuxserver/picons-builder as piconsstage


FROM ghcr.io/linuxserver/baseimage-alpine:3.18 as amd64-buildstage
FROM ghcr.io/linuxserver/baseimage-alpine:arm64v8-3.18 as arm64-buildstage

FROM ${TARGETARCH}${TARGETVARIANT}-buildstage as buildstage
############## build stage ##############


# package versions
ARG ARGTABLE_VER="2.13"

# environment settings
ARG TARGETARCH
ARG TZ="Etc/UTC"
ARG TVHEADEND_COMMIT
ENV HOME="/config"

# copy patches and picons
COPY patches/ /tmp/patches/
COPY --from=piconsstage /picons.tar.bz2 /picons.tar.bz2

RUN \
  echo "**** install build packages ****" && \
  apk add --no-cache \
    autoconf \
    automake \
    bsd-compat-headers \
    build-base \
    cmake \
    ffmpeg4-dev \
    file \
    findutils \
    gettext-dev \
    git \
    gnu-libiconv-dev \
    libgcrypt-dev \
    libhdhomerun-dev \
    libtool \
    libva-dev \
    libvpx-dev \
    libxml2-dev \
    libxslt-dev \
    linux-headers \
    openssl-dev \
    opus-dev \
    patch \
    pcre2-dev \
    pkgconf \
    pngquant \
    python3 \
    sdl2-dev \
    uriparser-dev \
    x264-dev \
    x265-dev \
    zlib-dev

# Download linuxserver/tvheadend git
RUN \
  echo "**** download linuxserver/docker-tvheadend ****" && \
  git clone https://github.com/linuxserver/docker-tvheadend.git /tmp/docker-tvheadend

RUN \
  echo "**** copy patches ****" && \
  cp /tmp/docker-tvheadend/patches/* /tmp/patches/

RUN \
  echo "**** compile libdvbcsa ****" && \
  git clone https://github.com/glenvt18/libdvbcsa.git /tmp/libdvbcsa && \
  cd /tmp/libdvbcsa && \
  git checkout 2a1e61e569a621c55c2426f235f42c2398b7f18f && \
  echo "**** patch libdvbcsa ****" && \
  git config apply.whitespace nowarn && git apply /tmp/patches/libdvbcsa.patch && sed 's# == 4)# > 0)#' -i src/dvbcsa_pv.h && \
  ./bootstrap && \
  ./configure \
    $([ "${TARGETARCH}" == "amd64" ] && echo '--enable-ssse3' || echo "--enable-neon") \
    --disable-shared \
    --enable-static \
    --with-pic \
    --prefix=/usr \
    --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --localstatedir=/var && \
  make -j 2 && \
  make check && \
  make DESTDIR=/tmp/libdvbcsa-build install && \
  echo "**** copy to /usr for tvheadend dependency ****" && \
  cp -pr /tmp/libdvbcsa-build/usr/* /usr/

RUN \
  echo "**** remove musl iconv.h and replace with gnu-iconv.h ****" && \
  rm -rf /usr/include/iconv.h && \
  cp /usr/include/gnu-libiconv/iconv.h /usr/include/iconv.h

RUN \
  echo "**** compile tvheadend ****" && \
  if [ -z ${TVHEADEND_COMMIT+x} ]; then \
    TVHEADEND_COMMIT=$(curl -sX GET https://api.github.com/repos/tvheadend/tvheadend/commits/master \
    | jq -r '. | .sha'); \
  fi && \
  mkdir -p \
    /tmp/tvheadend && \
  git clone https://github.com/tvheadend/tvheadend.git /tmp/tvheadend && \
  cd /tmp/tvheadend && \
  git fetch && \
  git checkout ${TVHEADEND_COMMIT} && \
  echo "**** patch tvheadend ****" && \
  git apply /tmp/patches/tvheadend43.patch && \
  echo "**** configure tvheadend ****" && \
  ./configure \
    `#Encoding` \
    --disable-ffmpeg_static \
    --disable-libfdkaac_static \
    --disable-libtheora_static \
    --disable-libopus_static \
    --disable-libvorbis_static \
    --disable-libvpx_static \
    --disable-libx264_static \
    --disable-libx265_static \
    --disable-libfdkaac \
    --enable-libopus \
    --enable-libvorbis \
    --enable-libvpx \
    --enable-libx264 \
    --enable-libx265 \
    \
    `#Options` \
    --disable-avahi \
    --disable-dbus_1 \
    --disable-bintray_cache \
    --disable-execinfo \
    --disable-hdhomerun_static \
    --enable-hdhomerun_client \
    --enable-dvbcsa \
    --enable-libav \
    --enable-pngquant \
    --enable-trace \
    --enable-vaapi \
    --infodir=/usr/share/info \
    --localstatedir=/var \
    --mandir=/usr/share/man \
    --prefix=/usr \
    --python=python3 \
    --sysconfdir=/config && \
  make -j 2 && \
  make DESTDIR=/tmp/tvheadend-build install

RUN \
  echo "**** compile argtable2 ****" && \
  ARGTABLE_VER1="${ARGTABLE_VER//./-}" && \
  mkdir -p \
    /tmp/argtable && \
  curl -s -o \
  /tmp/argtable-src.tar.gz -L \
    "https://sourceforge.net/projects/argtable/files/argtable/argtable-${ARGTABLE_VER}/argtable${ARGTABLE_VER1}.tar.gz" && \
  tar xf \
  /tmp/argtable-src.tar.gz -C \
    /tmp/argtable --strip-components=1 && \
  cp /tmp/patches/config.* /tmp/argtable && \
  cd /tmp/argtable && \
  ./configure \
    --prefix=/usr && \
  make -j 2 && \
  make check && \
  make DESTDIR=/tmp/argtable-build install && \
  echo "**** copy to /usr for comskip dependency ****" && \
  cp -pr /tmp/argtable-build/usr/* /usr/

RUN \
  echo "***** compile comskip ****" && \
  git clone https://github.com/erikkaashoek/Comskip /tmp/comskip && \
  cd /tmp/comskip && \
  ./autogen.sh && \
  ./configure \
    --bindir=/usr/bin \
    --sysconfdir=/config/comskip && \
  make -j 2 && \
  make DESTDIR=/tmp/comskip-build install

RUN \
  echo "***** extract picons ****" && \
  mkdir -p /picons && \
  tar xf \
    /picons.tar.bz2 -C \
    /picons

############## runtime stage ##############
FROM ghcr.io/linuxserver/baseimage-alpine:3.18 as amd64-runtime
FROM ghcr.io/linuxserver/baseimage-alpine:arm64v8-3.18 as arm64-runtime

FROM ${TARGETARCH}${TARGETVARIANT}-runtime as runtime

# set version label
ARG TARGETARCH
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="Chris230291"

# environment settings
ENV HOME="/config"

RUN \
  echo "**** install runtime packages ****" && \
  apk add --no-cache \
    bsd-compat-headers \
    ffmpeg \
    ffmpeg4-libavcodec \
    ffmpeg4-libavdevice \
    ffmpeg4-libavfilter \
    ffmpeg4-libavformat \
    ffmpeg4-libavutil \
    ffmpeg4-libpostproc \
    ffmpeg4-libswresample \
    ffmpeg4-libswscale \
    gnu-libiconv \
    libhdhomerun-libs \
    libva \
    $([ "${TARGETARCH}" == "amd64" ] && echo 'libva-intel-driver') \
    $([ "${TARGETARCH}" == "amd64" ] && echo 'intel-media-driver') \
    mesa \
    libvpx \
    libxml2 \
    libxslt \
    linux-headers \
    opus \
    pcre2 \
    perl \
    perl-datetime-format-strptime \
    perl-json \
    py3-requests \
    python3 \
    uriparser \
    x264 \
    x265 \
    xmltv \
    zlib

# copy local files and buildstage artifacts
COPY --from=buildstage /tmp/argtable-build/usr/ /usr/
COPY --from=buildstage /tmp/comskip-build/usr/ /usr/
COPY --from=buildstage /tmp/tvheadend-build/usr/ /usr/
COPY --from=buildstage /picons /picons
COPY --from=buildstage /tmp/docker-tvheadend/root/ /

# ports and volumes
EXPOSE 9981 9982
VOLUME /config