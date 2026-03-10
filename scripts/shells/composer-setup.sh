#!/bin/sh

set -eu

COMPOSER_INSTALL_DIR="${COMPOSER_INSTALL_DIR:-/usr/local/bin}"
COMPOSER_FILENAME="${COMPOSER_FILENAME:-composer}"

EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]
then
  >&2 echo 'ERROR: Invalid installer checksum'
  rm composer-setup.php
  exit 1
fi

mkdir -p "$COMPOSER_INSTALL_DIR"
php composer-setup.php --quiet --install-dir="$COMPOSER_INSTALL_DIR" --filename="$COMPOSER_FILENAME"
RESULT=$?
rm composer-setup.php
rm -f -- "$0"
exit $RESULT
