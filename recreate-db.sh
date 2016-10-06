#!/bin/sh

set -e

cd "$(dirname $0)"

# TODO: largely c&p from vagrant/bootstrap.sh, changes: no root passwd, db scheme create

echo "drop database if exists winchester" | mysql -uroot
echo "DROP USER 'winchester'@'localhost'" | mysql -uroot 2>/dev/null || true
echo "CREATE USER 'winchester'@'localhost' IDENTIFIED BY 'testpasswd'" | mysql -uroot
echo "CREATE DATABASE winchester" | mysql -uroot
echo "GRANT ALL ON winchester.* TO 'winchester'@'localhost'" | mysql -uroot
echo "flush privileges" | mysql -uroot

. ./.venv/bin/activate && winchester_db -c winchester.yaml upgrade head
