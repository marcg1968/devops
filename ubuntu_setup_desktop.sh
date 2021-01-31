#!/usr/bin/env bash

# run as root
#
# URL="https://raw.githubusercontent.com/marcg1968/devops/dev/ubuntu_setup_desktop.sh"
# wget -qO - "$URL" | bash
# OR
# curl -s "$URL" | bash
#
URL="https://raw.githubusercontent.com/marcg1968/devops/dev/ubuntu_setup_desktop.sh"

os_check() {
    detected_os=$(grep "\bID\b" /etc/os-release | cut -d '=' -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
    detected_os_like=$(grep "\bID_LIKE\b" /etc/os-release | cut -d '=' -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
    #detected_version=$(grep VERSION_ID /etc/os-release | cut -d '=' -f2 | tr -d '"')
    [[ "$detected_os" == "ubuntu" || "$detected_os_like" == "ubuntu" ]] || return 1
    return 0
}

main() {
    if [ "$(id -u)" -eq 0 ]; then
        # user is root and good to go
	echo "User has root privilege"
    else
    	# assume sudo command exists
	
	# when running via curl piping
	if [[ "$0" == "bash" ]]; then
            # download script and run with root rights
	    exec curl -sSL "$URL" | sudo bash "$@"
        else
	    # when running by calling local bash script
            exec sudo bash "$0" "$@"
	fi
    fi
	
}

os_check && echo "OS detected: ${detected_os_like} ${detected_os_like} - will proceed" || { echo "Needs to be Ubuntu"; exit 1; }

main


exit 0

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

