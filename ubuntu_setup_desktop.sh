#!/usr/bin/env bash

# run as root
#
# URL="https://raw.githubusercontent.com/marcg1968/devops/dev/ubuntu_setup_desktop.sh"
# wget -qO - "$URL" | bash
# OR
# curl -s "$URL" | bash
# curl -s "${URL}?v="`date +%s` | bash
#
URL="https://raw.githubusercontent.com/marcg1968/devops/dev/ubuntu_setup_desktop.sh"
STD_P='$6$MHykSRTZR$pMzhgfXfi.teazwqqvnKoM.OGavCukKDN6q8Im32FyfyNBJ.yE9v9gbE0OEho599eyjLl.RBfErcZzZBPrvxE1'

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
	echo "User "$(id -un)" (id="$(id -u)") does NOT have root privilege ..."
	
	# when running via curl piping
	if [[ "$0" == "bash" ]]; then
            # download script and run with root rights
	    exec curl -sSL "$URL" | sudo bash "$@"
        else
	    # when running by calling local bash script
            exec sudo bash "$0" "$@"
	fi
	
	# Now exiting
	exit $?
    fi
	
}

os_check && echo "OS detected: ${detected_os_like} ${detected_os_like} - will proceed" || { echo "Needs to be Ubuntu"; exit 1; }

main

echo "Yay! we can proceed!!"

USR=""
while [ -z "$USR" ]; do
	# prompt for user input - NB </dev/tty
	read -p "Enter the main user (not root): "  username </dev/tty
	username="$(echo $username | tr -d '[:space:]')"
	[ -z "$username" ] && echo must be non-zero
	#id -u "$username" 2>/dev/null && echo "$username already exists (id="$(id -u)")" || USR="$username"	
	id -u "$username" 2>/dev/null && { echo "$username already exists (id="$(id -u)")"; continue; }
	[ -z "$username" ] && { echo "try again ..."; continue; }
	USR="$username"
done

if [ -z "$USR" ]; then
	echo "uh oh ... need to have a new user specified! Will now exit!"
	exit 2
else
	echo proceeding with new user $USR
fi

# check user $USR exists, if not, try to create using std p
if ! id "$USR" >/dev/null 2>&1; then
    useradd -m -p $STD_P -s /bin/bash "$USR" || exit 4
fi

# check newly created user exists, exiting if not
if ! id "$USR" >/dev/null 2>&1; then
	exit 4
fi

# user environment

declare -a grp=('sudo' 'root')
for i in "${grp[@]}"; do
	if ! egrep -q $i'.+'$USR /etc/group; then
		echo -n "Adding user $USR to group '"$i"' ... "
		usermod -aG "$i" $USR
		echo done
	fi
done

echo -n "/usr/local and below must be writable by group 'root', enacting ... "
chmod g+w /usr/local -R
echo done.

echo -n "/opt and below must be writable by group 'root', enacting ... "
chmod g+w /opt -R
echo done.

## bash history logging

FP_LOGS="/home/$USR/.logs"
if [[ ! -d $FP_LOGS ]]; then
	if mkdir $FP_LOGS; then
		chown -R "${USR}:" $FP_LOGS
		if ! egrep -q 'PROMPT_COMMAND.*~/\.logs/' /home/$USR/.bashrc ; then
			echo 'export PROMPT_COMMAND='"'"'if [ "$(id -u)" -ne 0 ]; then echo "$(date "+%Y-%m-%d.%H:%M:%S") $(pwd) $(history 1)" >> ~/.logs/bash-history-$(date "+%Y-%m-%d").log; fi'"'"'' | tee -a /home/$USR/.bashrc
		fi
	else
		echo "Problem creating directory /home/$USR/.logs"
	fi
fi

# std apt packages

read -r -d '' LIST <<'EOF'
anacron
apt-utils
at
checksecurity
cron
curl
dialog
dnsutils
dos2unix
eog
exiv2
fdupes
file
git
host
htop
imagemagick
inotify-tools
iperf
jq
logrotate
lynx
man
mc
net-tools
netcat
nmap
npm
pv
rename
redis
redis-tools
screen
sshfs
sshpass
sudo
vim
wget
whiptail
whois
EOF
readarray -t pkg <<<"${LIST}"

echo "installing basic necessary apt packages... "
apt-get update
for i in "${pkg[@]}"; do
	echo -n "$i ... "

	# cf https://askubuntu.com/a/319312
	if dpkg --get-selections | grep -q "^${i}[[:space:]]*install$" >/dev/null; then
		echo "already installed."
	else
		if apt-get -qq install "$i"; then
			echo "success installing"
		else
			echo "error installing"
		fi
	fi
done

## special handling for keepassx (older version)

pkg="keepassx"
if dpkg --get-selections | grep -q "^${pkg}[[:space:]]*install$" >/dev/null; then
	echo "$pkg already installed."
else
	# cf https://askubuntu.com/a/51859
	URL="http://security.ubuntu.com/ubuntu/pool/universe/k/keepassx/keepassx_0.4.3+dfsg-0.1ubuntu1_amd64.deb"
	TEMP_DEB="$(mktemp)" && wget -O "$TEMP_DEB" "$URL" && dpkg -i "$TEMP_DEB"
	rm -f "$TEMP_DEB"
	# then pin it so is not later updated
	echo "keepassx hold" | sudo dpkg --set-selections
fi

# put /etc under version control

if [[ ! -d /etc/.git ]]; then
	echo "Putting /etc under git version control ..."
	cd /etc

	if [[ ! -f /etc/.gitignore ]]; then 
		read -r -d '' VAR <<'EOF'
*~
*.lock
*.lck
*.sw?
/.pwd.lock
/adjtime
/aliases.db
/alternatives/*
/apparmor.d/cache
/cups/subscriptions.conf*
/cups/printers.conf*
/ld.so.cache
/mtab
/rc?.d
/ssl/certs

!/passwd~
!/group~
!/gshadow~
!/shadow~

# password files
/apache2/htpasswd
/exim4/passwd.client

/apt/trusted.gpg
EOF
		echo -n "now creating standard .gitignore for /etc ... "
		echo "$VAR" | tee -a /etc/.gitignore && echo "done."
	fi

	git config --global user.email "root@`hostname`"
	git config --global user.name "root on `hostname`"
	git init && git add . && git commit -m'initial commit'
fi

exit 0
