#!/bin/sh
# ASAN variant startup: a single prefork worker, ASAN logs in an inspectable
# directory, Apache in the foreground.
set -eu

mkdir -p /var/log/apache2 /var/run/apache2 /tmp
chown -R www-data:www-data /var/log/apache2 2>/dev/null || true

# One worker only: same reason as the normal lab — producer and consumer in the
# same PID.
sed -i 's/^\s*StartServers\s\+[0-9]\+/    StartServers 1/'            /etc/apache2/apache2.conf
sed -i 's/^\s*MaxRequestWorkers\s\+[0-9]\+/    MaxRequestWorkers 1/'  /etc/apache2/apache2.conf
sed -i 's/^\s*ServerLimit\s\+[0-9]\+/    ServerLimit 1/'              /etc/apache2/apache2.conf

echo "[p2s] php: $(php -v | head -n1)"
echo "[p2s] asan: ${LD_PRELOAD}"

# Apache does not like running as root without an explicit -DFOREGROUND; we keep
# root+prefork like the real target so the heap layout stays comparable.
exec apache2ctl -D FOREGROUND
