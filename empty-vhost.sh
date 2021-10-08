#!/usr/bin/env bash

APACHE_LOG_DIR="/var/log/apache2"
EMAIL="mgreyling@gmail.com"

[ $(id -u) == "0" ] || { echo "Need to run script as root"; exit 1; }

(( $# < 1 )) && { echo "Domain as arg1 missing!"; exit 1; } || { echo "Domain: ""$1"; DOMAIN="$1"; }

DIR="/var/www/html/$DOMAIN"
DBNAME=$(echo ${DOMAIN%%.*} | tr -d -c '[[:alnum:]]')

for i in `hostname -I`; do [[ $i =~ "127"* || $i =~ "::"* ]] && continue || { IP="$i"; break; }; done
echo "IP: $IP"

## Initial checks

echo -n "Checking if domain $DOMAIN resolves to this host's IP $IP ..."
_IP=""
if which getent >/dev/null; then
	_IP=$(getent hosts $DOMAIN | awk '{ print $1 ; exit }')
elif which dig >/dev/null; then
	_IP=$(dig +short $DOMAIN | awk '{ print ; exit }')
else
	echo -e "\nNeither 'dig' nor 'getent' available on this system. Exiting." 
	exit 2
fi

echo ""
if [[ ! -z _$IP && "$_IP" == "$IP" ]]; then
	echo "Yay, this host's IP, $IP matches the domain name resolution $_IP"
else
	echo "Uh oh! This host's IP, $IP does not match the domain name resolution ${_IP}."
	echo "Does the DNS entry for $DOMAIN exist?"
fi

if [ -d "$DIR" ] && find "$DIR" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
	echo -e "\nDirectory $DIR already exists and is not empty. Exiting."
	exit 8
elif mkdir -p "$DIR"; then
	echo -e "\nSuccess creating dir $DIR ."
else
	echo -e "\nFailed to create directory $DIR. Exiting."
	exit 16
fi

echo -n "Now setting permissions ... "
cd $DIR
chown www-data:www-data -R . # Let Apache be owner
find . -type d -exec sudo chmod 755 {} \;  # Change directory permissions rwxr-xr-x
find . -type f -exec sudo chmod 644 {} \;  # Change file permissions rw-r--r--

echo Exit code now: $?

SITE="05-${DOMAIN}.conf"
F="/etc/apache2/sites-available/$SITE"
if [[ -f "$F" ]]; then
	echo "$F already exits"
else
	echo "Creating apache2 vhost conf file $F ... "
	read -r -d '' CONF <<EOF
<VirtualHost *:80>
        ServerName      ${DOMAIN}
        ServerAdmin     adm@neuesziel.de
        DocumentRoot    ${DIR}
        SetEnvIf        Request_URI "^/favicon.ico" dontlog

        ErrorLog ${APACHE_LOG_DIR}/${DOMAIN}-error.log
        CustomLog ${APACHE_LOG_DIR}/${DOMAIN}-access.log combined env=!dontlog

        <Directory ${DIR}>
                RewriteEngine On
                RewriteCond %{REQUEST_FILENAME} !-f
                RewriteCond %{REQUEST_FILENAME} !-d
                RewriteRule . index.php
        </Directory>

        # hide .git directory
        <DirectoryMatch /\.git/>
                Order deny,allow
                Deny from all
        </DirectoryMatch>

</VirtualHost>
EOF
	echo "${CONF}" | tee -a "$F"
	a2ensite "$SITE"
fi

# SSL
if certbot certificates 2>/dev/null | egrep -q 'Domains:.*'${DOMAIN}; then 
	echo "SSL certificate for $DOMAIN already exists."
elif ! which certbot; then
	echo "Need to install certbot. Exiting."
	exit 128
else
	echo "Getting SSL certificate ... "
	#certbot certonly -n --agree-tos --no-eff-email --email $EMAIL --redirect -d $DOMAIN --apache
	#if certbot -n --agree-tos --no-eff-email --email $EMAIL --redirect -d $DOMAIN --apache; then
	if certbot -n --agree-tos --no-eff-email --email $EMAIL --no-redirect -d $DOMAIN --apache; then
		service apache2 graceful
	fi
fi

echo "Try accessing new WP site at https://"$DOMAIN




