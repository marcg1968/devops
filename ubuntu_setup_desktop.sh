#!/usr/bin/env bash

# run as root
#
# URL="https://www.dropbox.com/s/sgwpa3mez110965/common_setup_desktop.sh?dl=1"
# wget -O - "$URL" | bash
#

[ $(id -u) == "0" ] || { echo "Need to run script as root"; exit 1; }

USR="marc"
GIT_DOTFILES="git@bitbucket.org:marcg68/dotfiles.git"

# check user `marc` exists, if not, try to create using std pw
if ! id "$USR" >/dev/null 2>&1; then
    useradd -m -p '$6$MHykSRTZR$pMzhgfXfi.teazwqqvnKoM.OGavCukKDN6q8Im32FyfyNBJ.yE9v9gbE0OEho599eyjLl.RBfErcZzZBPrvxE1' -s /bin/bash marcp
fi

# check user `marc` exists, exiting if not
if ! id "$USR" >/dev/null 2>&1; then
	exit 2
fi

# user environment

declare -a grp=('sudo' 'root')
for i in "${grp[@]}"; do
	if ! egrep -q $i'.+'$USR /etc/group; then
		echo -n "Adding user $USR to group '"$i"' ... "
		usermod -aG "$i" $USR
		#usermod -aG root $USR
		echo done
	fi
done

