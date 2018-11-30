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
FROM sbutler/pie-base:latest-ubuntu18.04

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

COPY SWITCHaai-swdistrib.asc /tmp/
COPY SWITCHaai-swdistrib.list /tmp/

RUN set -xe \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get update && apt-get install -y --no-install-recommends gnupg  \
    && apt-key add /tmp/SWITCHaai-swdistrib.asc && rm /tmp/SWITCHaai-swdistrib.asc \
    && mv /tmp/SWITCHaai-swdistrib.list /etc/apt/sources.list.d/ \
    && apt-get update && apt-get install -y --no-install-recommends \
        apache2 \
        curl \
        libapache2-mod-shib \
        libapache2-mod-xsendfile \
        python3 \
        python3-pip \
        python3-botocore \
        python3-jmespath \
        python3-requests \
        unzip \
    && rm -rf /var/lib/apt/lists/*

COPY etc/ /etc
COPY opt/ /opt
COPY pie-entrypoint.sh /usr/local/bin/
COPY pie-trustedproxies.sh /usr/local/bin/

COPY pie-aws-metrics.py /usr/local/bin/
RUN pip3 install --no-cache-dir boto3

RUN groupadd -r -g $HTTPD_GID pie-www-data
RUN useradd -N -r -g pie-www-data -s /usr/sbin/nologin -u $HTTPD_UID pie-www-data

RUN for mod in $HTTPD_DISMOD; do a2dismod $mod; done
RUN for mod in $HTTPD_ENMOD; do a2enmod $mod; done
RUN for conf in $HTTPD_DISCONF; do a2disconf $conf; done
RUN for conf in $HTTPD_ENCONF; do a2enconf $conf; done
RUN a2ensite 001-pie-sites && a2ensite 000-default-ssl && a2ensite 999-pie-agent

RUN chmod a+rx /usr/local/bin/pie-aws-metrics.py
RUN chmod a+rx /usr/local/bin/pie-entrypoint.sh
RUN chmod a+rx /usr/local/bin/pie-trustedproxies.sh

ENV PIE_EXP_MEMORY_SIZE=30 \
    PIE_RES_MEMORY_SIZE=50

ENV APACHE_SERVER_ADMIN=webmaster@example.org \
    APACHE_ADMIN_SUBNET=10.0.0.0/8 \
    APACHE_REMOTEIP_TRUSTEDPROXYLIST_URL="https://s3.amazonaws.com/deploy-publish-illinois-edu/cloudfront-trustedproxylist.txt" \
    APACHE_REMOTEIP_HEADER=X-Forwarded-For

ENV PHP_FPM_SOCKET "/run/php/php7.2-fpm.sock"

ENV SHIBD_CONFIG_SUFFIX ""

VOLUME /etc/apache2/sites-pie
VOLUME /etc/opt/pie/apache2 /etc/opt/pie/ssl
VOLUME /var/www

EXPOSE 80 8080
EXPOSE 443 8443
EXPOSE 8008

ENTRYPOINT ["/usr/local/bin/pie-entrypoint.sh"]
CMD ["apache2-pie"]
