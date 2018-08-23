#!/bin/bash
# RESPAWN Masternode Setup Script V1.4 for Ubuntu 16.04 LTS
# (c) 2018 by Dwigt007, Modified by Eswede for RPWN
#
# Script will attempt to autodetect primary public IP address
# and generate masternode private key unless specified in command line
#
# Usage:
# bash RPWN-setup.sh [Masternode_Private_Key]
#
# Example 1: Existing genkey created earlier is supplied
# bash RPWN-setup.sh 27dSmwq9CabKjo2L3UD1HvgBP3ygbn8HdNmFiGFoVbN1STcsypy
#
# Example 2: Script will generate a new genkey automatically
# bash RPWN-setup.sh
#

#Color codes
RED='\033[0;91m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#RESPAWN TCP port
PORT=9321
VERSION=v0.12.5.4

#Clear keyboard input buffer
function clear_stdin { while read -r -t 0; do read -r; done; }

#Delay script execution for N seconds
function delay { echo -e "${GREEN}Sleep for $1 seconds...${NC}"; sleep "$1"; }

#Stop daemon if it's already running
function stop_daemon {
    if pgrep -x 'RPWNd' > /dev/null; then
        echo -e "${YELLOW}Attempting to stop RPWNd${NC}"
        RPWN-cli stop
        delay 30
        if pgrep -x 'RPWNd' > /dev/null; then
            echo -e "${RED}RPWNd daemon is still running!${NC} \a"
            echo -e "${YELLOW}Attempting to kill...${NC}"
            pkill RPWNd
            delay 30
            if pgrep -x 'RPWNd' > /dev/null; then
                echo -e "${RED}Can't stop RPWNd! Reboot and try again...${NC} \a"
                exit 2
            fi
        fi
    fi
}

#Process command line parameters
genkey=$1

clear
echo -e "${YELLOW}(c) 2018 by Dwigt007, Modified by Eswede for RESPAWN Masternode Setup Script V1.4 for Ubuntu 16.04 LTS${NC}"
echo -e "${GREEN}Updating system and installing required packages...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get update -y

# Determine primary public IP address
dpkg -s dnsutils 2>/dev/null >/dev/null || sudo apt-get -y install dnsutils
publicip=$(dig +short myip.opendns.com @resolver1.opendns.com)

if [ -n "$publicip" ]; then
    echo -e "${YELLOW}IP Address detected:" $publicip ${NC}
else
    echo -e "${RED}ERROR: Public IP Address was not detected!${NC} \a"
    clear_stdin
    read -e -p "Enter VPS Public IP Address: " publicip
    if [ -z "$publicip" ]; then
        echo -e "${RED}ERROR: Public IP Address must be provided. Try again...${NC} \a"
        exit 1
    fi
fi

# update packages and upgrade Ubuntu
#sudo apt-get -y upgrade
#sudo apt-get -y dist-upgrade
#sudo apt-get -y autoremove
apt-get -y update
apt-get -y install wget nano htop jq
apt-get -y install libzmq3-dev
apt-get -y install libboost-system-dev libboost-filesystem-dev libboost-chrono-dev libboost-program-options-dev libboost-test-dev libboost-thread-dev
apt-get -y install libevent-dev

apt -y install software-properties-common
add-apt-repository ppa:bitcoin/bitcoin -y
apt-get -y update
apt-get -y install libdb4.8-dev libdb4.8++-dev

apt-get -y install libminiupnpc-dev

apt-get -y install fail2ban
service fail2ban restart

# Installing and configuring firewall
apt-get install ufw -y
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow $PORT/tcp
ufw allow 22/tcp
ufw limit 22/tcp
echo -e "${YELLOW}"
ufw --force enable
echo -e "${NC}"

#Generating Random Password for JSON RPC
rpcuser=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
rpcpassword=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

#Create 2GB swap file
if grep -q "SwapTotal" /proc/meminfo; then
    echo -e "${GREEN}Skipping disk swap configuration...${NC} \n"
