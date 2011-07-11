#!/bin/sh

#	ESX Support Script
#
#	Collects various configuration and log files
#	for use when troubleshooting ESX
#
#


#
# Variables
#
VER=1.30.x
DATE=$(date +"%F--%H.%M")
# Sometimes hostname -s fails (see PR #277063)
HOSTNAME=$(hostname -s 2>/dev/null)
if [ $? != 0 ]; then
   # But hostname works
   HOSTNAME=$(hostname 2>/dev/null)
   if [ $? != 0 ]; then
      # Just to be on the safe side.
      HOSTNAME="unknown-host"
   fi
fi
COS=$(if [ $(uname) = "Linux" ]; then echo 1; else echo 0; fi)
NEWLINE='
'

#
# File names
#
TARFILE=esx-$DATE.$$.tgz
OUTPUT_DIR=vm-support-$HOSTNAME-$DATE.$$
ESXTOPSHOTFILE=esxtop-$HOSTNAME-$DATE.$$.csv
# vm-support log filename.
VMSUPPORT_LOG_FILE=$OUTPUT_DIR/tmp/vm-support.$$.log
TMP_DIR_FILE=${OUTPUT_DIR}/tmp/working_dir.txt
COREDUMP_DIR="/root"
DEFAULT_TMP_DIR="/tmp"
# Which files are necessary for esxtop (+ additional ones we care about).
SNAP_SHOT_FILES="cpuinfo net/*/*.info scsi/*/*"
SCHEDTRACE_MOD=/usr/lib/vmware/vmkmod/schedtrace
CHANNELLOGGER=/usr/sbin/logchannellogger
SCHED_STATS=/usr/bin/sched-stats
VSCSISTATS_BIN=/usr/lib/vmware/bin/vscsiStats
VMCP=/usr/lib/vmware/bin/vmcp
if [ "$COS" = "1" ]; then
   VIMDUMP="/usr/bin/vmware-vimdump"
   VMX_BIN="vmware-vmx"
else
   VIMDUMP="/bin/vmware-vimdump"
   VMX_BIN="vmx"
fi

#
# Tuning vm-support
#
BACKGROUND_CMD_WAIT=300


#
# usage
#
#	Function: usage prints how to use this script
#
usage() {
   if [ "$COS" = "1" ]; then
      usageStr="[-a] [-n] [-N] [-c] [-s] [-S] [-p] [-P] [-C esxtoprc_file] [-d duration_in_seconds] [-i interval] [-x] [-X wid] [-q] [-w] [-f] [-l] [-Z wid] [-r] [-t wgid] [-v] [-h]"
   else
      usageStr="[-a] [-n] [-s] [-S] [-p] [-P] [-C esxtoprc_file] [-d duration_in_seconds] [-i interval] [-x] [-X wid] [-q] [-w] [-l] [-Z wid] [-r] [-v] [-h]"
   fi

   echo "Usage: $0 $usageStr"
   echo "  -a causes all cores to be tar'ed up - even those from previous"
   echo "     runnings of this script"
   echo "  -n causes no cores to be tar'ed up"
   if [ "$COS" = "1" ]; then
      echo "  -N causes no service console cores to be tar'ed up"
      echo "  -c gather schedtrace snapshots (only if performance snapshots are enabled)"
   fi
   echo "  -p take esxtop batch performance data in addition to other data"
   echo "  -P take only esxtop performance data"
   echo "  -s take performance snapshots in addition to other data"
   echo "  -S take only performance snapshots"
   echo "  -d <s|p> set performance snapshot duration to <s> seconds [default $snap_duration]"
   echo "  -i <s|p> sleep <s> seconds between snapshots [default autodetect]"
   echo "  -x lists wids for running VMs"
   echo "  -X <wid> grab debug info for a hung VM"
   echo "  -q runs in quiet mode"
   echo "  -w <dir> sets the working directory used for the output files"
   if [ "$COS" = "1" ]; then
      echo "  -f allows you to force vm-support to use a VMFS working directory"
   fi
   echo "  -l print list of files being collected"
   echo "  -Z <wid> suspends a VM and grabs debug info"
   echo "  -r causes all vmfs3 volumes' volume headers to be tar'ed up"
   if [ "$COS" = "1" ]; then
      # -t is not supported because vscsiStats are not available for visor (PR 275119)
      echo "  -t <wgid> takes a scsi command trace for I/O from a VM (specify world group id)"
      echo "      Note:- this option consumes a noticeable amount of cpu so enabling it "
      echo "             can negatively impact the performance of the system"
      echo "           - limited to one VM at a time"
      echo "           - trace contains NO customer sensitive data"
      echo "           - only information recorded is: "
      echo "              - serialnumber, timestamp, length of command"
      echo "              - command type, block number"
      echo "           - Therefore, actual data/payload of commands is not stored"
   fi
   # VMware internal use only, so don't pollute help:
   # echo "  -T collect test-esx logs in addition to other data"
   echo "  -v prints out vm-support version"
   echo "  -h prints this usage statement"
   echo ""
   if [ "$COS" = "1" ]; then
      echo "See man page for more information on vm-support version $VER"
   fi
}

#
# version
#
version() {
	echo -e "vm-support v$VER\n"
        exit
}


#
# commandlog
#
# The command log is for logging the vm-support messages and commands it runs.
# Used by both 'banner' and 'log' (generally just use one of those in the 
# rest of the script.)
#
# The commandlog is ignored until after the basic argument parsing is completed.
#
commandlog() {
    if [ -f $VMSUPPORT_LOG_FILE ]; then
	echo "${@}" >> $VMSUPPORT_LOG_FILE 2>/dev/null
    fi
}

#
# commandloge
#
commandloge() {
    if [ -f $VMSUPPORT_LOG_FILE ]; then
	echo -e "${@}" >> $VMSUPPORT_LOG_FILE 2>/dev/null
    fi
}

#
# echolog 
#
#	Function: prints and logs a string
#
echolog() {
   echo "${@}"
   commandlog "${@}"
}

#
# banner
#
#	Function: banner prints any number of strings padded with 
#	newlines before and after.
#
banner() {
	echo
	for option in "$@"
	do
		echo $option
		commandlog "$option"
	done
	echo
}

#
# log
#
# Log the input to a stream if VERBOSE output is enabled.
#
log() {
   if [ "$VERBOSE" = "1" ]; then
      echo $1
   fi
   commandlog "$1"
}

#
# loge
#
# Log the input to a stream if VERBOSE output is enabled. use
# echo -e instead of the standard echo.
#
loge() {
   if [ "$VERBOSE" = "1" ]; then
      echo -e $1
   fi
   commandloge "$1"
}

#
# vmklog
#
# Write log message to vmkernel log
#
vmklog() {
   if [ -w /proc/vmware/log ]; then
	echo -n "vm-support: ${@}" >> /proc/vmware/log
   fi
}

#
# getConfigVal
#
# Match expressions of the following form: key = "value"
# Usage: getConfigVal(<option>, <default value>, <config file>)
#
getConfigVal() {
   ret=`sed -ne "s/^[ \t]*$1[ \t]*=[ \t]*\"\(.*\)\".*/\1/p" $3 | tail -1`
   if [ "${ret}" = "" ]; then
      echo $2
   else
      echo $ret
   fi
}

#
# UpdateSpinner
#
UpdateSpinner() {
    # Only show the pretty spinner on a tty
    if [ -t 1 ]; then
        case $SPINNER in
		"|")
                        SPINNER="/"
                ;;

                "/")
                        SPINNER="-"
                ;;

                "-")
                        SPINNER="\\"
                ;;

                "\\")
                        SPINNER="|"
                ;;

                *)
                        SPINNER="|"
                ;;
        esac
        echo -en "\r$1: $SPINNER"
    fi
}

