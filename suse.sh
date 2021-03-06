#!/bin/bash

#
# OpenSUSE specific functions 
#
# (c) 2007-2016, Hetzner Online GmbH
#


# setup_network_config "$device" "$HWADDR" "$IPADDR" "$BROADCAST" "$SUBNETMASK" "$GATEWAY" "$NETWORK" "$IP6ADDR" "$IP6PREFLEN" "$IP6GATEWAY"
setup_network_config() {
  if [ "$1" -a "$2" ]; then
    # good we have a device and a MAC

    if [ -e "$FOLD/hdd/etc/os-release" ]; then
      SUSEVERSION="$(grep 'VERSION=' "$FOLD/hdd/etc/os-release" | cut -d '"' -f2 | sed -e 's/\.//')"
    else 
      SUSEVERSION="$(grep VERSION "$FOLD/hdd/etc/SuSE-release" | cut -d ' '  -f3 | sed -e 's/\.//')"
    fi
    debug "# Version: ${SUSEVERSION}"

    ROUTEFILE="$FOLD/hdd/etc/sysconfig/network/routes"
    if [ -f "$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules" ]; then
      UDEVFILE="$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules"
    else
      UDEVFILE="/dev/null"
    fi
    # Delete network udev rules
#    rm $FOLD/hdd/etc/udev/rules.d/*-persistent-net.rules 2>&1 | debugoutput

    {
      echo "### $COMPANY - installimage"
      echo "# device: $1"
      printf 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="%s", KERNEL=="eth*", NAME="%s"\n' "$2" "$1"
    } > "$UDEVFILE"

    # remove any other existing config files
    for i in `find "$FOLD/hdd/etc/sysconfig/network/" -name "*-eth*"`; do rm -rf "$i" >>/dev/null 2>&1; done

    CONFIGFILE="$FOLD/hdd/etc/sysconfig/network/ifcfg-$1"

    echo -e "### $COMPANY - installimage" > $CONFIGFILE 2>>$DEBUGFILE
    echo -e "# device: $1" >> $CONFIGFILE 2>>$DEBUGFILE
    echo -e "BOOTPROTO='static'" >> $CONFIGFILE 2>>$DEBUGFILE
    echo -e "MTU=''" >> $CONFIGFILE 2>>$DEBUGFILE
    echo -e "STARTMODE='auto'" >> $CONFIGFILE 2>>$DEBUGFILE
    echo -e "UNIQUE=''" >> $CONFIGFILE 2>>$DEBUGFILE
    echo -e "USERCONTROL='no'" >> $CONFIGFILE 2>>$DEBUGFILE

    if [ "$1" -a "$2" -a "$3" -a "$4" -a "$5" -a "$6" -a "$7" ]; then
      echo -e "REMOTE_IPADDR=''" >> $CONFIGFILE 2>>$DEBUGFILE
      echo -e "BROADCAST='$4'" >> $CONFIGFILE 2>>$DEBUGFILE
      echo -e "IPADDR='$3'" >> $CONFIGFILE 2>>$DEBUGFILE
      echo -e "NETMASK='$5'" >> $CONFIGFILE 2>>$DEBUGFILE
      echo -e "NETWORK='$7'" >> $CONFIGFILE 2>>$DEBUGFILE

      echo -e "$7 $6 $5 $1" > $ROUTEFILE 2>>$DEBUGFILE
      echo -e "$6 - 255.255.255.255 $1" >> $ROUTEFILE 2>>$DEBUGFILE
      echo -e "default $6 - -" >> $ROUTEFILE 2>>$DEBUGFILE
    fi

    if [ "$8" -a "$9" -a "${10}" ]; then
      debug "setting up ipv6 networking $8/$9 via ${10}"
      if [ "$3" ]; then
	# add v6 addr as an alias, if we have a v4 addr
        echo -e "IPADDR_0='$8/$9'" >> $CONFIGFILE 2>>$DEBUGFILE
      else
        echo -e "IPADDR='$8/$9'" >> $CONFIGFILE 2>>$DEBUGFILE
      fi
      echo -e "default ${10} - $1" >> $ROUTEFILE 2>>$DEBUGFILE
    fi 

    if ! isNegotiated && ! isVServer; then
      echo -e "ETHTOOL_OPTIONS=\"speed 100 duplex full autoneg off\"" >> $CONFIGFILE 2>>$DEBUGFILE
    fi

    return 0
  fi
}

