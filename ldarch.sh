#!/bin/sh

# DEFAULTS:
[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/dechnik/dotfiles.git"
[ -z "$progsfile" ] && progsfile="https://raw.githubusercontent.com/dechnik/ldarch/master/programs.csv"
[ -z "$aurhelper" ] && aurhelper="yay"

error() { clear; printf "ERROR:\\n%s\\n" "$1"; exit;}

getuserandpass() { \
	# Prompts user for new username an password.
	name=$(dialog --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit
	while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
		name=$(dialog --no-cancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	pass1=$(dialog --no-cancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(dialog --no-cancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
    	done ;}

adduserandpass() { \
	# Adds user `$name` with password $pass1.
	dialog --infobox "Adding user \"$name\"..." 4 50
	useradd -m -g wheel -s /usr/bin/fish "$name" >/dev/null 2>&1 ||
	usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2 ;}

refreshkeys() { \
	dialog --infobox "Refreshing Arch Keyring..." 4 40
	pacman --noconfirm -Sy archlinux-keyring >/dev/null 2>&1
	}

newperms() { # Set special sudoers settings for install (or after).
	sed -i "/#LD/d" /etc/sudoers
	echo "$* #LD" >> /etc/sudoers ;}

manualinstall() { # Installs $1 manually if not installed. Used only for AUR helper here.
	[ -f "/usr/bin/$1" ] || (
    	dialog --infobox "Installing \"$1\", an AUR helper and dependencies (probably GO)" 4 50
	cd /tmp || exit
	rm -rf /tmp/"$1"*
	curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/"$1".tar.gz &&
	sudo -u "$name" tar -xvf "$1".tar.gz >/dev/null 2>&1 &&
	cd "$1" &&
	sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1
	cd /tmp || return) ;}

aurinstall() { \
	dialog --title "Installation" --infobox "Installing \`$1\` ($n of $total) from the AUR. $2" 6 70
	echo "$aurinstalled" | grep "^$1$" >/dev/null 2>&1 && return
	sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
	}

maininstall() { # Installs all needed programs from main repo.
	dialog --title "Installation" --infobox "Installing \`$1\` ($n of $total). $2" 6 70
	pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
	}

goinstall() { \
	dialog --title "Installation" --infobox "Installing \`$1\` ($n of $total) from the GO repository. $2" 6 70
	sudo -u "$name" go get -u $2
	}

gitsucklessinstall() {
	dir=$(mktemp -d)
	dialog --title "Installation" --infobox "Installing \`$(basename "$1")\` ($n of $total) via \`git\` and \`make\`. $2" 6 70
	git clone "$2" "$dir" >/dev/null 2>&1
	cd "$dir" || exit
	git branch -r | grep -v '\->' | while read remote; do git branch --track "${remote#origin/}" "$remote" >/dev/null 2>&1; done
	git fetch --all >/dev/null 2>&1
	git pull --all >/dev/null 2>&1
	git checkout master >/dev/null 2>&1
	for branch in $(git for-each-ref --format='%(refname)' refs/heads/ | cut -d'/' -f3); do
		if [ "$branch" != "master" ];then
			git merge $branch -m $branch >/dev/null 2>&1
		fi
	done
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return ;}

gitmakeinstall() {
	dir=$(mktemp -d)
	dialog --title "Installation" --infobox "Installing \`$(basename "$1")\` ($n of $total) via \`git\` and \`make\`. $2" 6 70
	git clone --depth 1 "$1" "$dir" >/dev/null 2>&1
	cd "$dir" || exit
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
    	cd /tmp || return ;}

gitmanualinstall() {
	case "$1" in
		"powerline-fonts")
			dir=$(mktemp -d)
			dialog --title "Installation" --infobox "Installing \`$(basename "$1")\` ($n of $total) via \`git\` and \`make\`. $2" 6 70
			git clone --depth=1 "$2" "$dir" >/dev/null 2>&1
			cd "$dir" || exit
			./install.sh >/dev/null 2>&1
			;;
    	esac
	}

installationloop() { \
    ([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) || curl -Ls "$progsfile" | sed '/^#/d' > /tmp/progs.csv
	total=$(wc -l < /tmp/progs.csv)
	aurinstalled=$(pacman -Qm | awk '{print $1}')
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep "^\".*\"$" >/dev/null 2>&1 && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"") maininstall "$program" "$comment" ;;
			"A") aurinstall "$program" "$comment" ;;
			"S") gitsucklessinstall "$program" "$comment" ;;
            		"G") gitmakeinstall "$program" "$comment" ;;
			"P") pipinstall "$program" "$comment" ;;
			"O") goinstall "$program" "$comment" ;;
			"M") gitmanualinstall "$program" "$comment" ;;
		esac
	done < /tmp/progs.csv ;}

installdotfiles() {
	dialog --infobox "Downloading and installing config files..." 6 70
	[ ! -d "$2" ] && mkdir -p "$2" && chown -R "$name:wheel" "$2"
	chown -R "$name:wheel" "$2"
	sudo -u "$name" git clone "$1" "$2" >/dev/null 2>&1 &&
    cd "$2" &&
    sudo -u "$name" sh letsstow.sh -t /home/"$name"
    cd /tmp || return ;}

systembeepoff() { dialog --infobox "Getting rid of that retarded error beep sound..." 10 50
	rmmod pcspkr
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;}

finalize(){ \
	dialog --title "All done!" --msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nTo run the new graphical environment, log out and log back in as your new user, then run the command \"startx\" to start the graphical environment (it will start automatically in tty1).\\n\\n" 12 80
	}

pacman -Syu --noconfirm --needed dialog || error "Are you sure you're running this as the root user? Are you sure you're using an Arch-based distro? ;-) Are you sure you have an internet connection? Are you sure your Arch keyring is updated?"

refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

maininstall "fish" "Smart and user friendly shell intended mostly for interactive use"

getuserandpass || error "User exited."

adduserandpass || error "Error adding username and/or password."

dialog --title "Installation" --infobox "Installing \`basedevel\` and \`git\` for installing other software." 5 70
pacman --noconfirm --needed -S base-devel git >/dev/null 2>&1

newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

grep "^Color" /etc/pacman.conf >/dev/null || sed -i "s/^#Color/Color/" /etc/pacman.conf
grep "ILoveCandy" /etc/pacman.conf >/dev/null || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf

sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

manualinstall $aurhelper || error "Failed to install AUR helper."

installationloop

installdotfiles $dotfilesrepo /home/"$name"/dotfiles

systembeepoff

newperms "%wheel ALL=(ALL) ALL #LD
%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay,/usr/bin/pacman -Syyuw --noconfirm"

finalize
clear
