FROM sbutler/pie-base

ARG HTTPD_UID=8001
ARG HTTPD_GID=8001

ARG HTTPD_DISMOD="\
    mpm_event \
    "

ARG HTTPD_ENMOD="\
    allowmethods \
    cgi \
    expires \
    headers \
    include \
    macro \
    proxy \
    proxy_fcgi \
    remoteip \
    reqtimeout \
    rewrite \
    ssl \
    pie-mpm-event \
    pie-info \
    pie-status \
    "

ARG HTTPD_DISCONF="\
    other-vhosts-access-log \
    serve-cgi-bin \
    localized-error-pages \
    "

ARG HTTPD_ENCONF="\
    pie-security \
    pie-logs \
    pie-error-pages \
    "

RUN set -xe \
    && apt-get update && apt-get install -y \
        apache2 \
        libapache2-mod-shib2 \
        libapache2-mod-xsendfile \
        python2.7 \
        unzip \
        curl \
        jq \
        --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

COPY etc/ /etc
COPY opt/ /opt
COPY pie-entrypoint.sh /usr/local/bin/

RUN set -xe \
    && groupadd -r -g $HTTPD_GID pie-www-data \
    && useradd -N -r -g pie-www-data -s /usr/sbin/nologin -u $HTTPD_UID pie-www-data \
    && for mod in $HTTPD_DISMOD; do a2dismod $mod; done \
    && for mod in $HTTPD_ENMOD; do a2enmod $mod; done \
    && for conf in $HTTPD_DISCONF; do a2disconf $conf; done \
    && for conf in $HTTPD_ENCONF; do a2enconf $conf; done \
    && a2ensite 001-pie-sites && a2ensite 000-default-ssl && a2ensite 999-pie-agent \
    && chmod a+rx /usr/local/bin/pie-entrypoint.sh

ENV PIE_EXP_MEMORY_SIZE 30
ENV PIE_RES_MEMORY_SIZE 50

ENV APACHE_SERVER_ADMIN   webmaster@example.org
ENV APACHE_ADMIN_SUBNET   10.0.0.0/8

ENV PHP_FPM_HOSTNAME  pie-php.local
ENV PHP_FPM_PORT      9000

VOLUME /etc/apache2/sites-pie
VOLUME /etc/opt/pie/apache2
VOLUME /etc/opt/pie/ssl
VOLUME /var/www

EXPOSE 80 8080
EXPOSE 443 8443
EXPOSE 8008

ENTRYPOINT ["/usr/local/bin/pie-entrypoint.sh"]
CMD ["apache2-pie"]
