Isolated, Scalable, & Lightweight Environment for Training
=========

Make training a smooth process...#NoMoreVMs <br>

A container system for teaching Linux based software with minimal participation and configuration effort. <br>
The participation barrier is set very low, students only need an SSH client.

![ISLET Screenshot](http://jonschipp.com/islet/islet.png)

#### Uses

* Event training
* Staff training
* Capture the flag competitions
* Trying out tools in a containerized environment
* Development environments

## Installation

Installation of ISLET is very simple and it can be done in two ways:

On the host operation system
```shell
make install
```
Or as a Docker container which requires little to no modification to the host
```shell
make install-contained
```

![ISLET Make Screenshot](http://jonschipp.com/islet/islet_make.png)

Target:         |    Description:
----------------|----------------
install         | Install ISLET: install-files + configuration
install-contained | Install ISLET as a container, no modification to host system
update		| Downloads and install new code (custom changes to default files will be overwritten)
uninstall       | Uninstall ISLET (Recommended to backup your stuff first)
mrproper 	| Removes files that did not come with the source
install-docker  | Installs latest Docker from Docker repo (Debian/Ubuntu only)
docker-config   | Reconfigures Docker storage backend to limit container and image sizes
user-config     | Configures a user account called demo w/ password dem
security-config | Configures sshd and pam_limits with islet relevant security in mind
iptables-config | Installs iptables ruleset

GNU make accepts arguments if you want a customized installation (*not supported*):
```shell
make install INSTALL_DIR=/usr/local/islet USER=training
make user-config INSTALL_DIR=/usr/local/islet USER=training
make security-config INSTALL_DIR=/usr/local/islet USER=training
make uninstall INSTALL_DIR=/usr/local/islet USER=training
```

Variable:       |    Description:
----------------|----------------
CONFIG_DIR      | ISLET config files directory (def: /etc/islet)
INSTALL_DIR     | ISLET installation directory (def: /opt/islet)
CRON		| Directory to place islet crontab file (def: /etc/cron.d)
USER		| User account created with user-config target (def: demo)
SIZE		| Maximum container and image size with configure-docker target (def: 2G)
IPTABLES	| Iptables ruleset (def: /etc/network/if-pre-up.d/iptables-rules)
NAGIOS      | Location of nagios plugins (def: /usr/local/nagios/libexec)
PORT        | The SSH port on the host when installing ISLET as a container (def: 2222)

## Updating

Updating an existing ISLET installation is very simple:

For host installation (`make install`):
```shell
make update
```
For container installation (`make install-contained`):
```shell
docker pull jonschipp/islet
```
### Dependencies

* Linux, Bash, Cron, OpenSSH, Make, SQLite, and Docker

The configure script will check dependencies (it doesn't create a makefile):
```shell
./configure
```

![ISLET Configure Screenshot](http://jonschipp.com/islet/islet_configure.png)

Typically all you need is make, sqlite, and docker (for Debian/Ubuntu):
```shell
apt-get install make sqlite
make install-docker
```

The included installation scripts are designed to work with Debian/Ubuntu systems.

**Note:** Installing ISLET as container `make install-contained` only requires Docker

#### Ubuntu

The following make targets will install docker and configure the system with security in mind for the Docker process.
It is designed to be a quick way to get a working system with a good configuration.

Install ISLET on the host:
```shell
make install-docker	# Installs latest Docker
make configure-docker   # Limits image and container sizes by rebuilding storage backend
make user-config	# Configures demo user account
make security-config    # Configure islet relevant security with sshd and pam_limits
```

Install ISLET as a container on the host:
```shell
make install-docker	# Installs latest Docker
make install-contained	# Installs ISLET as a container
make configure-docker   # Limits image and container sizes by rebuilding storage backend
make security-config    # Configure islet relevant security with sshd and pam_limits
```

#### Manual

Manually install and configure all dependencies to your liking.

* Install Docker:
```shell
apt-get install docker
yum install docker
```

* Configure user account for training (this is given to students to login):
```shell
useradd --create-home --shell /opt/islet/bin/islet_shell training
echo "training:training" | chpasswd
groupadd docker
gpasswd -a training docker
```

### Security Recommendations

* SSH: _/etc/ssh/sshd_config_

The following command will configure sshd_config to match the example after with the exception of modifying LoginGraceTime.

```shell
make security-config
```

```shell
LoginGraceTime 30s
ClientAliveInterval 15
ClientAliveCountMax 10

#Subsystem       sftp    /usr/libexec/openssh/sftp-server

Match User training
	ForceCommand /opt/islet/bin/islet_shell
	X11Forwarding no
	AllowTcpForwarding no
	PermitTunnel no
	PermitOpen none
	MaxAuthTries 3
	MaxSessions 1
	AllowAgentForwarding no
	PermitEmptyPasswords no
```

* ulimit contraints

The following command will configure decent ulimit settings for docker processes.
These have the effect of restricting the user's environment inside the container.

```shell
make security-config
```

Adjust as necessary: _/etc/init/docker.conf_
```
# BEGIN ISLET Additions
limit nofile 1000 2000		 # Limit number of open files
limit nproc  1000 2000		 # Prevent fork bombs
limit fsize  100000000 200000000 # Limit file sizes to max of 200MB
limit cpu    500  500
# END
```

* Separate storage for containers:

```
service docker stop
rm -rf /var/lib/docker/*
mkfs.ext2 /dev/sdb1
mount -o defaults,noatime,nodiratime /dev/sdb1 /var/lib/docker
tail -1 /etc/fstab
	/dev/sdb1	/var/lib/docker	    ext2     defaults,noatime,nodiratime,nobootwait 0 1
service docker start
```

* Limit container storage size to prevent DoS or resource abuse

Switching storage backends to devicemapper allows for disk quotas.
Set dm.basesize to the maximum size the container can grow to (def: 10G)

**Note:** All container and image data will be lost.

Automatic:

```
make docker-config SIZE=3G
```

Manual:

```
service docker stop
rm -rf /var/lib/docker/*
docker -d --storage-driver=devicemapper --storage-opt dm.basesize=3G &
sleep 3 && pkill docker
tail -1 /etc/default/docker
	DOCKER_OPTS="--storage-driver=devicemapper --storage-opt dm.basesize=3G"
start docker
```

**Note:** There's currently a bug in devicemapper that may cause docker to fail run containers [more info](https://github.com/docker/docker/issues/4036).

* Iptables

Rate limiting protection for the SSH service
```
make iptables-config
```

* GRSecurity kernel patches

To aid in protecting the host system it's recommended to patch the Linux kernel [more info](https://grsecurity.net/)

# Administration

* Global configuration file: */etc/islet/islet.conf*
* Per-image configuration file: */etc/islet/$IMAGE.conf*

Per-image configs overwrite the variables specified in the global config file.
For each Docker image you want available for use by ISLET, create an image file with a .conf extension and place it in the /etc/islet/ directory.
These images will be selectable from the ISLET menu after authentication via SSH.

Common Tasks:

* Change the password of the demo user to help prevent unauthorized access

```
        $ passwd demo
```

* Change the password of a container user (Not a system account).

```
    $ PASS=$(echo "newpassword" | sha1sum | sed 's/ .*//)
	$ sqlite3 /var/tmp/islet.db "UPDATE accounts SET password='$PASS' WHERE user='jon';"
	$ sqlite3 /var/tmp/islet.db "SELECT password FROM accounts WHERE user='jon';"
	aaaaaaa2a4817e5c9a56db45d41ed876e823fcf|1413533585

```

* Configure container and user lifetime (e.g. conference duration)

  1. Specify the number of days for user account and container lifetime in:

```
        $ grep ^DAYS /etc/islet/islet.conf
        DAYS=3 # Length of the event in days
```

  Removal scripts are cron jobs that are scheduled in /etc/cron.d/islet

* Allocate more or less resources for containers, and control other container settings.
  These changes will take effect for each newly created container.
  - System and use case dependent

```
    $ grep -A 5 "Container config /etc/islet/brolive.conf
	# Container Configuration
	VIRTUSER="demo"                                         # Account used when container is entered (Must exist in container!)
	CPU="1"                                                 # Number of CPU's allocated to each container
	RAM="256m"                                              # Amount of memory allocated to each container
	HOSTNAME="bro"	                                      	# Set hostname in container. PS1 will end up as $VIRTUSER@$HOSTNAME:~$ in shell
	NETWORK="none"                                          # Disable networking by default: none; Enable networking: bridge
	DNS="127.0.0.1"                                         # Use loopback when networking is disabled to prevent error messages from resolver
	MOUNT="-v /exercises:/exercises:ro"			# Mount point(s), sep. by -v: /src:/dst:attributes, ro = readonly (avoid rw)
	OPTIONS="--cap-add=NET_RAW --cap-add=NET_ADMIN"		# Apply any other options you want passed to Docker run here
	MOTD="Training materials are in /exercises"             # Message of the day is displayed before container launch and reattachment
```

* Adding, removing, or modifying exercises

  1. Make changes in /exercises on the host's filesystem

  *  Changes are immediately available for new and existing containers

# Branding

* Per-image banners

  1. Add BANNER variable to the image file config in /etc/islet/. Color codes from libislet work here.

```
	...

	BANNER="
	${MF}===============================================================${N}

	${BF}ISLET${N}${RF}:${N} ${Y}A Linux-based Software Training System${N}

   	${BF}Web${N}${RF}:${N} ${U}${Y}https://github.com/jonschipp/islet${N}

	${MF}===============================================================${N}
	"

```

* Custom login message for each user

  1. Edit the MOTD variable in the image file config in /etc/islet/ with the text of your liking.
     printf escape sequences work here.

```
        $ grep -A 2 MOTD /etc/islet/brolive.conf
        MOTD="
        Training materials are located in /exercises
        \te.g. $ bro -r /exercises/BroCon14/beginner/http.pcap\n"

```

# Adding Training Environments

See Docker's [image documentation](http://docs.docker.com/userguide/dockerimages)

 1. Build or pull in a new Docker image

 2. Create a ISLET config file for that image. It's best to copy and modify an existing one.

 3. Place it in /etc/islet with a .conf extension

 It should now be available from the selection menu upon login.

![ISLET Configs Screenshot](http://jonschipp.com/islet/islet_configs.png)

# Demo

The precursor to ISLET was used to aid the instructers in teaching the Bro platform at BroCon14.

Steps:
* Install ISLET and dependencies
* Build Docker image containing Bro (docker pull broplatform/brolive)
* Write a ISLET config file for the Bro image
* Set a banner in the ISLET config file for light branding (logo)
* Hand out the demo account credentials to your students so they can SSH in
* Instruct them on the software

Here's a brief demonstration:

```
        $ ssh demo@live.bro.org

        Welcome to Bro Live!
        ====================

            -----------
          /             \
         |  (   (0)   )  |
         |            // |
          \     <====// /
            -----------

        A place to try out Bro.

        Are you a new or existing user? [new/existing]: new

        A temporary account will be created so that you can resume your session. Account is valid for the length of the event.

        Choose a username [a-zA-Z0-9]: jon
        Your username is jon
        Choose a password:
        Verify your password:
        Your account will expire on Fri 29 Aug 2014 07:40:11 PM UTC

        Enjoy yourself!
        Training materials are located in /exercises.
        e.g. $ bro -r /exercises/beginner/http.pcap

        demo@bro:~$ pwd
        /home/demo
        demo@bro:~$ which bro
        /usr/local/bro/bin/bro
```


