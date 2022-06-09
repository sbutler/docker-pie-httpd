FROM publish/pie-base:latest-ubuntu22.04

ARG HTTPD_UID=8001
ARG HTTPD_GID=8001

ARG HTTPD_DISMOD="\
    mpm_event \
    shib \
    status \
    "

ARG HTTPD_ENMOD="\
    allowmethods \
    asis \
    authnz_ldap \
    cache \
    cache_disk \
    cache_socache \
    cgi \
    expires \
    headers \
    include \
    macro \
    proxy \
    proxy_fcgi \
    proxy_html \
    proxy_http \
    remoteip \
    reqtimeout \
    rewrite \
    ssl \
    socache_memcache \
    socache_shmcb \
    pie-mpm-event \
    pie-info \
    pie-ldap \
    pie-shib \
    pie-status \
    unique_id \
    "

ARG HTTPD_DISCONF="\
    other-vhosts-access-log \
    serve-cgi-bin \
    localized-error-pages \
    shib \
    "

ARG HTTPD_ENCONF="\
    pie-cache \
    pie-security \
    pie-logs \
    pie-remoteip \
    pie-error-pages \
    pie-shib \
    "

ARG DEBIAN_FRONTEND=noninteractive

RUN set -xe \
    && apt-get update && apt-get install -y --no-install-recommends \
        apache2 \
        libapache2-mod-shib \
        libapache2-mod-xsendfile \
        python3 \
        python3-pip \
        python3-botocore \
        python3-jmespath \
        python3-requests \
    && rm -fr /etc/shibboleth/* \
    && rm -fr /var/log/shibboleth/* \
    && rm -fr /var/log/apache2/* \
    && rm -rf /var/lib/apt/lists/*

COPY etc/ /etc
COPY opt/ /opt
COPY pie-entrypoint.sh /usr/local/bin/
COPY pie-trustedproxies.sh /usr/local/bin/
COPY pie-htcacheclean.sh /usr/local/bin/
COPY pie-configtest.sh /usr/local/bin/

COPY pie-aws-metrics.py /usr/local/bin/
RUN pip3 install --no-cache-dir boto3

RUN groupadd -r -g $HTTPD_GID pie-www-data
RUN useradd -N -r -g pie-www-data -s /usr/sbin/nologin -u $HTTPD_UID pie-www-data

RUN for mod in $HTTPD_DISMOD; do a2dismod $mod; done
RUN for mod in $HTTPD_ENMOD; do a2enmod $mod; done
RUN for conf in $HTTPD_DISCONF; do a2disconf $conf; done
RUN for conf in $HTTPD_ENCONF; do a2enconf $conf; done
RUN a2ensite 001-pie-sites && a2ensite 000-default-ssl && a2ensite 000-proxydefault && a2ensite 000-proxydefault-ssl && a2ensite 999-pie-agent
RUN mkdir -m 0750 /var/log/shibboleth-www
RUN chown pie-www-data:pie-www-data /var/log/shibboleth-www

RUN chmod a+rx /usr/local/bin/pie-aws-metrics.py
RUN chmod a+rx /usr/local/bin/pie-entrypoint.sh
RUN chmod a+rx /usr/local/bin/pie-trustedproxies.sh
RUN chmod a+rx /usr/local/bin/pie-htcacheclean.sh
RUN chmod a+rx /usr/local/bin/pie-configtest.sh

ENV PIE_EXP_MEMORY_SIZE=30 \
    PIE_RES_MEMORY_SIZE=50

ENV APACHE_SERVER_NAME="" \
    APACHE_SERVER_ADMIN=webmaster@example.org \
    APACHE_ADMIN_SUBNET=10.0.0.0/8 \
    APACHE_REMOTEIP_TRUSTEDPROXYLIST_URL="https://s3.amazonaws.com/deploy-publish-illinois-edu/cloudfront-trustedproxylist.txt" \
    APACHE_REMOTEIP_HEADER=X-Forwarded-For \
    APACHE_LOGGING="" \
    APACHE_CACHE_LOCK=on \
    APACHE_CACHE_QUICK_HANDLER=off \
    APACHE_CACHE_DEFAULT=3600 \
    APACHE_CACHE_MIN=0 \
    APACHE_CACHE_MAX=86400 \
    APACHE_CACHE_LIMIT="" \
    APACHE_CACHE_IGNORE_CACHECONTROL=on \
    APACHE_CACHE_IGNORE_NOLASTMOD=on \
    APACHE_CACHE_IGNORE_QUERYSTRING=off \
    APACHE_CACHE_STORE_EXPIRED=off \
    APACHE_CACHE_STORE_NOSTORE=off \
    APACHE_CACHE_STORE_PRIVATE=off

ENV APACHE_PROXY_URL="" \
    APACHE_PROXY_PRESERVE_HOST=off

ENV PHP_FPM_SOCKET "/run/php-fpm.sock.d/default.sock"

ENV SHIBD_CONFIG_SUFFIX ""

VOLUME /etc/apache2/sites-pie
VOLUME /etc/opt/pie/apache2 /etc/opt/pie/ssl
VOLUME /var/www
VOLUME /var/log/apache2 /var/log/shibboleth-www
VOLUME /var/cache/apache2/mod_cache_disk

EXPOSE 80 8080
EXPOSE 443 8443
EXPOSE 8008

ENTRYPOINT ["/usr/local/bin/pie-entrypoint.sh"]
CMD ["apache2-pie"]