#
# snarfVMFiles
#
# Add all interesting files associated with a 
# VM into the tar. 
#
snarfVMFiles() {
   local VMDIRNAME=$1
   addtar "$VMDIRNAME/*.cfg" IGNORE_ERROR
   addtar "$VMDIRNAME/*.vmx" IGNORE_ERROR
   addtar "$VMDIRNAME/*.vmxf" IGNORE_ERROR
   addtar "$VMDIRNAME/*.log" IGNORE_ERROR
   addtar "$VMDIRNAME/*.vmsd" IGNORE_ERROR
   addtar "$VMDIRNAME/*.vmft" IGNORE_ERROR
   addtar "$VMDIRNAME/debug.vmss" IGNORE_ERROR
   addtar "$VMDIRNAME/debug.vmem" IGNORE_ERROR
      
   # Only add descriptor files, not the whole disk
   addtar "$VMDIRNAME/*.vmdk" 1024 IGNORE_ERROR
   addtar "$VMDIRNAME/*.dsk" 1024 IGNORE_ERROR

   # Add screenshots (useful for hung vm debugging)
   addtar "$VMDIRNAME/*.png" IGNORE_ERROR

   #
   # If one of the above commands succeeded, then
   # add a list of all the VM's files.  
   #
   if [ -e "$OUTPUT_DIR/$VMDIRNAME" ]; then
      # You might think runcmd would work, but you're wrong.
      # (think spaces, and the fact that it would end up creating
      #  and then deleting files in every VM's directory)
      ls -l "$VMDIRNAME" > "$OUTPUT_DIR/$VMDIRNAME/filelist.$$.txt"
   fi

   if [ $no_cores -eq 0 ]; then
      addtar "$VMDIRNAME/vmware-core*"
      addtar "$VMDIRNAME/vmware64-core*"
      addtar "$VMDIRNAME/core*"                
      addtar "$VMDIRNAME/${VMX_BIN}-zdump*"
   fi

   # stats, kstats, callstack profiling
   addtar "$VMDIRNAME/stats" IGNORE_ERROR
 
   # We assume the directory has been created by now
   if [ $suspend_hung_vm -eq 1 ]; then
      for FILE in $(ls -d "$VMDIRNAME"/*.vmss 2>/dev/null); do
         gzip -c "$FILE" > "$OUTPUT_DIR"/"$FILE".gz 2>/dev/null
      done
   fi
}

#
# snarfVirtualCenterFiles
#
# Add all log & core files for VMs managed by VPX into into the tar file.
# (note that we'll copy registered VM's twice.  This seems like a less
# evil than trying to parse the vm-list.)
#
snarfVirtualCenterFiles() {
   local vpxVMDir=$1
   if [ -d ${vpxVMDir} ];  then
      IFS=$NEWLINE
      for VMDIRNAME in `find $vpxVMDir -type d`; do
            unset IFS
            snarfVMFiles "$VMDIRNAME"
      done
      unset IFS
   fi
}

#
# addtar
#
#	Function: addtar takes a single paramater, possibly containing wildcards,
#       and recursively copies the resulting files and directories into self 
#       contained output directory for later tar'ing
#
#	Working on copies could slow this down with VERY large files but:
#	1) We don't expect VERY large files
#	2) Since /proc files can be copied this preserves the tree without
#	   having to cat them all into a file.
#	3) tar barfs on open files like logs if it changes while it's tar'ing.
#          Copying file first makes sure tar doesn't complain
#
#  To use vmcp for the file copies, create an environment variable 
#  named 'usevmcp' prior to running this script.
addtar() {
   local OPTFLAGS=""
   local rc=0

   FILES=$1
   if [ "$2" = "IGNORE_ERROR" ]; then
      OPTFLAGS="-D"
      ignoreError=$2
      SIZELIMIT=""
   else 
      SIZELIMIT=$2
      ignoreError=$3
   fi

	log "addtar \"$FILES\""
	IFS=$NEWLINE
   for FILE in $(ls -d $FILES 2>/dev/null); do
      unset IFS
      if [ -n "$SIZELIMIT" ] ; then
         local fSize=`stat -c %s "$FILE"`
         # If $fSize is too large (>2147483647) $fSize -gt $SIZELIMIT
         # causes a "out of range exception". Thus compare the number
         # of digits first and avoid the second check. see PR 162904
         if [ `expr length "$fSize"` -gt `expr length "$SIZELIMIT"` ] ||
            [ $fSize -gt $SIZELIMIT ]; then   
            log "  File '$FILE' is too big ($fSize > $SIZELIMIT), skipping"
            continue
         fi
      fi 
      local fType=`stat -c %F "$FILE"`
      # If $fType is "symbolic link" then set IGNORE_ERROR automatically
      # so that we ignore any errors in copying symlinks. (PR 304343)
      if [ "$fType" == "symbolic link" ]; then
         ignoreError="IGNORE_ERROR"
      fi
      log "  Copying \"$FILE\" to output directory."

      if [ -n "$usevmcp" ]; then    # USING VMCP
         if [ "$COS" = "1" ]; then
            grepExpr='^/proc'
         else
              grepExpr='^/proc\|^/etc'
         fi
         echo $FILE | grep "$grepExpr" > /dev/null
         if [ $? -eq 0 ]; then
            OPTFLAGS="$OPTFLAGS -e"
         fi

         if [ $no_cores -eq 0 ] && [ $all_cores -eq 0 ]; then
            if [ "$FILE" = "$COREDUMP_DIR" ] || [ "$FILE" = "$COREDUMP_DIR/" ]; then
               for f in $(ls $COREDUMP_DIR/ 2>/dev/null); do
                  if [ $f != "old_cores" ]; then
                     $VMCP -i "$COREDUMP_DIR/$f" -o "$OUTPUT_DIR/$f" 
                  fi
               done
            else
               $VMCP $OPTFLAGS -i "$FILE" -o "$OUTPUT_DIR/$FILE"
            fi
         else
            $VMCP $OPTFLAGS -i "$FILE" -o "$OUTPUT_DIR/$FILE" 
         fi
         rc=$?
         if [ $rc != 0 ]; then
            if [ $rc != 3 ]; then
               echo "Fatal error copying $FILE"
               log "Fatal error copying $FILE"
               exit
            else
               echo "Non-fatal error copying $FILE"
               log "Non-fatal error copying $FILE"
            fi
         fi

         if [ $quiet_mode -eq 0 ]; then
            UpdateSpinner "Preparing files"
         fi
      else
         # USING CP
         if [ $no_cores -eq 0 ] && [ $all_cores -eq 0 ]; then
            # chkeck if $FILE is $COREDUMP_DIR to copy only cores except old_cores
            if [ "$FILE" = "$COREDUMP_DIR" ] || [ "$FILE" = "$COREDUMP_DIR/" ]; then
               for f in $(ls $COREDUMP_DIR/ 2>/dev/null); do
                  if [ $f != "old_cores" ]; then
                     cp -prL --parents "$COREDUMP_DIR/$f" "$OUTPUT_DIR" 2>/dev/null
                  fi
               done
            else
               cp -prL --parents "$FILE" "$OUTPUT_DIR" 2>/dev/null
            fi
         else
            cp -prL --parents "$FILE" "$OUTPUT_DIR" 2>/dev/null
         fi

         # If a file from /proc does not copy, ignore - they're 
         # funny.  Otherwise, exit for failed copy.
         # 
         # Also allow callers to specify IGNORE_ERROR, if a file
         # might not be available (perhaps a locked vmfs file)
         rc=$?
         if [ $rc -ne 0 ] && [ "$ignoreError" != "IGNORE_ERROR" ]; then
            if [ "$COS" = "1" ]; then
               grepExpr='^/proc'
            else
               # XXX /etc (visorfs) contains special files (.#)
               # these files cannot be opened for write because of their
               # special meaning. 
               # Therefore if vm-support output directory is 
               # backed by visorfs the error could be because of the special
               # files.
               grepExpr='^/proc\|^/etc'
            fi
            echo $FILE | grep "$grepExpr" > /dev/null
            if [ $? != 0 ]; then
               banner "Could not copy $FILE to tar area (`pwd`/$OUTPUT_DIR) (err $rc)." \
                      "Have you run out of disk space?" 
               if [ -d $OUTPUT_DIR ]; then
                  rm -rf $OUTPUT_DIR
               fi
               exit 1
            fi
         fi
      fi
      # Filter out ':'s for Windows -- this is here for vmhba names from
      # procfs which confuse winzip
      TARGET=$(basename "${FILE}" | /bin/awk '{ gsub(/:/, "_"); print $0; }')
      if [[ "$(basename "${FILE}")" != "${TARGET}" ]] ; then
         mv "${OUTPUT_DIR}/${FILE}" "${OUTPUT_DIR}/$(dirname "${FILE}")/${TARGET}" 2> /dev/null
      fi

      if [ $quiet_mode -eq 0 ]; then
         UpdateSpinner "Preparing files"
      fi
   done
   unset IFS
}

#
# diagnoseError
# 
# Run tests to help isolate the cause of the 'runcmd' failure
#
diagnoseError() {

   local cmd="$1"
   local log="$2"

   echolog ""
   # make sure we have permission to write to output dir
   if [ -f $log ]; then
      echolog "Log file exists, so permissions should be okay."
   else
      echolog "Log file doesn't exist. Checking that we can create log file:"
      echolog ">touch $log"
      output=$(touch $log 2>&1)
      rc=$?
      echolog "$output"
      if [ $rc -ne 0 ]; then
         echolog "Could not touch output file \"$log\"."  
         echolog "1) Check permissions on the output directory."
         echolog "2) Lack of space may be the problem (see following output)."
      else
         echolog "Touch succeeded. Permissions look fine."
      fi
      rm -rf $log
      
   fi
   echolog "" 

   # strip everything except the first word (hopefully the binary)
   binary=${cmd%% *} 

   # check to make sure that command exists
   echolog "Checking that \"$binary\" exists:" 
   echolog ">which $binary"
   output=$(which $binary 2>&1)
   rc=$?
   echolog "$output"
   if [ $rc -ne 0 ]; then 
      echolog "Command was not found."
      return
   else
      echolog "Command was found."
   fi
   echolog "" 

   if [ "$3" != "NORETRY" ]; then
      local newlog=${log}.again
      # execute same command again (check for transient error)
      echolog "Trying to run command again:"
      echolog ">sh -c \"$cmd > $newlog\""
      output=$(sh -c "$cmd > $newlog" 2>&1)
      rc=$?
      echolog "$output"

      # addtar the new log, then delete it
      if [ -e "$newlog" ]; then
         addtar "$newlog" IGNORE_ERROR
         if ! rm "$newlog"; then
            echolog "Could not delete $log." "Continuing..."
         fi
      fi

      if [ $rc -ne 0 ]; then
         echolog "Received an error again (err $rc)."
      else
         echolog "Command succeeded.  Probably a transient error."
         addtar "$newlog" IGNORE_ERROR
         return
      fi 
      echolog "" 

      # execute same command again without logging (full disk)
      echolog "Checking to see if disk is full. Trying to run command without logging:"
      echolog ">sh -c \"$cmd\""
      output=$(sh -c "$cmd" 2>&1) 
      rc=$?
      echolog "$output"
      if [ $rc -ne 0 ]; then
         echolog "Received error again (err $rc)" 
      else
         echolog "Command succeeded.  Disk is likely full."
      fi 
      echolog ""
   fi

   # print df information
   echolog "Space information for all partitions:" 
   echolog ">df -h" 
   output=$(df -h 2>&1) 
   echolog "$output"
}


#
# runcmd
#
#	Function: runcmd executes the command ($1) 
#	redirected to a file ($2) and then adds that 
#	file to the list of files to tar. 
#	It then deletes the temp file since addtar makes a copy in its own
#	self contained area.
#
runcmd() {
	local cmd="$1"
	local log="$2"

	log "Running command: \"$cmd\""

	# if $cmd segfaults (see PR 105045 for an example), bash will print
	# a lovely "/usr/bin/vm-support: line 1338: 19032 Segmentation
	# fault" which is scary and inappropriate (if it said 'dmidecode'
	# we might let it pass).  So, to hide such errors we run the
	# command in a subshell append any shell output to the logfile.
	rm -f "$log"
	sh -c "$cmd >\"$log\" 2>&1" >>"$log" 2>&1
	rc=$?

   if [ $rc -ne 0 ]; then
      if [ "$3" != "IGNORE_ERROR" ]; then
         echolog "" "Error running $cmd or writing to $log (err $rc)." ""
         diagnoseError "$cmd" "$log" "$3"
         echolog "Continuing..."
      fi
   fi

	if [ -e "$log" ]; then
		addtar "$log" IGNORE_ERROR
		if ! rm "$log"; then
			echolog "" "Could not delete $log (err $rc)." "Continuing..." 
		fi
	fi
}


#
# runbackgroundcmd
#
#	Function: runbackgroundcmd executes the command ($1) 
#	redirected to a file ($2) in the tar directory.
#	
#	The command will be run in the background. vm-support will wait
#	up to BACKGROUND_CMD_WAIT seconds at the end of its runtime for 
#	these commands to complete before giving up.
#
#	The command will be added to a list of commands so that a message
#	can be printed out at the end of vm-support indicating that we're 
#	pausing in the hopes that the following commands complete.
#
#	We also keep track of a list of PIDs so that vm-support doesn't 
#	wait longer than necessary for commands to complete.
#
#	Note that you should be careful to make sure your output file
#	location will be a valid path within OUTPUT_DIR.
#
runbackgroundcmd() {
	log "Running backgrounded command: $1"

	$1 > "$OUTPUT_DIR/$2" 2>&1 &
	pid=$!

	log "Backgrounded pid $pid for command: $1"

	BACKGROUND_CMD_LIST="${BACKGROUND_CMD_LIST}\n\n${1}";
	BACKGROUND_CMD_PIDS="${BACKGROUND_CMD_PIDS} $pid";
}


#
# snarf_running_state
#
# Grab info about the running machine (current processes, open files, etc).
# This is as opposed to the persistent configuration state (like mount 
# points or RPMs installed, log files, etc).
#
snarf_running_state() {
   runcmd "date" "$tmp_dir/date.$$.txt"

   local filter="\|/proc/kcore\|/proc/kmsg"

   # Do not expand the globs when creating the command.  We save the
   # current globignore just incase it is used in the future
   OLD_GLOBIGNORE=$GLOBIGNORE
   export GLOBIGNORE=*

   if [ -f /etc/vmware/vm-support.conf ] ; then
      filter="${filter}$(/bin/awk '/ignored-proc-nodes/                                 \
                                  {                                                     \
                                      split($0, values, "=");                           \
                                      sub(/^[ ]*/, "", values[2]);                      \
                                                                                        \
                                      filters = gensub(/^\([ ]*"(.*)"[ ]*\)$/, "\\1",   \
                                                       "", values[2]);                  \
                                                                                        \
                                      split(filters, f, "\" \"");                       \
                                      for (i in f)                                      \
                                      {                                                 \
                                         filter = filter "\\|" f[i]                     \
                                      }                                                 \
                                                                                        \
                                      print filter;                                     \
                                   }' /etc/vmware/vm-support.conf)";
   fi

   # stdout redirected to /dev/null.  Some files come and go and confuse find.
   # Just send whatever works and don't scare user.
   for file in $(find /proc -type f 2> /dev/null | /bin/grep -v /proc/$$${filter}) ; do
      addtar "${file}"
   done

   export GLOBIGNORE=$OLD_GLOBIGNORE

   # Traverse the entire VSI tree, saving it to a file.
   runcmd "/usr/lib/vmware/bin/vsi_traverse -s" "$tmp_dir/vsicache.$$"
   sleep 5
   runcmd "/usr/lib/vmware/bin/vsi_traverse -s" "$tmp_dir/vsicache-5-seconds-later.$$"

   if [ "$COS" = "1" ]; then
	   runcmd "uptime" "$tmp_dir/uptime.$$.txt"

	   runcmd "dmesg -s 262144" "$tmp_dir/dmesg.$$.txt"

	   if [ -x /usr/sbin/lsof ]; then
	   	runcmd "lsof -l -n -P -b" "$tmp_dir/lsof-normal-output.$$.txt"
	   	runcmd "lsof -i -n -P -b" "$tmp_dir/lsof-network-output.$$.txt"
	   fi

	   runcmd "netstat -a -n -p" "$tmp_dir/netstat-conn.$$.txt"
	   runcmd "netstat -s" "$tmp_dir/netstat-stats.$$.txt"
	   runcmd "netstat -i -a" "$tmp_dir/netstat-intf.$$.txt" 
	   runcmd "ps -auxwww" "$tmp_dir/ps.$$.txt"
	   runcmd "pstree -ap" "$tmp_dir/pstree.$$.txt"
	   runcmd "top -d 1 -n 10 -b" "$tmp_dir/top.$$.txt"
   fi
}


