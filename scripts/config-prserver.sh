#!/bin/bash
#  Copyright (c) 2005-2008,2010-2013 Wind River Systems, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

# ------------------------------------------------------------------------
# A tool to manipulate a PR server in a Wind River Linux project build tree.
# The primary use for it is starting and stopping the server in a consistent
# fashion.
#
# NOTE: This script is only intended to be used if you are setting up a shared
# PR Server.  For a local PR server in a single build, you do not need to use
# this script.  bitbake handles starting and stopping the service
# automatically.

# Setup globals
unset pr_host
unset pr_pid
unset pr_port

build_top="."
pr_action="start"
pr_db="${build_top}/prserv.sqlite3"
pr_xdb="${build_top}/prserv-db.ex"
pr_infofile="${build_top}/prserv-info"
pr_logfile="${build_top}/prserv.log"
pr_loglevel=

unset build_top_i
unset pr_db_i
unset pr_host_i
unset pr_logfile_i
unset pr_loglevel_i
unset pr_pid_i
unset pr_port_i

function find_pr_info
{
	eval `grep '^PRSERV_HOST' ${build_top}/local.conf | sed 's/"//g' | cut -f2- -d\= | sed 's/:/ pr_port=/' | sed 's/^ /pr_host=/'`
}

function log_pr_info
{
	if [ ! -f ${pr_infofile} ] ; then
		# the information file, or the directory where it will live, doesn't exist.  Create it.
		mkdir -p ${pr_infofile%/*} || exit 1
	fi

	# NOTE: log_pr_info can change the values for pr_host and pr_port.
	# This should rarely happen, but it will in the case where --port=0.
	# The only way for us to know what port has actually been auto-selected
	# is to watch the log to see what port the PR Server reports.
	eval $(perl -n -e '
		next if !m/NOTE: Started/;
		if (m/IP:\s+([^,\s]+)[,\s]+/) { print "pr_host=$1;"; }
		if (m/PORT:\s+([^,\s]+)[,\s+]/) { print "pr_port=$1;"; }
		if (m/PID:\s+([^,\s]+)[,\s+]/) { print "pr_pid=$1;"; }
	' ${pr_logfile})
	cat >${pr_infofile} <<EOT
# DO NOT EDIT THIS FILE!
# This file is automatically generated by $0
# when managing a PR server.  It should only be written by that script.
EOT
	echo "build_top_i=${build_top}" >> ${pr_infofile}
	echo "pr_db_i=${pr_db}" >> ${pr_infofile}
	echo "pr_host_i=${pr_host}" >> ${pr_infofile}
	echo "pr_logfile_i=${pr_logfile}" >> ${pr_infofile}
	echo "pr_pid_i=${pr_pid}" >> ${pr_infofile}
	echo "pr_port_i=${pr_port}" >> ${pr_infofile}
	echo "pr_loglevel_i=${pr_loglevel}" >> ${pr_infofile}
}

function pr_status
{
	# Quick check for a running prserver with the expected PID

	if [ -f ${pr_infofile} ]; then
		# We have an infofile to consult, that's promising.
		. ${pr_infofile}
		if [ -n "${pr_pid_i}" ]; then
			# The infofile appears to have contained PID information.
			if $(pgrep -f bitbake-prserv | grep -q "$pr_pid_i") ; then
				# There is a server running and it appears to
				# be ours based on the infofile PID and a
				# running prserv process that has that PID.
				return 0
			fi
		fi
	fi
	return 1
}

function load_pr_info
{
	if pr_status ; then
		# the current pr_infofile appears to point to a running PR
		# server, load those values.
		build_top=${build_top_i}
		pr_db=${pr_db_i}
		pr_host=${pr_host_i}
		pr_logfile=${pr_logfile_i}
		pr_loglevel=${pr_loglevel_i}
		pr_pid=${pr_pid_i}
		pr_port=${pr_port_i}

		unset build_top_i
		unset pr_db_i
		unset pr_host_i
		unset pr_logfile_i
		unset pr_loglevel_i
		unset pr_pid_i
		unset pr_port_i
		return 0
	fi
	return 1
}

function pr_start
{
	if pr_status ; then
		echo "There already appears to be an active PR server (pid: $pr_pid)"
		echo "using infofile: ${pr_infofile}."
		echo "Refusing to start a second PR server with the same info file."
		echo "If you really want to start a second PR server on please"
		echo "specify (at least) a different infofile for it with the -i option."
		exit 1
	fi

	if [ -z "${pr_host}" -a -z "${pr_port}" ] ; then
		# if both host and port info were omitted, we'll attemp to make
		# our best guess based on the local.conf in the top build
		# directory.  After that, either we've got values in both
		# pr_host and pr_port or we assume the defaults.
		find_pr_info
	fi

	# Prepare to do all kinds of good logging stuff.
	if [ ! -f ${pr_logfile} ] ; then
		# the logfile, or the directory where it will live, doesn't exist.  Create it.
		mkdir -p ${pr_logfile%/*} || exit 1
	fi

	if [ ! -f ${pr_db} ] ; then
		# the database, or the directory where it will live, doesn't exist.  Create it.
		mkdir -p ${pr_db%/*} || exit 1
	fi

	if [ ! -f ${pr_infofile} ] ; then
		# the information file, or the directory where it will live, doesn't exist.  Create it.
		mkdir -p ${pr_infofile%/*} || exit 1
	fi

	${build_top}/bitbake/bin/bitbake-prserv --start --host=${pr_host:=localhost} --port=${pr_port:=0} -f ${pr_db} -l ${pr_logfile} ${pr_loglevel:+--loglevel=$pr_loglevel}
	if [ $? -eq 0 ]; then
		log_pr_info
		echo "PR Server started (pid: ${pr_pid} addr: ${pr_host} port: ${pr_port})"
		echo ""
		echo "You should not attempt to halt this server by killing the process. Instead you"
		echo "should stop it by running this script with the 'stop' action or by echo issuing:"
		echo ""
		echo "	'bitbake-prserv --stop --host=${pr_host} --port=${pr_port}' in a bitbake shell"
		echo ""
		echo "You can access this server from another build by passing:"
		echo ""
		echo "	--enable-prserver=${pr_host}:${pr_port}"
		echo ""
		echo "in the list of configure options."
	else
		echo "Failed to start PR server for some reason."
		echo "Consult ${pr_logfile} for more information."
		exit 1
	fi
}

function pr_stop
{
	if load_pr_info ; then
		echo "Killing pr-server (pid: ${pr_pid})"
		${build_top}/bitbake/bin/bitbake-prserv --stop --host=${pr_host:=localhost} --port=${pr_port:=0} -l ${pr_logfile} ${pr_loglevel:+--loglevel=$pr_loglevel}
	else
		echo "No PR Server information file available, unable to locate a server to stop."
		exit 1
	fi
}

function pr_help
{
	echo "$0 [options]"
	echo ""
	echo " Options:"
	echo "	-a action	The action to perform. One of the following actions:"
	echo "			start:   start a new pr-server"
	echo "			stop:    cleanly kill a running pr-server"
	echo "			restart: attempt to stop and re-start a current pr-server"
	echo "			import:  import a previously exported pr-server database"
	echo "				 into the current pr-server database"
	echo "			export:  export the current pr-server database, suitable"
	echo "				 for re-import later."
	echo "			(default: start)"
	echo "	-h host		The hostname or IP address to bind the server to."
	echo "	-p port		The port to listen on."
	echo "	-b build_top	The top-level of the Wind River Linux project build. (default: .)"
	echo "	-d database	The full path to the prserver database (default: ${pr_db})"
	echo "	-l logfile	The full path to the prserver logfile (default: ${pr_logfile})"
	echo "  -L loglevel	The desired log level {EMERG, ALERT, CRIT, ERR, WARNING, NOTICE, INFO, DEBUG}"
	echo "	-x exportdb	The full path to an exported prserver database (default: ${pr_xdb})"
	echo ""
	echo " Note: -h and -p are required options, however if absent from the command line, they"
	echo " an attempt will be made to guess appropriate values by looking at the PRSERV_HOST"
	echo " value from <build_dir>/local.conf.  If this fails, the default values will be"
	echo " localhost and a port number 0, meaning auto-selected at server start time."
	echo ""
	echo " The -x option is only used with the 'import' or 'export' actions."
}

function pr_restart
{
	pr_stop
	pr_start
}

function pr_import
{
	local pr_was_running=1
	if ! pr_status ; then
		echo "A PR Server does not appear be running already.  Attempting to start it before proceeding."
		pr_start
		pr_was_running=0
	fi
	bitbake-prserv-tool import ${pr_xdb}
	if [ $pr_was_running -eq 0 ]; then
		echo "The PR server was not running prior to export, attempting to stop."
		pr_stop
	fi
}

function pr_export
{
	local pr_was_running=1
	if ! pr_status ; then
		echo "A PR Server does not appear be running already.  Attempting to start it before proceeding."
		pr_start
		pr_was_running=0
	fi
	bitbake-prserv-tool export ${pr_xdb}
	if [ $pr_was_running -eq 0 ]; then
		echo "The PR server was not running prior to export, attempting to stop."
		pr_stop
	fi
}

# main
OPTIND=1
while getopts "a:h:p:b:d:l:x:i:L:" opt ; do
	case $opt in
		a ) pr_action=$OPTARG ;;
		h ) pr_host=$OPTARG ;;
		p ) pr_port=$OPTARG ;;
		b ) build_top=$OPTARG ;;
		d ) pr_db=$OPTARG ;;
		i ) pr_infofile=$OPTARG ;;
		l ) pr_logfile=$OPTARG ;;
	        L ) pr_loglevel=$OPTARG ;;
		x ) pr_xdb=$OPTARG ;;
		* ) pr_help ; exit 1 ;;
	esac
done

# Take whatever action we've been told to take
case ${pr_action} in
	"start" )
		echo "Attempting to start a pr-server..."
		pr_start
		;;
	"stop" )
		echo "Attempting to kill a running pr-server..."
		pr_stop
		;;
	"import" )
		echo "Attempting to import pr-server database dump ${pr_xdb} into ${pr_db}"
		pr_import
		;;
	"export" )
		echo "Attempting to export pr-server database ${pr_db} to ${pr_xdb}"
		pr_export
		;;
	"restart" )
		echo "Attempting to export pr-server database ${pr_db} to ${pr_xdb}"
		pr_restart
		;;
	* ) echo "Invalid action specified: ${pr_action}" ; pr_help ; exit 1 ;;
esac
exit 0
