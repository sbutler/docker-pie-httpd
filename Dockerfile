# Copyright (c) 2017 University of Illinois Board of Trustees
# All rights reserved.
#
# Developed by: 		Technology Services
#                      	University of Illinois at Urbana-Champaign
#                       https://techservices.illinois.edu/
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# with the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
#	* Redistributions of source code must retain the above copyright notice,
#	  this list of conditions and the following disclaimers.
#	* Redistributions in binary form must reproduce the above copyright notice,
#	  this list of conditions and the following disclaimers in the
#	  documentation and/or other materials provided with the distribution.
#	* Neither the names of Technology Services, University of Illinois at
#	  Urbana-Champaign, nor the names of its contributors may be used to
#	  endorse or promote products derived from this Software without specific
#	  prior written permission.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS WITH
# THE SOFTWARE.
FROM sbutler/pie-base AS builder

RUN set -xe \
    && cp /etc/apt/sources.list /etc/apt/sources.list.orig \
    && sed -re 's/^deb[[:space:]]+(.+)$/deb-src \1/' < /etc/apt/sources.list.orig >> /etc/apt/sources.list \
    && rm /etc/apt/sources.list.orig \
    && apt-get update && apt-get install -y \
        build-essential \
        fakeroot \
        devscripts \
        apache2 \
        --no-install-recommends \
    && mkdir -p /usr/src/patches /usr/src/debian /output

COPY apache2-*.patch /usr/src/patches

WORKDIR /usr/src/debian
RUN set -xe \
    && apt-get source -y apache2 \
    && apt-get build-dep -y apache2 \
    && cd "$(find . -maxdepth 1 -type d -name apache2-*)" \
    && cp /usr/src/patches/apache2-*.patch debian/patches/ \
    && (cd /usr/src/patches && ls -1 apache2-*.patch) >> debian/patches/series \
    && debuild -b -uc -us \
    && cd /usr/src/debian \
    && cp *.deb /output/ \
    && rm -rf /var/lib/apt/lists/*


FROM sbutler/pie-base

ARG HTTPD_UID=8001
ARG HTTPD_GID=8001

ARG HTTPD_DISMOD="\
    mpm_event \
    status \
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
    unique_id \
    "

ARG HTTPD_DISCONF="\
    other-vhosts-access-log \
    serve-cgi-bin \
    localized-error-pages \
    "

ARG HTTPD_ENCONF="\
    pie-security \
    pie-logs \
    pie-remoteip \
    pie-error-pages \
    "

COPY --from=builder /output/*.deb /tmp/apache2-debs/

RUN set -xe \
    && cd /tmp/apache2-debs \
    && dpkg -i apache2_*.deb apache2-bin_*.deb apache2-data_*.deb apache2-utils_*.deb || /bin/true \
    && apt-get update && apt-get install -y -f --no-install-recommends \
    && dpkg -i apache2_*.deb apache2-bin_*.deb apache2-data_*.deb apache2-utils_*.deb \
    && apt-get install -y \
        libapache2-mod-shib2 \
        libapache2-mod-xsendfile \
        python2.7 \
        python3 python3-pip python3-botocore python3-jmespath python3-requests \
        unzip \
        curl \
        --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && rm -fr /tmp/apache2-debs

COPY etc/ /etc
COPY opt/ /opt
COPY pie-entrypoint.sh /usr/local/bin/
COPY pie-trustedproxies.sh /usr/local/bin/

COPY pie-aws-metrics.py /usr/local/bin/
RUN pip3 install boto3

RUN set -xe \
    && groupadd -r -g $HTTPD_GID pie-www-data \
    && useradd -N -r -g pie-www-data -s /usr/sbin/nologin -u $HTTPD_UID pie-www-data \
    && for mod in $HTTPD_DISMOD; do a2dismod $mod; done \
    && for mod in $HTTPD_ENMOD; do a2enmod $mod; done \
    && for conf in $HTTPD_DISCONF; do a2disconf $conf; done \
    && for conf in $HTTPD_ENCONF; do a2enconf $conf; done \
    && a2ensite 001-pie-sites && a2ensite 000-default-ssl && a2ensite 999-pie-agent \
    && chmod a+rx /usr/local/bin/pie-aws-metrics.py \
    && chmod a+rx /usr/local/bin/pie-entrypoint.sh \
    && chmod a+rx /usr/local/bin/pie-trustedproxies.sh

ENV PIE_EXP_MEMORY_SIZE=30 \
    PIE_RES_MEMORY_SIZE=50

ENV APACHE_SERVER_ADMIN=webmaster@example.org \
    APACHE_ADMIN_SUBNET=10.0.0.0/8 \
    APACHE_REMOTEIP_TRUSTEDPROXYLIST_URL="https://s3.amazonaws.com/deploy-publish-illinois-edu/cloudfront-trustedproxylist.txt" \
    APACHE_REMOTEIP_HEADER=X-Forwarded-For

ENV PHP_FPM_HOSTNAME=pie-php.local \
    PHP_FPM_PORT=9000

ENV SHIBD_CONFIG_SUFFIX ""

VOLUME /etc/apache2/sites-pie
VOLUME /etc/opt/pie/apache2
VOLUME /etc/opt/pie/ssl
VOLUME /var/www

EXPOSE 80 8080
EXPOSE 443 8443
EXPOSE 8008

ENTRYPOINT ["/usr/local/bin/pie-entrypoint.sh"]
CMD ["apache2-pie"]