#
# snarf_hostd_state
#
# Get support information about hostd
#
snarf_hostd_state() {
   #	Parse /etc/vmware/hostd/vmInventory.xml and add the virtual 
   #	machine configuration and log files to the 
   #	list of files

   INVENTORY_LOCATION="/etc/vmware/hostd/vmInventory.xml"
   NEW_LOCATION=`sed -n -e "s/^\s*<vmInventory>\s*\(\.*\)/\1/g" -e "s/<\/vmInventory>\s*$//pg" /etc/vmware/hostd/config.xml`
   if [ -n "$NEW_LOCATION" ]; then
      INVENTORY_LOCATION=$NEW_LOCATION
   fi

   # Grab the inventory file itself, in case it is configured differently
   addtar $INVENTORY_LOCATION
   IFS=$NEWLINE
   for CFGNAME in $(sed -n -e "s/^\s*<vmxCfgPath>\s*\(\.*\)/\1/g" \
       -e "s/<\/vmxCfgPath>//pg" $INVENTORY_LOCATION); do
           unset IFS
	   VMDIRNAME=$(dirname "$CFGNAME")
           snarfVMFiles "$VMDIRNAME"
   done
   unset IFS

   #    grab logs and cores for vms which aren't here anymore
   #    (they won't be in the vm-list after vmotion'ing)
   #    The old default directory was /vpx/vms.  The new default
   #    directory is /home/vmware.  Try to grab both,
   #    since we don't know what version of virtual center is being used.

   vpxVMDir=`getConfigVal "serverd.vpx.defaultVmDir" "/vpx/vms/" "/etc/vmware/config"`
   snarfVirtualCenterFiles "$vpxVMDir"
   if [ "$vpxVMDir" != "/home/vmware" ]; then
      snarfVirtualCenterFiles "/home/vmware"
   fi

   #    Grab a dump of all hostd properties export through the VIM API.
   runbackgroundcmd $VIMDUMP "$tmp_dir/vmware-vimdump.$$.txt"
}


