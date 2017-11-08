#!/usr/bin/env bash
# wget https://raw.githubusercontent.com/xhrfc/xmail/master/installer.sh -v -O installer.sh; chmod +x installer.sh; ./installer.sh; rm -rf installer.sh
clear
if [[ $EUID -ne 0 ]]; then
	echo "Please run this script as root" 1>&2
	exit 1
fi

echo "--------------------------------------------------------------"
echo "# Email Server Installer. (v.0.1)"
echo "# Never use this script for sending unsolicited emails (spam)."
echo "--------------------------------------------------------------"
echo
read -p "Mail server domain: " -r DOMAIN
read -p "Mail server name: " -r HOSTNAME
read -p "Public mail server IP: " -r IP
echo
read -p "Is everything fine? [ $HOSTNAME.$DOMAIN - $IP ] [Y/N]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "[1] Hostname setup"
    cd /root
    mkdir /root/settings
    hostname $HOSTNAME.$DOMAIN
    echo $HOSTNAME.$DOMAIN > /etc/hostname
    touch /etc/mailname
    echo $DOMAIN > /etc/mailname

    cat <<-EOF > /etc/hosts
	127.0.1.1   localhost localhost.localdomain
	${IP}   ${HOSTNAME} ${HOSTNAME}.${DOMAIN}
	EOF

    echo "[2] Removing previous installs if any"
    apt-get remove -qq -y exim4 exim4-base exim4-config exim4-daemon-light postfix  > /dev/null 2>&1
    rm -r /var/log/exim4/  > /dev/null 2>&1

    echo "[3] Updating and Installing Dependicies"
    echo -e "** System update"
    apt-get -qq update  > /dev/null 2>&1
    echo -e "** Installing nodejs repository"
    curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash - > /dev/null 2>&1
    echo -e "** Installing build compilers"
	apt-get install -qq -y build-essential > /dev/null 2>&1
	echo -e "** Installing htop"
	apt-get install -qq -y htop > /dev/null 2>&1
	echo -e "** Installing unzip"
	apt-get install -qq -y unzip > /dev/null 2>&1
	echo -e "** Installing curl"
	apt-get install -qq -y curl > /dev/null 2>&1
	echo -e "** Installing pflogsumm"
	apt-get install -qq -y pflogsumm > /dev/null 2>&1
	echo -e "** Installing nodejs"
	apt-get install -qq -y nodejs > /dev/null 2>&1
	export DEBIAN_FRONTEND=noninteractive > /dev/null 2>&1
	echo -e "** Installing postfix"
	apt-get install -qq -y postfix > /dev/null 2>&1
	echo -e "** Installing opendkim"
	apt-get install -qq -y opendkim opendkim-tools > /dev/null 2>&1

    echo "[4] Configuring packages"
    echo -e "** Configuring Postfix"
    cat <<-EOF > /etc/postfix/main.cf
	smtpd_banner = \$myhostname ESMTP \$mail_name (Ubuntu)
biff = no
append_dot_mydomain = no
readme_directory = no
smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
smtpd_use_tls=yes
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache
smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = ${HOSTNAME}.${DOMAIN}
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
myorigin = /etc/mailname
mydestination = \$myhostname, ${DOMAIN}, ${HOSTNAME}.${DOMAIN}, localhost
relayhost =
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = all
milter_protocol = 2
milter_default_action = accept
smtpd_milters = inet:localhost:12301
non_smtpd_milters = inet:localhost:12301
smtpd_tls_security_level = may
smtp_tls_security_level = may
smtp_tls_loglevel = 1
smtpd_tls_loglevel = 1
EOF
    echo -e "** Configuring OpenDKIM"
    cat <<-EOF > /etc/opendkim.conf
AutoRestart             Yes
AutoRestartRate         10/1h
UMask                   002
Syslog                  yes
SyslogSuccess           Yes
LogWhy                  Yes
Canonicalization        relaxed/simple
ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
Mode                    sv
PidFile                 /var/run/opendkim/opendkim.pid
SignatureAlgorithm      rsa-sha256
UserID                  opendkim:opendkim
Socket                  inet:12301@localhost
EOF
    mkdir -p /etc/opendkim/keys
    echo 'SOCKET="inet:12301@localhost"' >> /etc/default/opendkim
    echo '127.0.0.1' >> /etc/opendkim/TrustedHosts
    echo 'localhost' >> /etc/opendkim/TrustedHosts
    echo "*.${DOMAIN}" >> /etc/opendkim/TrustedHosts
    echo "mail._domainkey.${DOMAIN} ${DOMAIN}:mail:/etc/opendkim/keys/${DOMAIN}/mail.private" >> /etc/opendkim/KeyTable
    echo "*@${DOMAIN} mail._domainkey.${DOMAIN}" >> /etc/opendkim/SigningTable
    mkdir /etc/opendkim/keys/$DOMAIN
    cd /etc/opendkim/keys/$DOMAIN
    opendkim-genkey -s mail -d $DOMAIN
    chown opendkim:opendkim mail.private

    ldconfig
    echo "[5] Saving settings in /root/settings"
    echo -e "** Saving SPF Record"
    echo "v=spf1 mx a ip4:${IP} ~all" > /root/settings/spf.$DOMAIN.txt
    echo -e "** Saving DKIM Record"
    cat /etc/opendkim/keys/$DOMAIN/mail.txt > /root/settings/mail._domainkey.$DOMAIN.txt
    echo -e "** Saving DMARK Record"
    echo "v=DMARC1; p=none" > /root/settings/_dmarc.$DOMAIN.txt

    echo "[6] Restarting services"
    echo -e "** postfix"
    service postfix restart
    echo -e "** openDKIM"
    service opendkim restart

    echo "[7] Fetching email marketing software"
    cd /root/
    git clone https://github.com/xhrfc/xmail.git > /dev/null 2>&1
    cd /root/xmail
    npm install > /dev/null 2>&1
    echo "** Email software saved in /root/xmail/";

    read -p "Do you want to reboot this machine? (Y/N)" -n 1 -r
    echo
        if [[ $REPLY =~ ^[Yy]$ ]]
        then
            reboot
        fi
fi

exit 0