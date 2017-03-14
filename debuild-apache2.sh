#!/bin/bash

set -xe

apt-get update

cd /usr/src/debian
apt-get install -y apache2 --no-install-recommends
apt-get source -y apache2
apt-get build-dep -y apache2

cd "$(find . -maxdepth 1 -type d -name apache2-*)"
cp /usr/src/patches/apache2-*.patch debian/patches/
(cd /usr/src/patches && ls -1 apache2-*.patch) >> debian/patches/series

debuild -b -uc -us

cd /usr/src/debian
cp *.deb /output/