#
# snarf_system_state
#
#	Function: snarf_system_state grabs all the interesting system state
#       and adds it to the the tar file.
#
snarf_system_state() {
 
   local rc=0

   snarf_running_state

   snarf_hostd_state
   
   if [ "$COS" = "0" ] && [ $no_cores -eq 0 ]; then
        COREDUMP_DIR="/var/core"
        # For vmvisor extract the vmk core in vm-support. 
        # In classic esx this is done during init however in embedded we may
        # not have storage at init time. Also because of space
        # constraints we gather only the last core.
        if [ -d "$COREDUMP_DIR/" ]; then
            devname=`/usr/sbin/esxcfg-dumppart --get-config | cut -f1`
            if [ $devname != "none" ]; then

               curTime=`date "+%m%d%y.%H.%M"`
               zDumpName=$COREDUMP_DIR/vmkernel-zdump-"$curTime"
               banner "Checking $devname for new core dumps ..."
               
               runcmd "/usr/sbin/esxcfg-dumppart --copy --zdumpname $zDumpName --devname /vmfs/devices/disks/$devname --newonly" \
               "$tmp_dir/dumppart-copy.$$.txt" 
            fi
        else
            banner "Warning: No core partition configured."
            all_cores=0
            no_cores=1
        fi
   fi

   # Grab any core files we can find.  Move "found" ones to a place where
   # we won't include them next time this is run.

   if [ $no_cores -eq 0 ]; then
      addtar "$COREDUMP_DIR/vmkernel-*"
      
      addtar "/${VMX_BIN}-zdump.*"
      rm -f "/${VMX_BIN}-zdump.*"

      if [ $all_cores -eq 1 ]; then
         addtar "$COREDUMP_DIR/old_cores/vmkernel-*"
         addtar "$COREDUMP_DIR/old_cores/*.core.gz"
      fi

      if [ ! -d $COREDUMP_DIR/old_cores ]; then
         mkdir $COREDUMP_DIR/old_cores
	 rc=$?
         if [ $rc != 0 ]; then
            banner "Could not mkdir $COREDUMP_DIR/old_cores ($rc). Is something wrong with $COREDUMP_DIR?"
         fi
	 log "mkdir $COREDUMP_DIR/old_cores ($rc)"
      fi

      # move off old cores so we don't keep sending old ones.
      if [ $(ls $COREDUMP_DIR/vmkernel-* 2> /dev/null | wc -l) != 0 ]; then
         if [ -d $COREDUMP_DIR/old_cores ]; then
            mv $COREDUMP_DIR/vmkernel-* $COREDUMP_DIR/old_cores/
	    rc=$?
            if [ $rc != 0 ]; then
               banner "Could not archive cores ($rc). Is something wrong with $COREDUMP_DIR?"
            else
               banner "NOTE: All cores archived from $COREDUMP_DIR into $COREDUMP_DIR/old_cores."
            fi
	    log "moved old cores to $COREDUMP_DIR/old_cores/ ($rc)"
         fi
      fi

      # gzip & archive cos core file.
      if [ $no_service_cos_core -eq 0 ]; then
         cosCoreFile=`esxcfg-advcfg -q -g /Misc/CosCorefile`
         if [ -e "$cosCoreFile" ]; then
            coreBkup=$COREDUMP_DIR/old_cores/`basename $cosCoreFile`.$$.core.gz
            if [ -d $COREDUMP_DIR/old_cores ]; then
               gzip -fc $cosCoreFile > $coreBkup
               if [ $? != 0 ]; then
                  banner "Failed to gzip service console core file."
               else
                  addtar "$coreBkup"
                  rm -f $cosCoreFile
               fi
            fi
         fi
      fi
   fi

   #  Grab legacy config files and upgrade log (if they exist)
   addtar "/esx3-installation/etc/vmware" IGNORE_ERROR
   addtar "/esx3-installation/var/log" IGNORE_ERROR

   #	Add system configuration and log files. Wildcards
   #	may be used.

   addtar "/etc/hosts"
   addtar "/etc/group"
   addtar "/etc/resolv.conf"
   addtar "/etc/nsswitch.conf"
   addtar "/etc/ldap.conf"
   addtar "/etc/sysctl.conf"
   addtar "/etc/inittab"
   addtar "/etc/iproute2/"
   addtar "/etc/ntp.conf"
   addtar "/etc/openldap/"
   addtar "/etc/pam_smb.conf"
   addtar "/etc/exports"
   addtar "/etc/hosts.conf"
   addtar "/etc/hosts.allow"
   addtar "/etc/hosts.deny"
   addtar "/etc/krb*"
   addtar "/boot/grub/grub.conf"
   addtar "/boot/grub/device.map"
   addtar "/boot/grub/menu.lst"
   addtar "/etc/lilo.conf"
   addtar "/etc/modules.conf"
   addtar "/etc/opt/vmware/vpxa/vpxa.cfg"
   addtar "/etc/rc.d/rc.local"
   addtar "/etc/rc.d/init.d/vmware*"
   addtar "/etc/ssh/ssh_conf"
   addtar "/etc/ssh/sshd_config"
   addtar "/etc/vmkiscsi.conf" IGNORE_ERROR
   addtar "/etc/initiatorname.vmkiscsi" IGNORE_ERROR
   addtar "/etc/vmware-release"
   addtar "/etc/yp.conf"
   addtar "/etc/yum.conf"
   addtar "/etc/logrotate.conf"
   addtar "/etc/logrotate.d/"
   addtar "/etc/snmp/snmpd.conf"
   addtar "/etc/sysconfig"
   addtar "/etc/vmware/" IGNORE_ERROR
   addtar "/etc/opt/vmware/" IGNORE_ERROR
   addtar "/etc/xinetd.d/vmware-authd"
   addtar "/tmp/dumppart.log"
   addtar "/etc/syslog.conf"
   addtar "/tmp/vmware-*"

   if [ $no_cores -eq 0 ]; then
      addtar "/var/core/"
      addtar "/var/cores/"
   fi
  
   # For vmvisor we are collecting the whole /var/log directory much
   # earlier
   if [ $COS = "1" ]; then
      if [ $no_cores -eq 0 ]; then
         addtar "/var/log/vmware/core"
      fi
      addtar "/var/log/weasel.log" 
      addtar "/var/log/boot*" IGNORE_ERROR
      addtar "/var/log/initrdlogs"
      addtar "/var/log/messages*"
      addtar "/var/log/secure*"
      addtar "/var/log/dmesg"
      addtar "/var/log/vmkproxy"
      addtar "/var/log/vmkiscsid*" IGNORE_ERROR
      addtar "/var/log/vmkernel*"
      addtar "/var/log/vmksummary"
      addtar "/var/log/vmksummary.d/vmksummary*"
      addtar "/var/log/vmkwarning*"
      addtar "/var/log/vmware/"
      addtar "/var/log/cron*"
      addtar "/var/log/rpmpkgs*"
      addtar "/var/log/ipmi" IGNORE_ERROR
   else 
      addtar "/bootbank/local.tgz"
      addtar "/bootbank/oem.tgz"
      addtar "/bootbank/boot.cfg"
   fi

   addtar "/etc/fstab"
   addtar "/etc/pam.d/"
   addtar "/etc/cron*"
   addtar "/var/pegasus/*.conf*"
   addtar "/var/kerberos/krb5kdc/kdc.conf"
   addtar "/root/anaconda-ks.cfg" IGNORE_ERROR

   if [ $collect_test_esx_logs ]; then
      addTestEsxLogs
   fi

   if [ "$COS" = "1" ]; then
        runbackgroundcmd "rpm -qa --verify" "$tmp_dir/rpm-verify.$$.txt"
   fi

   # snarf cim classes
   runbackgroundcmd "/bin/cim-diagnostic.sh" "$tmp_dir/cim.$$.txt"
   runbackgroundcmd "/bin/lsi_log" "/$tmp_dir/lsi.$$.log"

   # collect aam information
   if [ -e /opt/LGTOaam512/vmware/aam_config_util.pl ] ; then
   	mkdir "$tmp_dir/aamSupport.$$"
   	runcmd "/usr/bin/perl /opt/LGTOaam512/vmware/aam_config_util.pl -cmd=support -dir=$tmp_dir/aamSupport.$$" "$tmp_dir/aam_config_util.output" NORETRY
   	addtar "$tmp_dir/aamSupport.$$/"
        rm -rf "$tmp_dir/aamSupport.$$"
   fi

   if [ "$COS" = "1" ]; then
   	addtar "/etc/opt/vmware/aam"
   else
	addtar "/var/run/vmware/aam"
   fi

   # webAccess config files
   addtar "/usr/lib/vmware/webAccess/tomcat/jakarta-tomcat-*/webapps/ui/WEB-INF/classes/*.properties"
   addtar "/usr/lib/vmware/webAccess/tomcat/jakarta-tomcat-*/webapps/ui/WEB-INF/classes/ui/*.properties"

   # grab the vmauthd and vmkauthd log files, if enabled
   if [ -f /etc/vmware/config ] ; then
      vmauthdLogFile=`getConfigVal "log.vmauthdFileName" "" "/etc/vmware/config"`
      vmkauthLogFile=`getConfigVal "log.vmkauthdFileName" "" "/etc/vmware/config"`
      for logFile in "$vmauthdLogFile" "$vmkauthdLogFile"; do
         if [ -n "$logFile" ] ; then
            if [ `dirname $logFile` = "." ] ; then
               logFile=/var/log/vmware/$logFile
            fi
            addtar $logFile
         fi
      done
   fi 

   # General cmds.
   runcmd "echo vm-support version: $VER" "$tmp_dir/vm-support-version.$$.txt"
   runcmd "uname -a" "$tmp_dir/uname.$$.txt"
   if [ "$COS" = "1" ]; then
	   runcmd "lspci -intel_conf1 -M" "$tmp_dir/lspci1.$$.txt"
	   runcmd "lspci -intel_conf1 -M -vn" "$tmp_dir/lspci2.$$.txt"
	   runcmd "lspci -vv" "$tmp_dir/lspci3.$$.txt"
	   runcmd "lspci -intel_conf1 -t -vv -n" "$tmp_dir/lspci4.$$.txt"
	   runcmd "lspci -v -b" "$tmp_dir/lspci5.$$.txt"
	   runcmd "/sbin/lsmod" "$tmp_dir/modules.$$.txt"
	   # added -l option to df to avoid NFS filesystems should the network
	   # be down
	   runcmd "df -al" "$tmp_dir/df.$$.txt"
	   # specify /vmfs to vdf, also to avoid any NFS filesystems
	   runcmd "vdf -h /vmfs" "$tmp_dir/vdf.$$.txt"
	   runcmd "ifconfig -a" "$tmp_dir/ifconfig.$$.txt"
	   runcmd "ping -c5 `/sbin/route -n | awk '{ if ($4 ~ /G/) print $2; }'`" "$tmp_dir/ping-gateway.$$.txt"
	   runcmd "ifconfig -a" "$tmp_dir/ifconfig_after.$$.txt"
	   runcmd "mii-tool -vv" "$tmp_dir/mii-tool-ethN.$$.txt" IGNORE_ERROR
	   runcmd "route" "$tmp_dir/route.$$.txt"
	   runcmd "mount" "$tmp_dir/mount.$$.txt"
	   runcmd "rpm -qa" "$tmp_dir/rpm.$$.txt"
	   runcmd "chkconfig --list" "$tmp_dir/chkconfig.$$.txt"
	   runcmd "/usr/sbin/dmidecode" "$tmp_dir/dmidecode.$$.txt" IGNORE_ERROR
	   runcmd "ls -lR /vmfs/devices" "$tmp_dir/vmfsDevices.$$.txt"
   else
           runcmd "df" "$tmp_dir/df.$$.txt"
	   runcmd "ls -lR /dev" "$tmp_dir/dev.$$.txt"
   fi
   runbackgroundcmd "fdisk -l" "$tmp_dir/fdisk.$$.txt"

   if [ -e /sbin/hplog ]; then
      # snarf hardware logs
      runcmd "/sbin/hplog -v" "$tmp_dir/hplog.$$.txt"
   fi

   # ESX-specific.
   runcmd "vmware -v" "$tmp_dir/vmware.$$.txt"
   # Skip esxupdate call for pxe/iso-image booted visor.
   # /bootbank is pointed to /tmp, and thus no boot.cfg under /bootbank
   if [ "${COS}" = "1" ] || [ "${COS}" = "0" -a -f "/bootbank/boot.cfg" ]; then
      runcmd "esxupdate query" "$tmp_dir/esxupdate-patch-history.$$.txt"
      runcmd "esxupdate query --vib-view" "$tmp_dir/esxupdate-vib-view.$$.txt"
   fi


   if [ -x /usr/bin/omreport ]; then
      # snarf Dell OpenManage information
      runcmd "/usr/bin/omreport system alertlog" "$tmp_dir/omreport-alertlog.$$.txt"
      runcmd "/usr/bin/omreport system cmdlog" "$tmp_dir/omreport-cmdlog.$$.txt"
      runcmd "/usr/bin/omreport system esmlog" "$tmp_dir/omreport-esmlog.$$.txt"
      runcmd "/usr/bin/omreport system postlog" "$tmp_dir/omreport-postlog.$$.txt"
      runcmd "/usr/bin/omreport chassis temps" "$tmp_dir/omreport-temps.$$.txt"
      runcmd "/usr/bin/omreport chassis fans" "$tmp_dir/omreport-fans.$$.txt"
      runcmd "/usr/bin/omreport chassis memory" "$tmp_dir/omreport-memory.$$.txt"
   fi

   runcmd "/usr/sbin/vmkload_mod -v10 -l" "$tmp_dir/vmkmod.$$.txt"

   #volume information added for vpa
   runcmd "ls -l /vmfs/volumes" "$tmp_dir/volume_list.vpa.txt"
   for VMFS in /vmfs/volumes/*; do
           if [ ! -d "$VMFS" ] || [ -h "$VMFS" ]; then
	       continue
	   fi
	   local vmfsBn=`basename $VMFS`
           runcmd "vmkfstools -P $VMFS" "$tmp_dir/$vmfsBn.vpa.txt"

           if [ $dump_vmfs_resfile -eq 1 ]; then 
                   echo -e "\nSaving volume header for $vmfsBn."

                   # we just save the volume header file for now.
                   addtar "$VMFS/.vh.sf"
                   # addtar "$VMFS/.fbb.sf"
                   # addtar "$VMFS/.pbc.sf"
                   # addtar "$VMFS/.sbc.sf"
                   # addtar "$VMFS/.fdc.sf"
           fi
   done

   if [ "$COS" = "1" ]; then
           runcmd "vmkchdev -L" "$tmp_dir/vmkchdev.$$.txt"
           runcmd "/usr/sbin/esxcfg-scsidevs -m" "$tmp_dir/esxcfg-scsidevs-vmfs.$$.txt"
           runcmd "/usr/sbin/esxcfg-scsidevs -l" "$tmp_dir/esxcfg-scsidevs.$$.txt"
           runcmd "/usr/sbin/esxcfg-scsidevs -a" "$tmp_dir/esxcfg-scsidevs-hba.$$.txt"
           runcmd "/usr/sbin/esxcfg-vswif -l" "$tmp_dir/esxcfg-vswif.$$.txt"
           runcmd "/usr/sbin/esxcfg-firewall -q" "$tmp_dir/esxcfg-firewall.$$.txt"

           # Add cos log files(, see PR 283772)
           cospath=$(dirname $(</proc/vmware/rootFsVMDKPath))
           if [ -n "$cospath" ]; then
              if [ -d "$cospath/logs" ]; then
                 addtar "$cospath/logs/*" IGNORE_ERROR
              fi
           fi
   fi

   runcmd "/usr/sbin/vmkerrcode -l" "$tmp_dir/vmkerrcode.$$.txt"

   runcmd "/usr/sbin/esxcfg-dumppart -c" "$tmp_dir/esxcfg-dumppart.$$.txt"
   runcmd "/usr/sbin/esxcfg-info -a" "$tmp_dir/esxcfg-info.$$.txt"
   runcmd "/usr/sbin/esxcfg-info -a -F 'xml'" "$tmp_dir/esxcfg-info-xml.$$.txt"
   runcmd "/usr/sbin/esxcfg-nas -l" "$tmp_dir/esxcfg-nas.$$.txt"
   runcmd "/usr/sbin/esxcfg-vswitch -l" "$tmp_dir/esxcfg-vswitch.$$.txt"
   runcmd "/usr/lib/vmware/bin/net-dvs -l" "$tmp_dir/net-dvs.$$.txt"
   runcmd "/usr/sbin/esxcfg-vmknic -l" "$tmp_dir/esxcfg-vmknic.$$.txt"
   runcmd "/usr/sbin/esxcfg-swiscsi -q" "$tmp_dir/esxcfg-swiscsi.$$.txt"
   runcmd "/usr/sbin/esxcfg-route -l" "$tmp_dir/esxcfg-route.$$.txt"
   runcmd "/usr/sbin/esxcfg-route -f V6 -l" "$tmp_dir/esxcfg-route6.$$.txt" IGNORE_ERROR
   runcmd "/usr/sbin/esxcfg-resgrp -l" "$tmp_dir/esxcfg-resgrp.$$.txt"
   runcmd "/usr/sbin/esxcfg-mpath -l" "$tmp_dir/esxcfg-mpath-paths.$$.txt"
   runcmd "/usr/sbin/esxcfg-mpath -b" "$tmp_dir/esxcfg-mpath-devices.$$.txt"
   runcmd "/usr/sbin/esxcfg-nics -l" "$tmp_dir/esxcfg-nics.$$.txt"
   runcmd "/usr/sbin/esxcli corestorage claimrule list" "$tmp_dir/esxcli-corestorage-claimrules.$$.txt"
   runcmd "/usr/sbin/esxcli nmp device list" "$tmp_dir/esxcli-nmp-devices.$$.txt"
   runcmd "/usr/sbin/esxcli nmp path list" "$tmp_dir/esxcli-nmp-paths.$$.txt"
   runcmd "/usr/sbin/esxcli nmp satp listrules" "$tmp_dir/esxcli-nmp-satp-rules.$$.txt"

   runcmd "/usr/sbin/vmkping -D -v" "$tmp_dir/vmkping.$$.txt"

   # iSCSI
   dumpFile=$tmp_dir/vmkiscsid.dump-db.$$.txt
   runcmd "/usr/sbin/vmkiscsid --dump-db=$dumpFile" "$tmp_dir/vmkiscsid.$$.txt"
   addtar "$dumpFile" IGNORE_ERROR

   if [ $COS = "1" ]; then
      runcmd "/sbin/ip -6 route list" "$tmp_dir/route6.$$.txt" IGNORE_ERROR
   fi

}


#
# snapshotOne
#
# snapshotOne: takes a single snapshot
#
snapshotOne() {
   local snapShotFiles=$1
   local dstDir=$2
   local num=$3
   local zip=$4
   local ERR_FILE=/dev/null

   # For some reason tar doesn't like to read directly from /proc
   # so 'tar -czf proc$num.tgz $FILES' doesn't work.

   mkdir -p $dstDir/proc > $ERR_FILE 2>&1 || exit 1
   for p in  $snapShotFiles ; do
      for f in `ls /proc/$p 2>/dev/null` ; do 
         cp -a --parents $f $dstDir > $ERR_FILE 2>&1
      done
   done
   date > $dstDir/proc/date
   mv $dstDir/proc $dstDir/proc$num > $ERR_FILE 2>&1 || exit 1
   if [ "$zip" != "0" ]; then
      tar -czf $dstDir/proc$num.tgz -C $dstDir proc$num > $ERR_FILE 2>&1
      rm -rf $dstDir/proc$num
   fi

   # Add a snapshot of the VSI tree as well.
   mkdir -p $dstDir/vsi > $ERR_FILE 2>&1 || exit 1
   if [ -x /usr/lib/vmware/bin/vsi_traverse ]; then
      /usr/lib/vmware/bin/vsi_traverse -s  > $dstDir/vsi/vsi.$num
   fi

   # Add a snapshot for the plm stats.
   # Vsh plugin requires an absolute path to the log directory.
   local plmDir=`pwd`/$dstDir/plm
   local vshCmd=/usr/lib/vmware/hostd/vsh
   mkdir -p $plmDir > $ERR_FILE 2>&1 || exit 1
   if [ -x $vshCmd ]; then
      local hostdLibDir=/usr/lib/vmware/hostd
      local plugin=$hostdLibDir/libsupportsvc.so
      LD_LIBRARY_PATH="$hostdLibDir" $vshCmd -e "puse $plugin; supportsvc_cmds/connect; supportsvc_cmds/login; supportsvc_cmds/printstatstofile $plmDir; quit" > /dev/null 2>&1
   fi
   return 0
}

#
# calculateSnapInterval
#
# calculateSnapInterval: measures how long a single snapshot
# takes, and sets the sleep interval to twice that.
#
calculateSnapInterval() {
   local startTime=`date +"%s"`
   snapshotOne "$1" "$2" "0" "$3" || exit 1
   local endTime=`date +"%s"`
   local interval=`expr '(' $endTime - $startTime ')' \* 2`
   if [ "$interval" = "0" ]; then
      interval=2
   fi
   echo "$interval"
}

#
# createSnapshots
#
# createSnapshots: creates multiple perf snapshots, 
# sleeping the specified (or calculated) amount between
# each snapshot.
#
createSnapshots() {
   local snapShotFiles=$1
   local dest=$2
   local duration=$3
   local sleepInterval=$4
   local zip=$5
   local i=0
   local startTime=`date +"%s"`

   echo -e "\nTaking performance snapshots.  This will take about $duration seconds."
   mkdir -p $dest
   echo -e '#!/bin/sh\n\nfor f in `ls proc*.tgz`; do\n   tar -xzf $f\n   rm $f\ndone\n' > $dest/untar.sh
   chmod +x $dest/untar.sh

   if [ "$sleepInterval" = "-1" ]; then
      i=1
      sleepInterval=`calculateSnapInterval "$snapShotFiles" "$dest" "$zip"`
      if [ "$?" != 0 ]; then
         echo "Error calculating interval: $sleepInterval" 
         exit 1
      fi

      echo "Snapshot interval is $sleepInterval" | tee $dest/interval
   fi

   schedStatsEnable  # Enable detailed scheduler stats.

   while [ 1 ]; do
      local curTime=`date +"%s"`
      if [ $(($startTime + $duration)) -lt $curTime ]; then
         echo -e "\nDone.  $i snapshots created."
         break
      fi
      if [ $i -eq 0 ]; then
	  echo -e "\nStarting vscsiStats."   # only print this message once
          log "starting vscsi stats collection"
      fi
      startVscsiStats $i # "start" vscsiStats each time to reset 30-min timeout
      sleep $sleepInterval
      if [ $quiet_mode -eq 0 ]; then
          echo -en "\rSnapping $i:" `expr $startTime + $duration - $curTime` " seconds left."
      fi
      snapshotOne "$snapShotFiles" "$dest" "$i" "$zip"
      i=`expr $i + 1`
   done
   schedStatsDisable # Disable detailed scheduler stats.
   stopVscsiStats $OUTPUT_DIR # stop vscsiStats collection
}

#
# createEsxtopShots
# createEsxtopShots: runs esxtop in batch mode for the prescribed 
# duration, taking snapshots between sleepIntervals
#
createEsxtopShots() {
   local esxtopbatchfile=$1
   local dest=$2
   local duration=$3
   local sleepInterval=$4
   local rcfile=$5
   local iterations=$(($duration/$sleepInterval+1))

   
   mkdir -p $dest
   if [ -e $rcfile ];then
       echo -e "\nUsing $rcfile to gather esxtop data\n"
       echo -e "\nTaking esxtop performance snapshots.  This will take about $duration seconds. Please stand-by..."
       esxtop -b -c $rcfile -d $sleepInterval -n $iterations > $dest/$esxtopbatchfile
   else
       echo -e "\nTaking esxtop performance snapshots.  This will take about $duration seconds.\n Please stand-by..."
       esxtop -b -a -d $sleepInterval -n $iterations > $dest/$esxtopbatchfile 
   fi      

   echo "Snapshot DONE"

 
}


#
# startSchedTrace
#
# starts schedtrace by loading the schedtrace module
# also starts the logchannellogger
#
startSchedTrace() {
    if [ -e $SCHEDTRACE_MOD ]; then       
        echo "Starting schedtrace."
	log "Starting schedtrace."
        /usr/sbin/vmkload_mod $SCHEDTRACE_MOD
        $CHANNELLOGGER schedtrace $SCHEDTRACE_FILE 2>/dev/null &
    fi
}

#
# stopSchedTrace
#
# unload schedtrace module
# also copy the file to vm-support destination directory
#
stopSchedTrace() {
    local dest=$1
    local ERR_FILE=/dev/null
    
    # check if schedtrace is loaded
    /usr/sbin/vmkload_mod -l |grep schedtrace > /dev/null
    if [ $? -eq 0 ]; then       
        echo -e "\nStopping schedtrace."
	log "Stopping schedtrace."
        /usr/sbin/vmkload_mod -u schedtrace
        sleep 10 #wait logchannellogger finish
        mkdir -p $dest/schedtrace > $ERR_FILE 2>&1 || exit 1
        mv $SCHEDTRACE_FILE $dest/schedtrace/
        cp /usr/sbin/schedtrace_format $dest/schedtrace/
    fi
}


#
# schedStatsEnable
#
# Enable detailed scheduler stats.
#
schedStatsEnable() {
    if [ -e $SCHED_STATS ]; then
        echo -e "\nStarting detailed scheduler stats."
        log "Starting detailed scheduler stats collection."
        # Enabling cpu state histograms."
        $SCHED_STATS -s 1
    fi
}

#
# schedStatsDisable
#
# Disable detailed scheduler stats.
#
schedStatsDisable() {
    if [ -e $SCHED_STATS ]; then
        echo -e "\nStopping detailed scheduler stats"
        log "Stopping detailed scheduler stats collection."
        # Disabling cpu state histograms.
        $SCHED_STATS -s 0
    fi
}


#
# startVscsiStats
#
# starts vscsiStats collection
# (data is only logged in vm-support output unless cmd tracing is enabled)
#
startVscsiStats() {
    local vscsiChannel=
    local initialized=$1
    if [ -e $VSCSISTATS_BIN ]; then       
	$VSCSISTATS_BIN -s > /dev/null
	if [ $vscsi_trace -eq 1 ]; then
	    if [ $initialized -eq 0 ]; then
		echo -e "\nStarting vscsi cmd trace for world group $vscsi_trace_wgid."
		log "\nStarting vscsi cmd trace for world group $vscsi_trace_wgid."
		$VSCSISTATS_BIN -s -t -w $vscsi_trace_wgid > $VSCSISTATS_TMP_FILE
		for VSCSITRACEHANDLES in $(grep traceChannel $VSCSISTATS_TMP_FILE); do
		    vscsiChannel=`echo $VSCSITRACEHANDLES | sed -n -e "s/<vscsiStats-traceChannel>//g" -e "s/<\/vscsiStats-traceChannel>//pg"`
		    $CHANNELLOGGER $vscsiChannel $VSCSISTATS_TMP_PATH/$vscsiChannel.vscsitrace 2>/dev/null &
		done
	    fi
	fi
    fi
}

#
# stopVscsiStats
#
# stops vscsiStats collection
# (data is only logged in vm-support output)
#
stopVscsiStats() {
    local dest=$1
    local loggers=
    if [ -e $VSCSISTATS_BIN ]; then       
	echo -e "\nStopping vscsiStats."
        log "stopping vscsi stats collection"
	$VSCSISTATS_BIN -x >  /dev/null
	if [ $vscsi_trace -eq 1 ]; then
	    sleep 2
	    mv $VSCSISTATS_TMP_PATH/*.vscsitrace $dest
	    rm $VSCSISTATS_TMP_FILE
	fi
    fi
}

#
# purgeFiles
#
# List of files that we don't want to keep.  
# vm-support.conf can be used for files that may 
# be optionally removed.
#
purgeFiles() {
   # list of files that shouldn't be included
   PURGELIST="/etc/vmware/ssl/"

   for FILE in ${PURGELIST}
   do
      log "Removing $FILE from vm-support."
      rm -rf $OUTPUT_DIR$FILE 2>/dev/null
   done
}

#
# createTar
#
# Create the final tar file &  cleanup.
#	Perform the tar ('S' for sparse core files)
#
createTar() {
   purgeFiles

   banner "Creating tar archive ..."

   if [ $print_file_list -eq 1 ]; then
       tar -czSvf $TARFILE $OUTPUT_DIR
   else
       tar -czSf $TARFILE $OUTPUT_DIR
   fi

   if [ $? != 0 ]; then
           banner "The tar did not successfully complete!" \
                   "If tar reports that a file changed while" \
                   "reading, please attempt to rerun this script."
   else
           fullPath="$(pwd | sed s/[\/]$//)/$TARFILE"
           size=`stat -c %s "$TARFILE"`
           if [ $size -gt 20000000 ]; then
                   banner "File: $fullPath" \
                          "NOTE: $TARFILE is greater than 20 MB." \
                          "Please do not attach this file when submitting an incident report." \
                          "Please contact VMware support for an ftp site." \
                          "To file a support incident, go to http://www.vmware.com/support/sr/sr_login.jsp"
           else
                   banner "File: $fullPath" \
                          "Please attach this file when submitting an incident report." \
                          "To file a support incident, go to http://www.vmware.com/support/sr/sr_login.jsp"
           fi
           banner "To see the files collected, run: tar -tzf $fullPath"
   fi


   #	Clean up temporary files

   rm -rf $OUTPUT_DIR

   if [ $? != 0 ]; then
           banner "$OUTPUT_DIR was not successfully removed.  Please remove manually."
   fi
   echo "Done."
}

# 
# MakeOutputDir
#
#  Tries to make a subdir to put all your files in.  Dies if it does not create.
#
MakeOutputDir() {
   mkdir $OUTPUT_DIR

   if [ $? != 0 ]; then
	banner "Could not create ./${OUTPUT_DIR}... Exiting..." \
               "Please cd to a directory to which you can write" # Thanks Adam!
	exit 1
   fi
  
   # This is a guarantee that the tmp directory will exist for blocking commands
   # to write their output to.
   mkdir $OUTPUT_DIR/tmp
   
   if [ $? != 0 ]; then
	banner "Could not create ./${OUTPUT_DIR}/tmp... Exiting..." \
               "${OUTPUT_DIR} must be writeable." 
	exit 1
   fi

   touch $VMSUPPORT_LOG_FILE; # enable logging of vm-support commands
}

#
# VMDumper
#
# Run the vmdumper command and add its output to the vmdumper log
#
VMDumper() {
    # Since vmdumper tends to mutate running VMs, also put a hint in the
    # vmkernel log
    vmklog "vm-support: running vmdumper $@"

    echo "running vmdumper $@" >> $OUTPUT_DIR/hungvm/vmdumper-commands.$$.txt
    /usr/lib/vmware/bin/vmdumper "$@" 2>&1 | tee -a $OUTPUT_DIR/hungvm/vmdumper-commands.$$.txt 
}


#
# DebugHungVM
#
#  Tries to capture some useful information about a single hung VM.
#  (with out relying on any other services being alive and well (ie serverd)
#
DebugHungVM() {
   local wid=$1; # wid of the vmm0 world
   local sendAbort="no"
   local sendNMI="no"
   local takeScreenShot="no"
   local name=`/usr/lib/vmware/bin/vmdumper -l 2>/dev/null | grep "^vmid=$wid"`

   if [ -z "$name" ] ; then
      banner "Cannot find world '$wid'"
      exit 1
   fi

   MakeOutputDir

   local vmxCfg=$(echo $name | sed -n 's/.*cfgFile="\(.*\)".*uuid=.*/\1/p')
   local vmxDirectory=$(dirname "$vmxCfg")

   runcmd "echo 'Suspected hung vm is: $vmxCfg, wid=$wid on $DATE'" "README.hungVM"

   echo ""
   echo ""
   read -p "Can I include a screenshot of the VM $wid? [y/n]: " takeScreenShot

   if [ $suspend_hung_vm -eq 0 ] ; then 

   	read -p "Can I send an NMI (non-maskable interrupt) to the VM $wid? \
This might crash the VM, but could aid in debugging [y/n]: " sendNMI

   	read -p "Can I send an ABORT to the VM $wid? \
This will crash the VM, but could aid in debugging [y/n]: " sendAbort

   fi

   # Grab info about the running processes before poking anything through the
   # hungVM probes
   #
   # Replace OUTPUT_DIR with a different location for the pre-hungvm
   # files, so they don't get overwritten by the post-hungvm support run.
   old_OUTPUT_DIR=${OUTPUT_DIR}
   OUTPUT_DIR="${OUTPUT_DIR}/pre-hungvm"
   MakeOutputDir ## create the pre-hungVM output dir
   snarf_running_state
   OUTPUT_DIR="${old_OUTPUT_DIR}"

   banner "Grabbing data & core files for world $wid.  This will take 5 - 10 minutes."

   createSnapshots "" "$OUTPUT_DIR/hungvm" $snap_duration $snap_interval 1

   trap "VMDumper $wid samples_off; exit;" HUP INT QUIT TERM EXIT KILL

   banner "Collecting VM samples (this may take several minutes) ..."
   VMDumper $wid samples_on
   sleep 60

   if [ "$takeScreenShot" = "yes" ] || [ "$takeScreenShot" = "y" ]; then
      VMDumper $wid screenshot 
   fi

   #
   # grab core files.
   #
   banner "Creating core files (this may take several minutes) ..."
   VMDumper $wid unsync 
   sleep 60
   for unysncCore in "$vmxDirectory"/vmware*-core*
      do
         mv -f "$unysncCore" "${unysncCore}-unsync" > /dev/null 2>&1 
   done
   VMDumper $wid sync 
   sleep 60
   VMDumper $wid vmx
   sleep 120

   if [ ! -f "$vmxDirectory"/${VMX_BIN}-zdump.* ]; then
      VMDumper $wid vmx_force
      sleep 120
   fi

   banner "Done with core dumps"
   
   VMDumper $wid samples_off
   trap - HUP INT QUIT TERM EXIT KILL

   if [ $suspend_hung_vm -eq 1 ]; then

      touch $vmxDirectory/temp.vmsupport.timestamp.$$
      local time_before_suspend=`stat -c "%Z" $vmxDirectory/temp.vmsupport.timestamp.$$`
      rm $vmxDirectory/temp.vmsupport.timestamp.$$

      VMDumper $wid suspend_vm
      banner "Note: This includes your VM's memory state in the vm-support file."\
             "Depending on the memory size of the VM, this operation could take >15 minutes."

      local suspend_vmss_file=""
      local count=0

      while [ $count -lt 180 ] && ! [ -f /$suspend_vmss_file ]; do
	 UpdateSpinner "Waiting for memory file write to begin"
         count=`expr $count + 1`
         sleep 1

	 for possible_vmss in `ls $vmxDirectory/*.vmss 2>/dev/null` ; do
	    local possible_vmss_timestamp=`stat -c "%Z" $possible_vmss 2>/dev/null`

	    if [ $possible_vmss_timestamp -gt $time_before_suspend ] ; then
	       suspend_vmss_file=$possible_vmss
	       break
	    fi
	 done
      done

      echo ""

      if [ -f $suspend_vmss_file ] ; then
         
	 while ! [ "`/usr/lib/vmware/bin/vmdumper -l 2>/dev/null | grep "^vmid=$wid"`" = "" ] ; do
	    
	    UpdateSpinner "Waiting for memory file write to finish"
	    sleep 1
	    
	 done

	 count=0

	 # wait 10 more seconds to guarantee everything gets finalized
	 while [ $count -lt 10 ] ; do
	    
	    UpdateSpinner "Waiting for memory file write to finish"
	    sleep 1
	    count=`expr $count + 1`
	 
	 done

	 banner "Memory file write finished."
      
      else 
         banner "Could not suspend VM... Please try again or contact VMware support."
      fi
   fi

   if [ "$sendNMI" = "yes" ] || [ "$sendNMI" = "y" ]; then
      VMDumper $wid nmi
   fi

   if [ "$sendAbort" = "yes" ] || [ "$sendAbort" = "y" ]; then
      local proxyPid=""
      
      if [ "$COS" = "1" ]; then
         # XXX A somewhat fragile lookup
         proxyPid=$(pgrep -f "vmkload_app.*${vmxCfg}")
      else
         proxyPid=$(echo $name | sed -n 's/.*vmxCartelID=\(.*\)/\1/p')
      fi

      if [ -n "$proxyPid" ]; then
         # Send SIGUSR1 to the proxy. The signal handler in the proxy will 
         # send a SIGABRT to the cartel and also dump core once the VM is killed
	 kill -USR1 $proxyPid > /dev/null 2>&1

         # Wait until the vmx and vmm worlds die and the proxy dumps core
         local proxyKilled=0
         local count=0
         local vmkloadAppCore=""
         
         while [ $count -lt 18 ] && [ $proxyKilled -eq 0 ]; do
	    sleep 10 
            count=`expr $count + 1`
            kill -0 $proxyPid >/dev/null 2>&1
            if [ $? -eq 1 ]; then
               proxyKilled=1
            fi
         done

         if [ "$COS" = "1" ]; then
            if [ $proxyKilled != 1 ]; then
               banner "Proxy failed to respond after $count tries. Forcing proxy Abort"
               kill -ABRT $proxyPid > /dev/null 2>&1
               #Look in /var/log/vmware/hostd for the proxy core file
               local coreFile=`ls /var/log/vmware/hostd/core.* 2>/dev/null | grep $proxyPid`
               if [ -n "$coreFile" ]; then
                  vmkloadAppCore="/var/log/vmware/hostd/$coreFile"
               fi
            else 
               # get the location of the core file and add it to the tar file
               vmkloadAppCore=$(tail -100 /var/log/vmkproxy | egrep '.*\['$proxyPid'\].*vmkload_app core file.*' | sed 's/.*file:\(.*\)/\1/')
            fi
         else 
             if [ $proxyKilled != 1 ]; then
                kill -ABRT $proxyPid > /dev/null 2>&1
             fi
         fi

         if [ -n "$vmkloadAppCore" ]; then
            banner "Adding proxy core file to tar"
            addtar $vmkloadAppCore
         fi
      else 
         banner "Cannot find pid for world $wid, not aborted." 
      fi
   fi
   banner "Adding all files in '$vmxDirectory' to tar"

   snarfVMFiles "$vmxDirectory"
   
   
   if [ "$COS" = "1" ]; then
      addtar /proc/vmware/log
      runcmd 'cat /proc/vmware/log' "$tmp_dir/vmkernel-after.$$.log"
   fi

   rm -f "$vmxDirectory"/${VMX_BIN}-zdump.*
   rm -f "$vmxDirectory"/vmware*-core*
}

