#!/bin/bash -e

. ./include/depinfo.sh

. ./include/path.sh # load $os var

[ -z "$TRAVIS" ] && TRAVIS=0 # skip steps not required for CI?
[ -z "$WGET" ] && WGET=wget # possibility of calling wget differently

if [ "$os" == "linux" ]; then
	if [ $TRAVIS -eq 0 ]; then
		hash yum &>/dev/null && {
			sudo yum install autoconf pkgconfig libtool ninja-build \
			python3-pip python3-setuptools unzip wget;
			sudo pip3 install meson; }
		dpkg -l autoconf | grep "no description" &>/dev/null && { sudo apt-get install autoconf; }
		dpkg -l pkg-config | grep "no description" &>/dev/null && { sudo apt-get install pkg-config; }
		dpkg -l libtool | grep "no description" &>/dev/null && { sudo apt-get install libtool; }
		dpkg -l ninja-build | grep "no description" &>/dev/null && { sudo apt-get install ninja-build; }
		dpkg -l python3-pip | grep "no description" &>/dev/null && { sudo apt-get install python3-pip; }
		dpkg -l python3-setuptools | grep "no description" &>/dev/null && { sudo apt-get install python3-setuptools; }
		dpkg -l unzip | grep "no description" &>/dev/null && { sudo apt-get install unzip; }
		python3 -m pip show meson | grep WARNING &>/dev/null && { python3 -m pip install --user meson; }
	fi

	if ! javac -version &>/dev/null; then
		echo "Error: missing Java Development Kit."
		hash yum &>/dev/null && \
			echo "Install it using e.g. sudo yum install java-latest-openjdk-devel"
		apt-get -v &>/dev/null && \
			echo "Install it using e.g. sudo apt-get install default-jre-headless"
		exit 255
	fi

	os_ndk="linux"
elif [ "$os" == "mac" ]; then
	if [ $TRAVIS -eq 0 ]; then
		if ! hash brew 2>/dev/null; then
			echo "Error: brew not found. You need to install Homebrew: https://brew.sh/"
			exit 255
		fi
		brew install \
			automake autoconf libtool pkg-config \
			coreutils gnu-sed wget meson ninja
	fi
	if ! javac -version &>/dev/null; then
		echo "Error: missing Java Development Kit. Install it manually."
		exit 255
	fi

	os_ndk="darwin"
fi

mkdir -p sdk && cd sdk

if [ -n "${ANDROID_SDK_ROOT_OLD}" ]; then
	if [ ! -d "android-sdk-${os}" ]; then
		echo "Using Android SDK defined by ANDROID_SDK_ROOT"
		ln -s "${ANDROID_SDK_ROOT_OLD}" "android-sdk-${os}"
	fi
fi

# Android SDK
if [ ! -d "android-sdk-${os}" ]; then
	echo "Android SDK not found. Downloading commandline tools."
	$WGET "https://dl.google.com/android/repository/commandlinetools-${os}-${v_sdk}.zip"
	mkdir "android-sdk-${os}"
	unzip -q -d "android-sdk-${os}" "commandlinetools-${os}-${v_sdk}.zip"
	rm "commandlinetools-${os}-${v_sdk}.zip"
fi
sdkmanager () {
	local exe="./android-sdk-$os/cmdline-tools/latest/bin/sdkmanager"
	[ -x "$exe" ] || exe="./android-sdk-$os/cmdline-tools/bin/sdkmanager"
	"$exe" --sdk_root="${ANDROID_HOME}" "$@"
}
echo y | sdkmanager \
	"platforms;android-33" "build-tools;${v_sdk_build_tools}" \
	"extras;android;m2repository"

# Android NDK (either standalone or installed by SDK)
if [ -d "android-ndk-${v_ndk}" ]; then
	echo "Android NDK directory found."
	:
elif [ -d "android-sdk-$os/ndk/${v_ndk_n}" ]; then
	echo "Creating NDK symlink to SDK."
	ln -s "android-sdk-$os/ndk/${v_ndk_n}" "android-ndk-${v_ndk}"
elif [ -d "android-sdk-${os}" ] && [ ! -d "android-sdk-$os/ndk/${v_ndk_n}" ]; then
	echo "Downloading NDK with sdkmanager."
	echo y | sdkmanager "ndk;${v_ndk_n}"
	ln -s "android-sdk-$os/ndk/${v_ndk_n}" "android-ndk-${v_ndk}"
elif [ "${os_ndk}" == "linux" ]; then
	echo "Downloading NDK for linux."
	$WGET "http://dl.google.com/android/repository/android-ndk-${v_ndk}-${os_ndk}.zip"
	unzip -q "android-ndk-${v_ndk}-${os_ndk}.zip"
	rm "android-ndk-${v_ndk}-${os_ndk}.zip"
elif [ "${os_ndk}" == "darwin" ]; then
	echo "Downloading NDK for darwin."
	$WGET "http://dl.google.com/android/repository/android-ndk-${v_ndk}-${os_ndk}.dmg"
	echo "NDK for darwin requires manual installation."
	exit 255
fi
if ! grep -qF "${v_ndk_n}" "android-ndk-${v_ndk}/source.properties"; then
	echo "Error: NDK exists but is not the correct version (expecting ${v_ndk_n})"
	exit 255
fi

# gas-preprocessor
if [ ! -f bin/gas-preprocessor.pl ]; then
	mkdir -p bin
	echo "Downloading gas-preprocessor.pl"
	$WGET "https://github.com/FFmpeg/gas-preprocessor/raw/master/gas-preprocessor.pl" \
		-O bin/gas-preprocessor.pl
	chmod +x bin/gas-preprocessor.pl
fi

cd ..
