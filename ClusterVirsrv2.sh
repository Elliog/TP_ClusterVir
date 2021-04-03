#!/bin/bash
# Nom : ClusterVirsrv1.sh
# Script pour le TP ClusterVIR suivant le cahier des charges TP_HA_5SRC3.txt

# Exemple : ./ClusterVirsrv2.sh

# Auteur : eamiet@myges.fr

# Source : 
# https://github.com/blogmotion/bm-bookstack-install/blob/master/bookstack-install-centos8.sh
# https://www.vultr.com/docs/how-to-install-bookstack-on-debian-9
# Cours virtualisation et clustering de M.NGUYEN
# drbd-Formation.pdf


VERSION="2021.03.04"

### VARIABLES #######################################################################################################################

CURRENT_IP=$(hostname -i)
blanc="\033[1;37m"; gris="\033[0;37m"; magenta="\033[0;35m"; rouge="\033[1;31m"; vert="\033[1;32m"; jaune="\033[1;33m"; bleu="\033[1;34m"; rescolor="\033[0m"

### START SCRIPT #################################################################################################################### 

echo -e "${vert}"
echo -e "#########################################################"
echo -e "#                                                       #"
echo -e "#                ClusterVir Deployment srv2             #"
echo -e "#                                                       #"
echo -e "#               Tested on debian 10 (x64)               #"
echo -e "#                      by @eamiet                       #"
echo -e "#                                                       #"
echo -e "###################### ${VERSION} #######################"
echo -e "${rescolor}\n\n"
sleep 3

### PACKAGES INSTALLATION ##########################################################################################################

echo -e "\n${jaune}Packages installation ...${rescolor}" && sleep 1

apt update && apt upgrade -y

# Package for me :
apt install -y vim tree dstat neofetch figlet lftp htop mlocate rsync lynx net-tools xz-utils

# Global Package :
apt install -y sudo unzip curl git

# Package for DRBD :
apt install -y drbd-utils

# Package for HeartBeat :
apt install -y heartbeat

### SET UP SERVER ##################################################################################################################
echo -e "\n${jaune}Set up server (alias, prompt, etc) ...${rescolor}" && sleep 1

# Beautiful prompt
mv ~/.bashrc ~/.bashrc.old
touch ~/.bashrc
cat <<EOT >> ~/.bashrc
alias cd..='cd ..'
alias ..='cd ..'
alias ll='ls -la'
alias ls='ls --color=auto'
alias c='clear'
alias sha1='openssl sha1'
alias mkdir='mkdir -pv'
alias mount='mount |column -t'
alias edit='nano'
alias ping='ping -c 5'
alias ports='netstat -tulanp'
alias rm='rm -I --preserve-root'
alias mv='mv -i'
alias cp='cp -i'
alias ln='ln -i'
alias chown='chown --preserve-root'
alias chmod='chmod --preserve-root'
alias chgrp='chgrp --preserve-root'
alias update='sudo apt-get update && sudo apt-get upgrade'

export PS1="\[\e[31m\]\u\[\e[m\]@\[\e[36m\]\h\[\e[m\] [\[\e[32m\]\t\[\e[m\]] \[\e[33m\]\w\[\e[m\] \\$ "
EOT

# Beautiful & easy motd
rm -f /etc/update-motd.d/10-uname
echo '#!/bin/sh' >> /etc/update-motd.d/10-uname
echo neofetch >> /etc/update-motd.d/10-uname

# Create User
useradd -m -s /bin/bash eamiet

# Make him superuser
usermod -aG sudo eamiet

### CONFIGURE SSH ###########################################################################################################
echo -e "\n${jaune}Configure SSH ...${rescolor}" && sleep 1

ssh-keygen -t ed25519

# Not working ?
#wget -c ftp://rendu:rendu@83.159.96.56:7222/PROF.id_ed25519.pub

HOST='83.159.96.56:7222'
USER='rendu'
PASSWD='rendu'

# download ssh pub key professor's :
lftp << END_OF_SCRIPT
open sftp://$HOST
user $USER $PASSWD
get PROF.id_ed25519.pub
END_OF_SCRIPT

# Put ssh key in authorized_keys :
cat PROF.id_ed25519.pub >> ~/.ssh/authorized_keys

# Change configuration :
cat <<EOT >> /etc/ssh/sshd_config
PermitRootlogin yes 
PubKeyAuthentication yes 
PasswordAuthentication No
EOT

# Restart for apply config :
systemctl restart sshd.service

### INSTALL & SET UP CHEAT #########################################################################################################
echo -e "\n${jaune}CHEAT (memento) installation ...${rescolor}" && sleep 1

wget https://github.com/cheat/cheat/releases/download/4.2.0/cheat-linux-amd64.gz
gunzip  cheat-linux-amd64.gz
chmod +x cheat-linux-amd64
mv cheat-linux-amd64  /usr/local/bin/cheat

# Cheat en mode partagé
mkdir /opt/MEMENTO
groupadd memento
chgrp memento MEMENTO
chmod -v 2770 MEMENTO
mv /root/.config/cheat   /opt/MEMENTO
find /opt/ -type d -exec chmod  2770 {} \;
find /opt/ -type d -exec chmod 660 {} \;
chgrp -R memento /opt/MEMENTO

