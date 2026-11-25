# AddressSanitizer build — to SEE the UAF, not to exploit it.
#
# Experimental: the build takes ~15 min and Apache must run with the ASAN runtime
# preloaded (see CMD). Without LD_PRELOAD, ASAN intercepts nothing inside
# libphp.so and the lab produces false negatives.
#
#   docker compose --profile asan build victim-asan
#   docker compose --profile asan up -d
#   docker compose logs -f victim-asan     # or read /var/log/apache2/asan.*

FROM debian:bookworm

ARG PHP_VERSION=8.5.11
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        apache2 \
        apache2-dev \
        build-essential \
        autoconf \
        bison \
        re2c \
        pkg-config \
        libxml2-dev \
        libsqlite3-dev \
        libssl-dev \
        libzip-dev \
        zlib1g-dev \
        libcurl4-openssl-dev \
        libonig-dev \
        libpng-dev \
        libjpeg62-turbo-dev \
        libfreetype6-dev \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src
RUN curl -fsSL "https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz" -o php.tar.gz \
    && tar -xzf php.tar.gz && mv "php-${PHP_VERSION}" php

WORKDIR /usr/src/php
RUN ./configure \
        --with-apxs2=/usr/bin/apxs2 \
        --enable-debug \
        --disable-cgi \
        --with-config-file-path=/usr/local/etc/php \
        --with-config-file-scan-dir=/usr/local/etc/php/conf.d \
        --with-zlib \
        --with-curl \
        --with-openssl \
        --enable-mbstring \
        --with-sqlite3 \
        --enable-session \
        CFLAGS="-fsanitize=address -fno-omit-frame-pointer -g -O1" \
        LDFLAGS="-fsanitize=address" \
    && make -j"$(nproc)" \
    && make install

RUN mkdir -p /usr/local/etc/php/conf.d \
    && cp php.ini-development /usr/local/etc/php/php.ini-development \
    && a2enmod rewrite \
    && echo "ServerName localhost" >> /etc/apache2/apache2.conf

# ASAN must be loaded in the process hosting libphp.so.
ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libasan.so.8
ENV ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:symbolize=1:log_path=/var/log/apache2/asan

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80
CMD ["/usr/local/bin/docker-entrypoint.sh"]