#
# isVMFS
#
#  Checks if a path is a vmfs volume
#  Returns 1 if it is, 0 otherwise
#
isVMFS() {
   path=$1

   if [ -x "/usr/sbin/vmkfstools" ]; then 
      vmkfstools="/usr/sbin/vmkfstools";
   elif [ -x "/sbin/vmkfstools" ]; then 
      vmkfstools="/sbin/vmkfstools";
   else 
      return 0;
   fi   
                                    
   vmfs=`$vmkfstools -P $path |  awk '/VMFS-[0-9]\.[0-9]/'`
                                          
   if [ "$vmfs" = "" ]; then 
      return 0;
   else 
      return 1;
   fi   
}
                                                                           
#
# addTestEsxLogs
#
# Add test-esx logs to the tar file.
#
addTestEsxLogs() {
# test-esx logs can be found under /tmp/test-esx*
# and under /vmfs/volumes/*/test-esx*

   addtar "/tmp/test-esx*" IGNORE_ERROR

# Go through each directory under /vmfs/volumes and check if its a vmfs volume
   for FILE in /vmfs/volumes/*; do
      if [ ! -d "$FILE" ] || [ -h "$FILE" ] ; then
	  continue;
      fi
      isVMFS "$FILE"
      if [ $? ]; then
         addtar "$FILE/test-esx*" IGNORE_ERROR
      fi
   done
}

#
# finishSupportDataCollection
#
#  Last part of vm-support that runs... Waits on background tasks and creates the
#  tar file.
#
finishSupportDataCollection() {

        if [ $snapshot_only -ne 1 ] && [ $esxtopshot_only -ne 1 ]; then
	   # Grab the multitude of random host files we might be interested in
           snarf_system_state
	fi

	banner "Waiting up to ${BACKGROUND_CMD_WAIT} seconds for background commands to complete:"

	loge "Blocking commands were:${BACKGROUND_CMD_LIST}\n"

	# do the necessary cleanup on the following signals: HUP INT QUIT TERM EXIT KILL 
	stopBackgroundWaitingOnException() {
            log "Got signal waiting for background processes. Proceeding to create tar file."
	    createTar
	    trap - HUP INT QUIT TERM EXIT KILL
	    exit 1
	}
	   
	trap stopBackgroundWaitingOnException HUP INT QUIT TERM EXIT KILL
	
	totalBackgroundWait=0
	while [ ! $totalBackgroundWait -gt $BACKGROUND_CMD_WAIT ]; do
	
		LIVE_PIDS=""
		
		if [ "${BACKGROUND_CMD_PIDS}" = "" ]; then 
			break;
		fi
	
		for p in ${BACKGROUND_CMD_PIDS}; do
			if ! kill -0 $p 2>/dev/null; then
				# pid $p is dead
	    
				# Check exit status ...
				if ! wait $p; then
					log "Background process $p had error."
				fi
			else
				# Pid p is still running ...
				LIVE_PIDS=${LIVE_PIDS}" ${p}"
			fi
		done
	
		# Remove the dead pids
		BACKGROUND_CMD_PIDS="${LIVE_PIDS}"
	
		# Let some more backgrounded pids go
		sleep 2

		UpdateSpinner "Waiting for background commands"
	
		totalBackgroundWait=$(( $totalBackgroundWait + 2 ))
	
		if [ $totalBackgroundWait -gt ${BACKGROUND_CMD_WAIT} ]; then
			# took too long ...
			log "Background process wait time expired: $LIVE_PIDS."
		fi
	done
    
	trap - HUP INT QUIT TERM EXIT KILL
	
	#Now tar up everything into one file.
	createTar
}

#
# cleanupOnException
#
# do the necessary cleanup on the following signals: HUP INT QUIT TERM EXIT KILL 
#
cleanupOnException() {
    trap - HUP INT QUIT TERM EXIT KILL
    stopSchedTrace $OUTPUT_DIR  #stop schedtrace if it's loaded
    schedStatsDisable
    stopVscsiStats $OUTPUT_DIR # stop vscsiStats collection
    finishSupportDataCollection
    exit 1
}


snap_duration=300
snap_interval=10
all_cores=0
no_cores=0
no_service_cos_core=0
schedtrace=0
snapshot=0
snapshot_only=0
esxtopshot=0
esxtopshot_only=0
esxrcfile=0
hung_vm=0
hung_vm_wid=0
suspend_hung_vm=0
quiet_mode=0
print_file_list=0
force_vmfs_working_dir=0
# working_dir is either user-specified or "/var/tmp" on visor.
working_dir=
dump_vmfs_resfile=0
vscsi_trace_wgid=
vscsi_trace=0

#
# main()
#
main()
{
if [ "$COS" = "1" ]; then 
   optString="lnNahfcsSpPC:Sd:i:xX:Z:t:qw:rTv"
else
   optString="lnahsSpPC:d:i:xX:Z:qw:rTv"
fi

while getopts $optString arg ; do
   case "$arg" in
      "n") no_cores=1 ;;
      "N") no_service_cos_core=1 ;;
      "a") all_cores=1 ;;
      "p") esxtopshot=1 ;;
      "P") esxtopshot_only=1 ;;
      "C") esxrcfile=$OPTARG ;;
      "s") snapshot=1 ;;
      "c") schedtrace=1 ;;
      "S") snapshot_only=1; ;;
      "d") snap_duration=$OPTARG ;;
      "i") snap_interval=$OPTARG ;;
      "Z") hung_vm=1; suspend_hung_vm=1 ; hung_vm_wid=$OPTARG ;;
      "X") hung_vm=1; hung_vm_wid=$OPTARG ;;
      "x") hung_vm=1 ;;
      "t") vscsi_trace=1; vscsi_trace_wgid=$OPTARG ;;
      "q") quiet_mode=1 ;;
      "l") print_file_list=1 ;;
      "f") force_vmfs_working_dir=1 ;;
      "w") working_dir=$OPTARG ;;
      "r") dump_vmfs_resfile=1 ;;
      "T") collect_test_esx_logs=1 ;; ## VMware internal use only
      "v") version ;;
      "h") usage ; exit ;;
        *) usage ; exit 1 ;;
   esac
done

# Start message
banner "VMware ESX Support Script $VER"

# Print if vmcp is enabled.  If an env variable named 'usevmcp'
# exists, vmcp will be enabled.
if [ -n "$usevmcp" ]; then 
   echo "Using vmcp."
fi

# Make sure there are no extraneous options on the command line.
# Once we exclude args parsed by getopts, there should be nothing left.
shift $(expr $OPTIND - 1)
if [ $# -gt 0 ]; then
   banner "Extraneous parameters not permitted."
   usage;
   exit 1;
fi

# Sanity check args
if [ $all_cores -eq 1 ] && [ $no_cores -eq 1 ]; then
	banner "The -n and -a flags are mutually exclusive."
	exit 1
fi

if [ $snapshot -eq 1 ] && [ $snapshot_only -eq 1 ]; then
	banner "The -S and -s flags are mutually exclusive."
	exit 1
fi

if ( [ $snapshot -eq 1 ] || [ $snapshot_only -eq 1 ] ) && ( [ $esxtopshot -eq 1 ] || [ $esxtopshot_only -eq 1 ] ); then
	banner "The "S" and the "P" flags are mutually exclusive."
	exit 1
fi


#	Check for root privilege
if [ $(whoami) != "root" ]; then
	banner "You must be root to run this script."
	exit 1
fi

working_dir_param=${working_dir}

if [ "$COS" = "0" ]; then
        force_vmfs_working_dir=1
        no_service_cos_core=1
	if [ -z $working_dir ]; then
	   working_dir="/var/tmp"
	fi
fi

#       Set the working directory if specified
if [ -n "$working_dir" ]; then
        if ! cd "$working_dir"; then
                banner "Could not set working directory to '$working_dir'."
                exit 1
        fi
fi

# $tmp_dir is BOTH 
#    -the real directory where runcmd output is temporarily stored.
#    -the path in the tar file where the runcmd output is permanently stored.
# If the user specified a working directory, use 'pwd' to turn it into a canonical path 
#    because a relative path would mess up the addtar() logic.
# It there was no user-specified working directory, we can use /tmp as the default.
if [ -z ${working_dir} ]; then
   tmp_dir=${DEFAULT_TMP_DIR}
else
   tmp_dir=$(pwd)
fi

if [ $force_vmfs_working_dir -ne 1 ]; then

	case "$(pwd)" in 
	
		/vmfs/volumes/*) 
	
		banner "The working directory should not be on a VMFS volume." \
			"" \
			"Please run vm-support from another directory or specify a different" \
			"working directory using the -w flag."

		exit 1

	esac

fi

# Source /etc/profile.  If we can't find it, it's the users problem to get
# their paths straight.

if [ -f /etc/profile ]; then
	. /etc/profile
fi

# Protect against non-default values of $IFS (Not all scripts in /etc/profile.d/ 
# are good citizens).
unset IFS

# DebugHungVM and createSnapshots depend on these vars, so set them up in time.
VSCSISTATS_TMP_PATH="$tmp_dir/"
VSCSISTATS_TMP_FILE=$VSCSISTATS_TMP_PATH/vscsiStatsTraceList.tmp

if [ $hung_vm -eq 1 ];then
  if [ $hung_vm_wid -eq 0 ]; then
     #
     # List the available VMs to dump (don't actually dump anything)
     #
     vmdumperApp=/usr/lib/vmware/bin/vmdumper
     if [ ! -x ${vmdumperApp} ]; then
        banner "Missing application (${vmdumperApp}) to list running VMs."
        exit 2
     fi
     runningVMs=$(/usr/lib/vmware/bin/vmdumper -l  | wc -l)
     if [ $runningVMs -eq 0 ]; then
        banner "Couldn't find any running VMs"
     else 
        banner "Available worlds to debug:"
        /usr/lib/vmware/bin/vmdumper -l | sed -n 's/pid=.*displayName="\(.*\)".*$/\1/p'
     fi
     exit 1
  else 
     #
     # Dump state for a single hung VM
     #
     # This code calls MakeOutputDir on its own
     #
     DebugHungVM $hung_vm_wid
  fi
else
  MakeOutputDir
fi

# This is the first place that we can log() to file.
log "Starting VMware ESX Support Script $VER."
# Save the working dir to file in case the user specified something.
log "Current working dir:($(pwd))"
log "working dir parameter, if any:(${working_dir_param})"
echo ${tmp_dir} > "${TMP_DIR_FILE}"
log "Temp dir:(${tmp_dir}) saved to ${TMP_DIR_FILE}. Command output is usually saved here."
log "Output dir:(${OUTPUT_DIR})"

# In quiet mode, print this here since the spinner won't be printed/updated
if [ $quiet_mode -eq 1 ]; then
    banner "Preparing files ..."
fi

if [ $COS = "0" ]; then
   # In vmvisor everything in /var/log is useful so we don't need to be
   # selective.
   addtar "/var/log"

   # grab esxupdate logs while we are at it
   addtar "/locker/db/esxupdate.log" IGNORE_ERROR
fi

#
# Before dumping host-wide state, do (performance-related)
# periodic snapshots
#
if  [ $snapshot -eq 1 ] || [ $snapshot_only -eq 1 ]; then
   # SchedTrace depends on this.
   SCHEDTRACE_FILE="$tmp_dir/schedtrace"
   # 
   # People might get bored waiting for the snapshoting to finish, so
   # install a signal handler that will create the final tar even if the snapshot
   # process gets interrupted.
   trap cleanupOnException HUP INT QUIT TERM EXIT KILL

   zip=1
   if [ $schedtrace -eq 1 ]; then
       startSchedTrace    # start schedtrace
   fi
   
   createSnapshots "$SNAP_SHOT_FILES" "$OUTPUT_DIR/snapshots" \
                   $snap_duration $snap_interval $zip

   if [ $schedtrace -eq 1 ]; then
       stopSchedTrace $OUTPUT_DIR  #stop schedtrace if it's loaded
   fi   
   echo -e "\rDone with performance snapshots."

   trap - HUP INT QUIT TERM EXIT KILL
fi


# Before dumping host-wide state, do (performance-related)
# esxtop snapshots
#
if  [ $esxtopshot -eq 1 ] || [ $esxtopshot_only -eq 1 ]; then

   # People might get bored waiting for the snapshoting to finish, so
   # install a signal handler that will create the final tar even if the snapshot
   # process gets interrupted.
   trap cleanupOnException HUP INT QUIT TERM EXIT KILL


   
   createEsxtopShots "$ESXTOPSHOTFILE" "$OUTPUT_DIR/esxtopshots" \
                   $snap_duration $snap_interval $esxrcfile
  
   echo -e "\rDone with (esxtop) performance snapshots."

   trap - HUP INT QUIT TERM EXIT KILL
fi

#
# Collect all the host-wide state and tar it up
#
finishSupportDataCollection
}

main "${@}"
#eof
