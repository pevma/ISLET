#!/usr/bin/env bash
# Author: Jon Schipp <jonschipp@gmail.com>
# Written for Ubuntu Saucy and Trusty, should be adaptable to other distros.

# Installation notification (not implemented yet)
MAIL="$(which mail 2>/dev/null)"
COWSAY=/usr/games/cowsay
IRCSAY=/usr/local/bin/ircsay
IRC_CHAN="#replace_me"
HOST="$(hostname -s)"
LOGFILE=install.log
EMAIL=user@company.com

# System Configuration
USER="demo" 			# User account to create for that people will ssh into to enter container
PASS="demo" 			# Password for the account that users will ssh into
GROUP="islet"                   # ISLET Group, used for permissions of database
SIZE=2G				# Maximum size of containers, DoS prevention
SSH_CONFIG=/etc/ssh/sshd_config
CONTAINER_DESTINATION= 		# Put containers on another volume e.g. /dev/sdb1 (optional). You must mkfs.$FS first!
FS="ext4"			# Filesystem type for CONTAINER_DESTINATION, used for mounting
INSTALL_DIR=/opt/islet	 	# ISLET component directory
BIN_DIR="$INSTALL_DIR/bin"   	# Directory to install islet scripts
SHELL="$BIN_DIR/islet_shell"	# $USER's shell and container launcher

# Other Declarations
RESTART_SSH=0
RESTART_DOCKER=0
LIMITS=/etc/security/limits.d
DEFAULT=/etc/default/docker
UPSTART=/etc/init/docker.conf

# Logging
#exec > >(tee -a "$LOGFILE") 2>&1
#printf "\n --> Logging stdout & stderr to ${LOGFILE}\n"

die(){
  if [[ -f "${COWSAY:-none}" ]]; then
    "$COWSAY" -d "$*"
  else
    printf "$(tput setaf 1)$*$(tput sgr0)\n"
  fi
  if [[ -f "$IRCSAY" ]]; then
    ( set +e; "$IRCSAY" "$IRC_CHAN" "$*" 2>/dev/null || true )
  fi
  if [[ -f "${MAIL:-none}" ]]; then
    echo "$*" | mail -s "[vagrant] Bro Sandbox install information on $HOST" "$EMAIL"
  fi

  exit 1
}

hi(){
  if [[ -f "${COWSAY:-none}" ]]; then
    "$COWSAY" "$*"
  else
    printf "$(tput setaf 3)$*$(tput sgr0)\n"
  fi
  if [[ -f "$IRCSAY" ]]; then
    ( set +e; "$IRCSAY" "$IRC_CHAN" "$*" 2>/dev/null || true )
  fi
  if [[ -f "${MAIL:-none}" ]]; then
    echo "$*" | mail -s "[vagrant] Bro Sandbox install information on $HOST" "$EMAIL"
  fi
}

