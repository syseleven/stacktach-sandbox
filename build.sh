#!/bin/bash

echo "StackTach dev env build script"

PACKAGE=false
TOX=false
DEPLOY=false
QUICK=false
TMUX=false
DETACH=false

while getopts cqpdtmD opt; do
  case $opt in
  c)
      CLEAN=true
      ;;
  q)
      QUICK=true
      ;;
  p)
      PACKAGE=true
      ;;
  t)
      TOX=true
      ;;
  d)
      DEPLOY=true
      ;;
  m)
      TMUX=true
      ;;
  D)
      DETACH=true
      ;;
  esac
done

shift $((OPTIND - 1))

DEV_DIR=git
PKG_DIR=dist
SOURCE_DIR=$DEV_DIR
VENV_DIR=.venv
PIPELINE_ENGINE=winchester

if [[ "$CLEAN" = true ]]
then
    rm -rf data "$DEV_DIR" stacktach-* "$VENV_DIR" build "$PKG_DIR"
fi

if [[ "$PACKAGE" = true ]]
then
    # Ensure libmysqlclient-dev is installed on build machine.
    # TODO(sandy): Support other distros.
    dpkg -s libmysqlclient-dev 2>/dev/null >/dev/null \
            || sudo apt-get -y install libmysqlclient-dev
    SOURCE_DIR=$PKG_DIR
    rm -rf $PKG_DIR
    rm -rf $VENV_DIR
fi

if [[ -f local.sh ]]; then
    source local.sh
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  mkdir $SOURCE_DIR
fi

if [[ ! -d "$VENV_DIR" ]]; then
  virtualenv $VENV_DIR
fi

cd $SOURCE_DIR
for project in shoebox simport notigen notification-utils \
            stackdistiller quincy quince timex \
            klugman winchester
do
    pname=stacktach-$project
    if [ -d $pname ]; then 
        cd $pname && git pull && cd ..
    else
	set +e
        git clone http://git.openstack.org/openstack/$pname
	set -e
    fi
done
# We still have some stragglers ...
if [ -d notabene ]; then 
    cd notabene && git pull && cd ..
else
    git clone https://github.com/StackTach/notabene
fi 

if [ -d yagi ]; then 
    cd yagi && git pull && cd ..
else
    git clone --quiet https://github.com/rackerlabs/yagi
fi 

if [[ "$TOX" = true ]]
then
    for file in shoebox simport notification-utils \
                stackdistiller winchester
    do
        cd stacktach-$file
        set -e
        tox
        set +e
        cd ..
    done
    exit
fi

cd ..

source ./$VENV_DIR/bin/activate

# Some extra required libs ...
pip install https://cdn.mysql.com/Downloads/Connector-Python/mysql-connector-python-2.0.4.tar.gz
pip install gunicorn
pip install httpie
pip install pika
pip install librabbitmq   # requires "make" -- or it will fail silently!

# Needed by pyrax:
pip install pbr


if [[ "$PACKAGE" = true ]]
then
    BUILDFLAGS=""
else
    BUILDFLAGS="-e"
fi

if [[ "$QUICK" = false || "$PACKAGE" = true ]]
then
    for file in $SOURCE_DIR/*
    do
        echo "----------------------- $file ------------------------------"
        cd $file
        rm -rf build dist
        pip install --force-reinstall $BUILDFLAGS .
        cd ../..
    done
fi

# Hack(sandy): remove msgpack that conflicts with carrot
#pip uninstall -y msgpack-python

pip freeze > pip_freeze_versions.txt

cp pip_freeze_versions.txt $VENV_DIR

(cat yagi.conf.$PIPELINE_ENGINE ; cat yagi.conf.common ) > yagi.conf

if [ $PIPELINE_ENGINE == "winchester" ]
then
    winchester_db -c winchester.yaml upgrade head
fi

if [[ "$PACKAGE" = true ]]
then
    SHA=$(git log --pretty=format:'%h' -n 1)
    mkdir dist
    virtualenv --relocatable $VENV_DIR
    mv $VENV_DIR dist/stv3
    # Fix up the activate script to new location. --relocatable doesn't handle this.
    cd dist/stv3/bin
    sed -i "s/VIRTUAL_ENV=\".*\"/VIRTUAL_ENV=\"\/opt\/stv3\"/" activate
    cd ../..
    tar -zcvf ../stacktachv3_$SHA.tar.gz stv3
    cd ..
    echo "Release tarball in stacktachv3_$SHA.tar.gz"

    if [[ "$DEPLOY" == true ]]
    then
        echo ansible-playbook database.yaml --extra-vars \"tarball_absolute_path=../stacktachv3_$SHA.tar.gz\" -vvv
        echo ansible-playbook workers.yaml --extra-vars \"tarball_absolute_path=../stacktachv3_$SHA.tar.gz\" -vvv
        echo ansible-playbook api.yaml --extra-vars \"tarball_absolute_path=../stacktachv3_$SHA.tar.gz\" -vvv
    fi
else
    if [[ "$TMUX" = false ]]
    then
        # TODO $DETACH
        screen -c screenrc.$PIPELINE_ENGINE
    else
        deactivate
        if [[ "$DETACH" = false ]]; then
            tmux start-server \; new-session -s tach -n shell bash \; source-file tmuxrc.$PIPELINE_ENGINE \; attach-session
        else
            tmux start-server \; new-session -d -s tach -n shell bash \; source-file tmuxrc.$PIPELINE_ENGINE
        fi
    fi
fi