# generate_mdadmconf "NIL"
generate_config_mdadm() {
  if [ -n "$1" ]; then
    local mdadmconf="/etc/mdadm.conf"
    {
      echo "DEVICE partitions"
      echo "MAILADDR root"
    } > "$FOLD/hdd$mdadmconf"
    execute_chroot_command "mdadm --examine --scan >> $mdadmconf"; declare -i EXITCODE=$?
    return $EXITCODE
  fi
}

# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  [ "$1" ] || return 0

  VERSION="$(find "$FOLD/hdd/boot/" -name "vmlinuz-*" | cut -d '-' -f 2- | sort -V | tail -1)"

  # blacklist i915
  local blacklist_conf="$FOLD/hdd/etc/modprobe.d/blacklist-$C_SHORT.conf"
  {
    echo "### $COMPANY - installimage"
    echo '### i915 driver blacklisted due to various bugs'
    echo '### especially in combination with nomodeset'
    echo 'blacklist i915'
  } > "$blacklist_conf"

  if [ "$SUSEVERSION" -eq 132 -o "$SUSEVERSION" -eq 421 ]; then
    # due to a bug within the 99suse dracut module an empty mduuid whitelist may be created
    # >  # mduuid
    # >  mduuid=$(getarg mduuid)
    # > -if [ -n "$mduuid"]; then
    # > +if [ -n "$mduuid" ]; then
    # >      echo "rd.md.uuid=$mduuid" >> /etc/cmdline.d/99-suse.conf
    # >      unset CMDLINE
    # >  fi
    sed -i 's/if \[ -n "$mduuid"\]; then/if [ -n "$mduuid" ]; then/g' "$FOLD/hdd/usr/lib/dracut/modules.d/99suse/parse-suse-initrd.sh"
  fi

  if [ "$SUSEVERSION" -lt 132 ]; then
    local f="$FOLD/hdd/etc/sysconfig/kernel"
    sed -i 's/INITRD_MODULES=.*/INITRD_MODULES=""/' "$f"
    if [ "$SUSEVERSION" -ge 113 ]; then
      sed -i 's/^NO_KMS_IN_INITRD=.*/NO_KMS_IN_INIRD="yes"/' "$f"
    fi
#  elif [ "$SUSEVERSION" -ge 132 ]; then
  else 
    local dracutfile="$FOLD/hdd/etc/dracut.conf.d/99-$C_SHORT.conf"
    {
      echo "### $COMPANY - installimage"
      echo 'add_dracutmodules+="lvm mdraid"'
      echo 'add_drivers+="raid0 raid1 raid10 raid456"'
      #echo 'early_microcode="no"'
      echo 'hostonly="no"'
      echo 'hostonly_cmdline="no"'
      echo 'kernel_cmdline="rd.auto rd.auto=1"'
      echo 'lvmconf="yes"'
      echo 'mdadmconf="yes"'
      echo 'persistent_policy="by-uuid"'
    } > "$dracutfile"
  fi

  # set mkinitrd_cmd
  local mkinitrd_cmd=''
  if [ "$SUSEVERSION" -ge 132 ]; then
    mkinitrd_cmd='dracut --force --regenerate-all'
#  elif [ "$SUSEVERSION" -ge 121 -a "$SUSEVERSION" -lt 132 ]; then
  else
    # run without updating bootloader as this would fail because of missing
    # or at this point still wrong device.map.
    # A device.map is temp. generated by grub2-install in 12.2
    mkinitrd_cmd='mkinitrd -B'
  fi

  execute_chroot_command "$mkinitrd_cmd"; EXITCODE=$?

  return $EXITCODE
}


