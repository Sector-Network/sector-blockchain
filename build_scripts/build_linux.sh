#!/bin/bash

if [ ! "$1" ]; then
  echo "This script requires either amd64 of arm64 as an argument"
	exit 1
elif [ "$1" = "amd64" ]; then
	PLATFORM="$1"
	REDHAT_PLATFORM="x86_64"
	DIR_NAME="chia-blockchain-linux-x64"
else
	PLATFORM="$1"
	DIR_NAME="chia-blockchain-linux-arm64"
fi

pip install setuptools_scm
# The environment variable SECTOR_INSTALLER_VERSION needs to be defined
# If the env variable NOTARIZE and the username and password variables are
# set, this will attempt to Notarize the signed DMG
SECTOR_INSTALLER_VERSION=$(python installer-version.py)

if [ ! "$SECTOR_INSTALLER_VERSION" ]; then
	echo "WARNING: No environment variable SECTOR_INSTALLER_VERSION set. Using 0.0.0."
	SECTOR_INSTALLER_VERSION="0.0.0"
fi
echo "Sector Installer Version is: $SECTOR_INSTALLER_VERSION"

echo "Installing npm and electron packagers"
npm install electron-packager -g
npm install electron-installer-debian -g
npm install electron-installer-redhat -g

echo "Create dist/"
rm -rf dist
mkdir dist

echo "Create executables with pyinstaller"
pip install pyinstaller==4.2
SPEC_FILE=$(python -c 'import sector; print(sector.PYINSTALLER_SPEC_PATH)')
pyinstaller --log-level=INFO "$SPEC_FILE"
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "pyinstaller failed!"
	exit $LAST_EXIT_CODE
fi

cp -r dist/daemon ../sector-blockchain-gui
cd .. || exit
cd sector-blockchain-gui || exit

echo "npm build"
npm install
npm audit fix
npm run build
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "npm run build failed!"
	exit $LAST_EXIT_CODE
fi

electron-packager . sector-blockchain --asar.unpack="**/daemon/**" --platform=linux \
--icon=src/assets/img/Sector.icns --overwrite --app-bundle-id=net.sector.blockchain \
--appVersion=$SECTOR_INSTALLER_VERSION
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "electron-packager failed!"
	exit $LAST_EXIT_CODE
fi

mv $DIR_NAME ../build_scripts/dist/
cd ../build_scripts || exit

echo "Create sector-$SECTOR_INSTALLER_VERSION.deb"
rm -rf final_installer
mkdir final_installer
electron-installer-debian --src dist/$DIR_NAME/ --dest final_installer/ \
--arch "$PLATFORM" --options.version $SECTOR_INSTALLER_VERSION
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "electron-installer-debian failed!"
	exit $LAST_EXIT_CODE
fi

if [ "$REDHAT_PLATFORM" = "x86_64" ]; then
	echo "Create sector-blockchain-$SECTOR_INSTALLER_VERSION.rpm"
  electron-installer-redhat --src dist/$DIR_NAME/ --dest final_installer/ \
  --arch "$REDHAT_PLATFORM" --options.version $SECTOR_INSTALLER_VERSION \
  --license ../LICENSE
  LAST_EXIT_CODE=$?
  if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	  echo >&2 "electron-installer-redhat failed!"
	  exit $LAST_EXIT_CODE
  fi
fi

ls final_installer/
