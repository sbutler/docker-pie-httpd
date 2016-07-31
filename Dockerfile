FROM sbutler/pie-base

ENV PIE_EXP_MEMORY_SIZE 30
ENV PIE_RES_MEMORY_SIZE 50

ENV HTTPD_DISMOD "$HTTPD_DISMOD \
    mpm_event \
    "

ENV HTTPD_ENMOD "$HTTPD_ENMOD \
    allowmethods \
    expires \
    headers \
    macro \
    proxy \
    proxy_fcgi \
    remoteip \
    reqtimeout \
    rewrite \
    ssl \
    pie-mpm-event \
    "

ENV HTTPD_DISCONF "$HTTPD_DISCONF \
    other-vhosts-access-log \
    serve-cgi-bin \
    "

ENV HTTPD_ENCONF "$HTTPD_ENCONF \
    pie-security \
    pie-logs \
    "

RUN set -xe \
    && apt-get update && apt-get install -y \
        apache2 \
        libapache2-mod-shib2 \
        libapache2-mod-xsendfile \
        --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

COPY etc/ /etc
COPY pie-entrypoint.sh /usr/local/bin/
COPY pie-sitegen.pl /usr/local/bin/

RUN set -xe \
    && for mod in $HTTPD_DISMOD; do a2dismod $mod; done \
    && for mod in $HTTPD_ENMOD; do a2enmod $mod; done \
    && for conf in $HTTPD_DISCONF; do a2disconf $conf; done \
    && for conf in $HTTPD_ENCONF; do a2enconf $conf; done \
    && a2ensite 00pie-sites \
    && chmod a+rx /usr/local/bin/pie-entrypoint.sh \
    && chmod a+rx /usr/local/bin/pie-sitegen.pl

VOLUME /etc/opt/pie/apache2
VOLUME /var/www

EXPOSE 80
EXPOSE 443

ENTRYPOINT ["/usr/local/bin/pie-entrypoint.sh"]
CMD ["apache2-pie"]