setup_cpufreq() {
  if [ "$1" ]; then
     # openSuSE defaults to the ondemand governor, so we don't need to set this at all
     # http://doc.opensuse.org/documentation/html/openSUSE/opensuse-tuning/cha.tuning.power.html
     # check release notes of furture releases carefully, if this has changed!
     
#    CPUFREQCONF="$FOLD/hdd/etc/init.d/boot.local"
#    echo -e "### $COMPANY - installimage" > $CPUFREQCONF 2>>$DEBUGFILE
#    echo -e "# cpu frequency scaling" >> $CPUFREQCONF 2>>$DEBUGFILE
#    echo -e "cpufreq-set -g $1 -r >> /dev/null 2>&1" >> $CPUFREQCONF 2>>$DEBUGFILE

    return 0
  fi
}

#
# generate_config_grub <version>
#
# Generate the GRUB bootloader configuration.
#
generate_config_grub() {
  declare -i EXITCODE=0
  local grubdefconf="$FOLD/hdd/etc/default/grub"

  # even though grub2-mkconfig will generate a device.map on the fly, the
  # yast perl bootloader script, will use the fscking device.map, as well as
  # mkinitrd (which also uses the perl bootloader script) if the -B option is
  # not passed
  DMAPFILE="$FOLD/hdd/boot/grub2/device.map"

  rm -f "$DMAPFILE"

  local i=0
  for ((i=1; i<=COUNT_DRIVES; i++)); do
    local j; j="$((i - 1))"
    local disk; disk="$(eval echo "\$DRIVE$i")"
    echo "(hd$j) $disk" >> "$DMAPFILE"
  done
  cat "$DMAPFILE" >> "$DEBUGFILE"

  local grub_linux_default="nomodeset"
  # set net.ifnames=0 to avoid predictable interface names for opensuse 13.2
  if [ "$SUSEVERSION" -ge 132 ] ; then
    grub_linux_default="${grub_linux_default} net.ifnames=0 quiet systemd.show_status=1"
  fi
  # set elevator to noop for vserver
  if isVServer; then
    grub_linux_default="${grub_linux_default} elevater=noop"
  fi
  # H8SGL need workaround for iommu
  if [ "$MBTYPE" = 'H8SGL' ] && [ "$IMG_VERSION" -ge 131 ] ; then
    grub_linux_default="${grub_linux_default} iommu=noaperture"
  fi

  sed -i "$grubdefconf" -e "s/^GRUB_HIDDEN_TIMEOUT=.*/GRUB_HIDDEN_TIMEOUT=5/" -e "s/^GRUB_HIDDEN_TIMEOUT_QUIET=.*/GRUB_HIDDEN_TIMEOUT_QUIET=false/"
  execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"'"${grub_linux_default}"'\"/"'

  sed -i "grubdefconf" -e "s/^GRUB_TERMINAL=.*/GRUB_TERMINAL=console/"

  execute_chroot_command "grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1"

  # the opensuse mkinitrd uses this file to determine where to write the bootloader...
  local grubinstalldev_file; grubinstalldev_file="$FOLD/hdd/etc/default/grub_installdevice"
  rm -f "$grubinstalldev_file"
  for ((i=1; i<=COUNT_DRIVES; i++)); do
    local disk; disk="$(eval echo "\$DRIVE$i")"
    echo "$disk" >> "$grubinstalldev_file"
  done
  echo "generic_mbr" >> "$grubinstalldev_file"

  return $EXITCODE
}

#
# write_grub
#
# Write the GRUB bootloader into the MBR
#
write_grub() {
  # only install grub2 in mbr of all other drives if we use swraid
  for ((i=1; i<=COUNT_DRIVES; i++)); do
    if [ "$SWRAID" -eq 1 ] || [ "$i" -eq 1 ] ;  then
      local disk; disk="$(eval echo "\$DRIVE$i")"
      execute_chroot_command "grub2-install --no-floppy --recheck $disk 2>&1" 
      declare -i EXITCODE=$?
    fi
  done
  uuid_bugfix

  return "$EXITCODE"
}
#
# os specific functions
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
run_os_specific_functions() {
  return 0
}

# vim: ai:ts=2:sw=2:et