# For rollback :
cp /opt/MEMENTO/cheat/conf.yml /opt/MEMENTO/cheat/conf.yml.old

# Change config' lines :
sed -i '50 d' /opt/MEMENTO/cheat/conf.yml
sed -i '50 i  \    path: /opt/MEMENTO/cheat/cheatsheets/community' /opt/MEMENTO/cheat/conf.yml
sed -i '57 d' /opt/MEMENTO/cheat/conf.yml
sed -i '57 i  \    path: /opt/MEMENTO/cheat/cheatsheets/personal' /opt/MEMENTO/cheat/conf.yml

echo '# rep=777-007=770 666-006=660' >> /etc/bash.bashrc
echo 'umask=007' >> /etc/bash.bashrc

# Set up link for eamiet
mkdir /home/eamiet/.config
ln -s  /opt/MEMENTO/cheat /home/eamiet/.config/cheat

# Set up link for user
mkdir /home/user/.config
ln -s  /opt/MEMENTO/cheat /home/user/.config/cheat

### INSTALL DRBD ###################################################################################################################
echo -e "\n${jaune}DRBD installation ...${rescolor}" && sleep 1

# Load module :
modprobe drbd

# Add srv :
cat <<EOT >>> /etc/hosts
10.254.2.85 sd10-2801 sd10-2801.esgi.local
10.254.3.225 sd10-2801 sd10-2801.esgi.local
10.254.3.226 sd10-2802 sd10-2802.esgi.local
EOT

# For rollback :
# cp /etc/drbd.d/global_common.conf /etc/drbd.d/global_common.conf.old

# DRBD configuration should be the same on both nodes : 
# cat <<EOT >>> /etc/drbd.d/global_common.conf
# global {
#     usage-count no;
# }
# common {    
#     protocol C;
#     startup {
#         wfc-timeout 1 ;
#         degr-wfc-timeout 1 ;
#     }
#     net {
#         max-buffers 8192;
#         max-epoch-size 8192;
#         sndbuf-size 512k;
#         unplug-watermark 8192;
#         process pending I/O requests
#         cram-hmac-alg sha1;
#         shared-secret "xxx";
#         # Split brains
#         after-sb-0pri disconnect;
#         after-sb-1pri disconnect;
#         after-sb-2pri disconnect;
#         rr-conflict disconnect;
#     }
#     handlers {
#         pri-on-incon-degr "echo node is primary, degraded and the local copy of the data is
#                            inconsistent | wall ";
#     }
#     disk {
#         on-io-error pass_on;
#         no-disk-barrier;                       
#         no-disk-flushes;                        
#         no-disk-drain;                      
#         reordering domain are issued
#         no-md-flushes;                      
#     } 
#     syncer {
#         rate 300M;                      
#         re-synchronization
#         al-extents 3833;                        
#     }
# }
# EOT

# Configuration resources:
cat <<EOT >>> /etc/drbd.d/r0.res
resource drbd0 {
    syncer {rate 10M; }

    on sd10-2801 {
            device /dev/drbd0;
            disk /dev/sda2;
            address 10.254.2.85:7789;
            meta-disk internal;
    }

    on sd10-2802 {
            device /dev/drbd0;
            disk /dev/sda2;
            address 10.254.2.86:7789;
            meta-disk internal;
    }
}
EOT

# Init metadata device :
drbdadm create-md drbd0
drbdadm attach drbd0
drbdadm connect drbd0

# Start synchronization :
drbdadm secondary drbd0

# Check :
# cat / proc / drbd
# drbd - overview

### INSTALL HEARTBEAT ##############################################################################################################
echo -e "\n${jaune}Heartbeat installation ...${rescolor}" && sleep 1

# First configuration file /etc/heartbeat/ha.cf :
cat <<EOT >>> /etc/heartbeat/ha.cf
logfile /var/log/heartbeat.log
logfacility daemon
node sd10-2801
node sd10-2802
keepalive 1
deadtime 10
bcast 
ping 192.168.1.1
auto_failback yes
EOT

# 2nd configuration file /etc/drbd/haresources :
echo Debian 10.254.3.228 drbddisk::drbd0 Filesystem::/md1 >> /etc/drbd/haresources

# 3th configuration file /etc/drbd/authkeys :
cat <<EOT >>> /etc/drbd/haresources
auth 1 
1 sha1 SecreteKey
EOT

#Change rights :
chmod 600 /etc/ha.d/authkeys

# Enable service on boot :
systemctl enable drbd

####################################################################################################################################

echo -e "\n\n"
echo -e "\t * 1 * ${vert}Deployement finished whithout error ! ${rescolor}"
echo -e "\t * 2 * ${rouge}PLEASE add password to eamiet user cmd: passwd eamiet ${rescolor}"
echo -e "\n\t${magenta} --- END OF SCRIPT (v${VERSION}) ---  \n\n\n ${rescolor}"

exit 0