#!/bin/bash -e

. ../../include/path.sh
. ../../include/depinfo.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf _build$ndk_suffix
	exit 0
else
	exit 255
fi

# TODO figure this out
if [[ -z "$DOIT" && "$ndk_triple" != "arm"* ]]; then
	echo "Skipping build for $ndk_triple, only supposed to run on ARM (for now)"
	echo "To build anyway set DOIT=1 env variable"
	exit 0
fi
###

hostpy=python${v_python:0:3}
if ! command -v $hostpy; then
	echo "compatible Python ($hostpy) is required to build"
	exit 1
fi

recompile_py () {
	find . -name '*.pyc' -delete
	$hostpy -OO -m compileall -b -j4 .
	# leave only the legacy locations (*.pyc next to *.py)
	find . -name "__pycache__" -print0 | xargs -0 -- rm -rf
}

prune_stdlib () {
	local delete=(
		pydoc_data turtledemo # docs
		test unittest/test # unittests
		tkinter sqlite3 venv ensurepip # doesn't work anyway
		lib2to3 idlelib distutils multiprocessing # not used by ytdl
	)
	rm -r "${delete[@]}"
	# ytdl tries to import this:
	rm -rf ctypes && mkdir -p ctypes
	cat >ctypes/__init__.py <<"FILE"
class cdll():
  @staticmethod
  def LoadLibrary(lib):
    raise OSError
FILE
}

export READELF=llvm-readelf
export CFLAGS="-Os -I$prefix_dir/include"
export LDFLAGS="-L$prefix_dir/lib"

mkdir -p _build$ndk_suffix
cd _build$ndk_suffix

# build
ac_cv_file__dev_ptmx=no ac_cv_file__dev_ptc=no \
../configure --host=$ndk_triple --build=${ndk_triple%%-*} \
	--enable-ipv6 --disable-shared --without-ensurepip
make -j$cores

# install to temporary location
rm -rf dest
make DESTDIR="$PWD/dest" install
inst=$PWD/dest/usr/local

out=$(realpath ../../../../app/src/main/assets/ytdl)
rm -f $out/python*

# copy & strip executable
cp -v python $out/python3
llvm-strip -s $out/python3
termux-elf-cleaner --api-level 24 $out/python3

# package standard library
pushd $inst/lib/python3.*
prune_stdlib
recompile_py
zip -9 $out/python3${v_python:2:1}.zip -R '*.pyc'
popd