template(){
cat <<"EOF"
# System Configuration
ENVIRONMENT="jonschipp/islet-netsniff-ng"                     # Launch containers from this image, must match name in Docker exactly.
DESCRIPTION="Netsniff-NG Toolkit training image"        # Brief description of image, shown in selection menu

# Security Configuration
VISIBLE="yes"                                           # This config file is visible from config selection menu
DAYS="3"                                                # Container lifetime specified in days, removed after x days by cron jobs
REMOVE="no"                                             # Container is removed after exit, user cannot re-attach and resume work
TIMEOUT="4h"                                            # Max runtime of containers, accepts timeout(1) arguments

# Container Configuration
VIRTUSER="demo"                                         # Account used when container is entered (Must exist in image!)
CPUSHARES="1024"                                        # Proportion of cpu share allocation per container
MEMORY="256m"                                              # Amount of memory allocated to each container
HOSTNAME="netsniff-ng"                                  # Set hostname in container. PS1 will end up as $VIRTUSER@$HOSTNAME:~$ in shell
NETWORK="none"                                          # Disable networking by default: none; Enable networking: bridge
DNS="127.0.0.1"                                         # Use loopback when networking is disabled to prevent error messages from resolver
MOUNT="-v /exercises:/exercises:ro"                     # Mount point(s), sep. by -v: /src:/dst:attributes, ro = readonly (avoid rw if possible)
LOCAL_OPTIONS="--cap-add=NET_RAW --cap-add=NET_ADMIN"   # Apply any other options you want passed to Docker run here
LOCAL_ENV=""                                            # Variables that get passed to VIRTUSER's shell for container

# Branding & Information
MOTD="Training materials are in /exercises
e.g. $ netsniff-ng --in /exercises/pcap/traffic.pcap"   # Message of the day is displayed before entering container
BANNER="
=================================================================

Welcome to Netsniff-NG Configuration!

netsniff-ng is a free, performant Linux network analyzer and
linux network analyzer and  networking toolkit. If you will,
the Swiss army knife for network packets.

Web: http://netsniff-ng.org

                /(      )\\
              ./ {______} \.
               \ ^,    ,^ /
                |'O\  /O'|     _.<0101011>--
                > \`'  '\` <  /
                ) ,.==., (  |
             .-(|/--~~--\|)-'
             (      ___
              \__.=|___E

A place to try out Netsniff-NG

=================================================================
"
EOF
}

logo(){
cat <<"EOF"
===============================================================

   ISLET: A Linux-based Software Training System

(I)solated,
	  (S)calable,
		     & (L)ightweight (E)nvironment
						 for (T)raining

   Web: https://github.com/jonschipp/islet

===============================================================
EOF
}

is_ubuntu(){
  if ! lsb_release -s -d 2>/dev/null | egrep -q 'Ubuntu|Debian'; then
    die "Debian or Ubuntu Linux is required for installation!"
  fi
}

install_docker(){
  is_ubuntu
  hi "  Installing Docker!\n"

 # Install docker
 # If not found intall docker following Docker for Bionic instructions
 # https://docs.docker.com/install/linux/docker-ce/ubuntu/
  if ! command -v docker >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -qy apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt-get update -qq
    apt-get install -y docker-ce
    #apt-get install -qy lxc-docker linux-image-extra-$(uname -r) aufs-tools
  fi
}

docker_configuration(){
  local RESTART=0
  local SIZE="${1:-$SIZE}"
  if command -v docker >/dev/null 2>&1; then
    # Set devicemapper storage limit
    [[ -f /etc/init.d/docker ]] && service docker stop 2>&1 >/dev/null || stop -q docker 2>/dev/null
    sleep 1
    [[ -d /var/lib/docker/aufs ]] && umount /var/lib/docker/aufs
    [[ -d /var/lib/docker/devicemapper ]] && umount /var/lib/docker/devicemapper
    rm -rf /var/lib/docker/* || die "Unable to remove /var/lib/docker!"
    docker -d --storage-driver=devicemapper --storage-opt dm.basesize="$SIZE" &
    sleep 3
    pkill docker
    sed -i '/DOCKER_OPTS/d' "$DEFAULT"
    echo DOCKER_OPTS=\"--storage-driver=devicemapper --storage-opt dm.basesize=$SIZE\" >> "$DEFAULT"
    [[ -f /etc/init.d/docker ]] && RESTART=1 && service docker start || die "Docker did not start correctly!"
    [[ "$RESTART" -eq 0 ]] && [[ -f /etc/init/docker.conf ]] && start -q docker || hi "Docker started!" && exit 0
  else
     die "Docker is required for configuration!"
  fi
}

user_configuration(){
  local USER="${1:-$USER}"
  local PASS="${2:-$PASS}"
  local GROUP="${3:-$GROUP}"
  local SHELL="${4:-$SHELL}"
  hi "  Configuring the $USER user account!\n"

  if ! getent passwd "$USER" 1>/dev/null; then
    useradd --create-home --shell "$SHELL" "$USER"
    echo "$USER:$PASS" | chpasswd
  fi

  if ! getent group "$GROUP" | grep -q "$USER" 1>/dev/null; then
    groupadd "$GROUP" 2>/dev/null
    gpasswd -a "$USER" "$GROUP" 2>/dev/null
  fi

  if ! getent group docker | grep -q "$USER" 1>/dev/null; then
    groupadd docker 2>/dev/null
    gpasswd -a "$USER" docker 2>/dev/null
  fi
}

security_configuration(){
  local USER="${1:-$USER}"
  local SHELL="${2:-$SHELL}"
  hi "  Configuring the system with security in mind!\n"

  if ! grep -q "ClientAliveInterval 15" "$SSH_CONFIG"; then
    printf "\nClientAliveInterval 600\nClientAliveCountMax 3\n" >> "$SSH_CONFIG"
    RESTART_SSH=1
  fi

if ! grep -q "Match User $USER" "$SSH_CONFIG"; then
cat <<EOF >> "$SSH_CONFIG"
Match User "$USER"
    ForceCommand "$SHELL"
    PasswordAuthentication yes
    X11Forwarding no
    AllowTcpForwarding no
    GatewayPorts no
    PermitTunnel no
    MaxAuthTries 3
    MaxSessions 1
    AllowAgentForwarding no
    PermitEmptyPasswords no
EOF
RESTART_SSH=1
fi

  if grep -q '^Subsystem sftp' "$SSH_CONFIG"; then
    sed -i '/Subsystem.*sftp/s/^/#/' "$SSH_CONFIG"
    RESTART_SSH=1
  fi

  if [[ "$RESTART_SSH" -eq 1 ]]; then
    if sshd -t 2>/dev/null; then
      [[ -f /etc/init.d/sshd ]] && service sshd restart 2>/dev/null
      [[ -f /etc/init.d/ssh  ]] && service ssh restart 2>/dev/null
    else
      echo "Syntax error in ${SSH_CONFIG}."
    fi
    echo
  fi

  if [[ "$RESTART_DOCKER" -eq 1 ]]; then
    local RESTART=0
    [[ -f /etc/init.d/docker ]] && service docker stop 2>&1 >/dev/null || stop -q docker 2>/dev/null
    sleep 2
    [[ -f /etc/init.d/docker ]] && RESTART=1 && service docker start || die "Docker did not start correctly!"
    [[ -f /etc/init/docker.conf ]] && [[ "$RESTART" -eq 0 ]] && start -q docker
    echo
    PID="$(pgrep -f "docker -d")"
    [[ "$PID" ]] && cat /proc/"$PID"/limits
    echo
  fi
}

install_sample_configuration(){
  hi "  Installing sample training image for Bro!\n"
  if ! docker images | grep -q brolive; then
    docker pull broplatform/brolive
  fi
}

install_nsm_configurations(){

  install_sample_configuration

  for file in $(git ls-files extra/*.conf | grep -v brolive.conf); do
    F="$(basename $file .conf)"
    if ! docker images | grep -q "$F"; then
      hi "  Installing sample training image for ${F}\n"
      docker pull jonschipp/islet-"${F}"
    fi
  done
}

install_sample_distributions(){
  DISTRO="ubuntu debian fedora centos"
  for image in "$DISTRO"; do
    if ! docker images | grep -q "$image"; then
      hi "  Installing distribution image for ${image}\n"
      docker pull "$image"
    fi
  done
}

"$@"