else
    echo -e "${YELLOW}Creating 2GB disk swap file. \nThis may take a few minutes!${NC} \a"
    touch /var/swap.img
    chmod 600 swap.img
    dd if=/dev/zero of=/var/swap.img bs=1024k count=2000
    mkswap /var/swap.img 2> /dev/null
    swapon /var/swap.img 2> /dev/null
    if [ $? -eq 0 ]; then
        echo '/var/swap.img none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}Swap was created successfully!${NC} \n"
    else
        echo -e "${YELLOW}Operation not permitted! Optional swap was not created.${NC} \a"
        rm /var/swap.img
    fi
fi

#Installing Daemon
wget https://github.com/RespawnPay/RPWN/releases/download/v.0.12.5.4/RPWN.linux_x64.$VERSION.tar.gz
tar -xvf RPWN.linux_x64.$VERSION.tar.gz --one-top-level
rm -rf RPWN.linux_x64.$VERSION.tar.gz

stop_daemon

# Deploy binaries to /usr/bin
cp ./RPWN.linux_x64.$VERSION/RPWN* /usr/bin/
chmod 755 /usr/bin/RPWN*

# Deploy masternode monitoring script
# cp ~/RPWNmasternodesetup/nodemon.sh /usr/local/bin
# chmod 711 /usr/local/bin/nodemon.sh

#Create datadir
if [ ! -f ~/.RPWNcore/RPWN.conf ]; then 
	sudo mkdir ~/.RPWNcore
fi

echo -e "${YELLOW}Creating RPWN.conf...${NC}"

# If genkey was not supplied in command line, we will generate private key on the fly
if [ -z $genkey ]; then
    cat <<EOF > ~/.RPWNcore/RPWN.conf
rpcuser=$rpcuser
rpcpassword=$rpcpassword
EOF

    chmod 755 -R ~/.RPWNcore/RPWN.conf

    #Starting daemon first time just to generate masternode private key
    RPWNd -daemon
    delay 30

    #Generate masternode private key
    echo -e "${YELLOW}Generating masternode private key...${NC}"
    genkey=$(RPWN-cli masternode genkey)
    if [ -z "$genkey" ]; then
        echo -e "${RED}ERROR: Can not generate masternode private key.${NC} \a"
        echo -e "${RED}ERROR:${YELLOW}Reboot VPS and try again or supply existing genkey as a parameter.${NC}"
        exit 1
    fi
    
    #Stopping daemon to create RPWN.conf
    stop_daemon
    delay 30
fi

# Create RPWN.conf
cat <<EOF > ~/.RPWNcore/RPWN.conf
rpcuser=$rpcuser
rpcpassword=$rpcpassword
rpcallowip=127.0.0.1
onlynet=ipv4
listen=1
server=1
daemon=1
maxconnections=64
externalip=$publicip
masternode=1
masternodeprivkey=$genkey
addnode=155.4.33.0
addnode=155.4.34.199
addnode=155.4.34.192
EOF

#Finally, starting RPWN daemon with new RPWN.conf
RPWNd -daemon
delay 5

#Setting auto star cron job for RPWNd
cronjob="@reboot sleep 30 && RPWNd -daemon"
crontab -l > tempcron
if ! grep -q "$cronjob" tempcron; then
    echo -e "${GREEN}Configuring crontab job...${NC}"
    echo $cronjob >> tempcron
    crontab tempcron
fi
rm tempcron

