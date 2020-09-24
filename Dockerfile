FROM debian:buster

LABEL maintainer="Jesse.Spielman@gmail.com"
LABEL license="MIT"

# Build time ARGs
ARG MITM_VERSION=5.1.1
ARG LOGO=logo.ans

# ENV vars
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update --fix-missing && apt-get install -y \
    hostapd \
    dbus \
    net-tools \
    iptables \
    dnsmasq \
    net-tools \
    macchanger \
    wget \
    unzip \
    libssl-dev \
    libffi-dev \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    locales \
    procps \
    git \
    tshark

WORKDIR /root

# Set locals per https://stackoverflow.com/a/38553499
# Required by some of the mitm tools
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8
ENV LANG en_US.UTF-8

# Build mitmproxy from source -- best way to get working on x86(-64) and ARM
RUN wget https://github.com/mitmproxy/mitmproxy/archive/v${MITM_VERSION}.zip \
    && unzip v${MITM_VERSION}.zip \
    && rm v${MITM_VERSION}.zip \
    && ln -s mitmproxy-${MITM_VERSION} mitmproxy-src
RUN cd mitmproxy-src && ./dev.sh && rm -rf ~/.cache/pip

# Copy over the pre-made CA files
# This ensures the certificates are always the same
COPY fake_ca /root/.mitmproxy

# Copy in some config files
COPY templates/hostapd.conf /etc/hostapd/hostapd.conf
COPY templates/hostapd /etc/default/hostapd
COPY templates/dnsmasq.conf /etc/dnsmasq.conf
COPY templates/mitm-config.yml /root/.mitmproxy/config.yml

# Copy in and set the entrypoint script
COPY entrypoint.sh /root/entrypoint.sh
COPY ${LOGO} /root/.logo.ans
ENTRYPOINT ["/root/entrypoint.sh"]