echo -e "========================================================================
${YELLOW}Masternode setup is complete!${NC}
========================================================================
Masternode was installed with VPS IP Address: ${YELLOW}$publicip${NC}
Masternode Private Key: ${YELLOW}$genkey${NC}
Now you can add the following string to the masternode.conf file
for your Hot Wallet (the wallet with your 3000 RPWN collateral funds):
======================================================================== \a"
echo -e "${YELLOW}mn1 $publicip:$PORT $genkey TxId TxIdx${NC}"
echo -e "========================================================================
Use your mouse to copy the whole string above into the clipboard by
tripple-click + single-click (Dont use Ctrl-C) and then paste it 
into your ${YELLOW}masternode.conf${NC} file and replace:
    ${YELLOW}mn1${NC} - with your desired masternode name (alias)
    ${YELLOW}TxId${NC} - with Transaction Id from masternode outputs
    ${YELLOW}TxIdx${NC} - with Transaction Index (0 or 1)
     Remember to save the masternode.conf and restart the wallet!
To introduce your new masternode to the RPWN network, you need to
issue a masternode start command from your wallet, which proves that
the collateral for this node is secured."

clear_stdin
read -p "*** Press any key to continue ***" -n1 -s

echo -e "1) Wait for the node wallet on this VPS to sync with the other nodes
on the network. Eventually the 'IsSynced' status will change
to 'true', which will indicate a comlete sync, although it may take
from several minutes to several hours depending on the network state.
Your initial Masternode Status may read:
    ${YELLOW}Node just started, not yet activated${NC} or
    ${YELLOW}Node  is not in masternode list${NC}, which is normal and expected.
2) Wait at least until 'IsBlockchainSynced' status becomes 'true'.
At this point you can go to your wallet and issue a start
command by either using Debug Console:
    Tools->Debug Console-> enter: ${YELLOW}masternode start-alias mn1${NC}
    where ${YELLOW}mn1${NC} is the name of your masternode (alias)
    as it was entered in the masternode.conf file
    
or by using wallet GUI:
    Masternodes -> Select masternode -> RightClick -> ${YELLOW}start alias${NC}
Once completed step (2), return to this VPS console and wait for the
Masternode Status to change to: 'Masternode successfully started'.
This will indicate that your masternode is fully functional and
you can celebrate this achievement!
Currently your masternode is syncing with the RESPAWN network...
The following screen will display in real-time
the list of peer connections, the status of your masternode,
node synchronization status and additional network and node stats.
"
clear_stdin
read -p "*** Press any key to continue ***" -n1 -s

echo -e "
${GREEN}...scroll up to see previous screens...${NC}
Here are some useful commands and tools for masternode troubleshooting:
========================================================================
To view masternode configuration produced by this script in RPWN.conf:
${YELLOW}cat ~/.RPWNcore/RPWN.conf${NC}
Here is your RPWN.conf generated by this script:
-------------------------------------------------${YELLOW}"
cat ~/.RPWNcore/RPWN.conf
echo -e "${NC}-------------------------------------------------
NOTE: To edit RPWN.conf, first stop the RPWNd daemon,
then edit the RPWN.conf file and save it in nano: (Ctrl-X + Y + Enter),
then start the RPWNd daemon back up:
to stop:   ${YELLOW}RPWN-cli stop${NC}
to edit:   ${YELLOW}nano ~/.RPWNcore/RPWN.conf${NC}
to start:  ${YELLOW}RPWNd${NC}
========================================================================
To view RPWNd debug log showing all MN network activity in realtime:
${YELLOW}tail -f ~/.RPWNcore/debug.log${NC}
========================================================================
To monitor system resource utilization and running processes:
${YELLOW}htop${NC}
========================================================================
To view the list of peer connections, status of your masternode, 
sync status etc. in real-time, run the nodemon.sh script:
${YELLOW}nodemon.sh${NC}
or just type 'node' and hit <TAB> to autocomplete script name.
========================================================================
Enjoy your RPWN Masternode and thanks for using this setup script!
If you found this script and masternode setup guide helpful...,

...please donate to the devfound: RPWN  **oMoN1fqkp7Rz9QfRDPAsjsfKM2uNskq76V**,
or BTC to **1HA19fBDYPPCFuaLemWbNFnDRGXpfNG2Ui**

Eswede
"
# Run nodemon.sh
#nodemon.sh

# EOF
