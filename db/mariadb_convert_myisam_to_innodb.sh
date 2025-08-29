#!/bin/bash

################################################################
# Convert MyISAM tables in a MariaDB database to InnoDB.       #
#                                                              #
# Used for cPanel servers with MariaDB installed.              #
#                                                              #
# Will create a backup and a log file in the home folder of    #
# the cPanel user or /root if ran as root.                     #
#                                                              #
# Planning downtime for websites using the database is         #
# required as the script will stop Apache and kill all         #
# php-cgi processes.                                           #
#                                                              #
# Running as non-root user will require database               #
# credentials.                                                 #
#                                                              #  
# Author: Svetoslav Petrov                                     #
################################################################

# support functions

# this script is using two log functions - for silent logging and log&output to console
function logMsg () {
    read in
    echo -e "[$(date +"%d.%m.%Y %T")] $in" >> $general_log
    echo -e $in
}

function log () {
    echo "[$(date +"%d.%m.%Y %T")] $1" >> $general_log
}

# see if we are running as root or a cPanel user and set paths accordingly
function initialize() {
if (( $EUID == 0 ))
then
    user="$(whoami)"
    user_home="/${user}"
    general_log="${user_home}/sh_mysql_convert_log"
    log "Running this script as root."
    echo -e "Running this script as ${green}root${nc} !"
    echo -e "Please note the backup and log file will be created in the ${green}/root${nc} directory!"
    echo -e "Creating log file in ${green}${general_log}${nc}"
else
    user="$(whoami)"
    user_home="/home/${user}"
    general_log="${user_home}/sh_mysql_convert_log"
    echo -e "Running this script as user ${user}." | logMsg
    echo -e "Creating log file in ${green}${general_log}${nc}"
fi
}

function show_help() {
    echo -e "Automated script to convert tables from using MyISAM to InnoDB"
    echo -e "Creates a backup and a log file in the home folder of the cPanel"
    echo -e "user or /root directory if ran as root"
    echo 
    echo -e "Options:"
    echo -e "   --help                Shows this information"
    echo -e "   --check-myisam        Lists MyISAM tables in the database"
    echo -e "   --count               Counts primary keys and indexes"
    echo -e "   --export-schema       Dumps only the schema of a database"
    echo -e "   --backup              Only backup a database"
    echo -e "   --partial             Performs a full backup and converts only certain tables"
    echo -e "   --full                Performs a full backup and converts all MyISAM tables to InnoDB"
    echo
    echo -e "Example usage:"
    echo -e "./convert_myisam_to_innodb.sh --full"
    exit 0
}

# main functions

function get_db_info() {
    echo "Enter database name:"
    echo
    read db_name
    log "Working on database: ${db_name}"
    if (( $EUID == 0 ))
    then 
        mysql_command="mysql -u${user}"
    else
        echo "Enter user for database ${db_name}:"
        read db_user
        echo "Enter password for user ${db_user}:"
        read db_pass
        mysql_command="mysql -u${db_user} -p${db_pass}" 
    fi
}

function check_myisam() {
    echo "Permorming MyISAM check..." | logMsg
    tables=$(echo "SELECT TABLE_NAME FROM information_schema.tables WHERE \`TABLE_SCHEMA\` = '${db_name}' and ENGINE = 'MyISAM'" | ${mysql_command} | egrep -vi 'table_name')

    if [ -z "${tables}" ]
    then
        echo "No MyISAM tables found in ${db_name} database. Exiting script" | logMsg
        exit 0
    fi

    if [ "$mode" == "--check-myisam" ]
    then
        echo "Showing tables using MyISAM. Delimeter is ' , ':"
        echo ${tables} | sed 's/ / , /g'
    fi
    echo "MyISAM check completed" | logMsg      
}

function count() {
    echo "Starting primary key and index count..." | logMsg
    pre_pk_count=$(echo "SELECT COUNT(*) FROM information_schema.table_constraints WHERE \`constraint_schema\` = '${db_name}'" | ${mysql_command} | grep -vi 'count')
    echo "Primary key count: $pre_pk_count" | logMsg
    pre_indx_count=$(echo "SELECT count(*) FROM information_schema.statistics WHERE \`TABLE_SCHEMA\` = '${db_name}'" | ${mysql_command} | grep -vi 'count')
    echo "Index count: $pre_indx_count" | logMsg
}

function export_schema() {
    echo "Dumping schema to ${db_name}-schema..." | logMsg
    if (( $EUID == 0 ))
    then 
        mysqldump -u${user} ${db_name} --no-data > ${user_home}/${db_name}-schema
    else
        mysqldump -u${db_user} -p${db_pass} ${db_name} --no-data > ${user_home}/${db_name}-schema
    fi
    echo "Schema dumped successfully." | logMsg
}

function get_tables() {
    echo "Please insert names of tables you want to convert"
    echo -e "${green}Devide every table with a comma, example:${nc}"
    echo "wp_options,wp_postmeta,wp_posts,..."
    read part_tables
    tables=$(echo ${part_tables} | sed 's/,/\n/g')
}

function pre_conv () {
    if (( $EUID == 0 ))
    then
        echo "Stoping httpd service..." | logMsg
        /scripts/restartsrv_httpd stop > /dev/null 2>&1;
        echo "httpd service is now stopped" | logMsg
        echo "Restarting mysql service..." | logMsg
        /scripts/restartsrv_mysql
        log "mysql restarted successfully"
    fi
    echo "Killing php-cgi proccesses..." | logMsg
    pkill -9 php-cgi
    echo "All php-cgi processes were killed" | logMsg
}

function post_conv() {
    if (( $EUID == 0 ))
    then
        echo "Restarting mysql service..." | logMsg
        /scripts/restartsrv_mysql
        log "mysql restarted successfully"
        echo "Starting httpd service..." | logMsg
        /scripts/restartsrv_httpd start > /dev/null 2>&1
        log "httpd started successfully"
        echo "Checking Apache status..." | logMsg
        httpd_status=$(curl -I "http://${host_serv}" | head -n 1 | awk '{print $2}')
        log "Apache is returning HTTP status ${httpd_status} after httpd restart."
	if [ ${httpd_status} != "200" ]
        then
            echo -e "Apache is returning HTTP status ${red}${httpd_status}${nc} after httpd restart!" 
	    echo "Please check if there is issues with Apache"
        else
            echo -e "Apache is returning HTTP status ${green}${httpd_status}${nc}."
            echo "Convert complete! Exiting script..." | logMsg
            exit 0
        fi
    fi
}

function gen_backup() {
    echo "Generating backup of database ${db_name}..." | logMsg
    tstamp="$(date +%d-%m-%Y_%H-%M)"
    if (( $EUID == 0 ))
    then
        db_dump="$( ( mysqldump -u${user} $db_name > ${user_home}/${db_name}-${tstamp}.sql ) 2>&1 )"
    else
        db_dump="$( ( mysqldump -u${db_user} -p${db_pass} $db_name > ${user_home}/${db_name}-${tstamp}.sql ) 2>&1 )"
    fi
    if [ -z "${db_dump}" ]
    then
        echo "mysqldump completed successfully without any errors" | logMsg
        echo "backup is located at ${user_home}/${db_name}-${tstamp}.sql" | logMsg
    else
	echo "mysqldump was not successfull!" | logMsg
    	echo ${db_dump} | logMsg
	echo "Exiting script..." | logMsg
	exit 1
    fi
}

function start_convert() {
    echo "Starting conversion..." | logMsg
    for table in ${tables} ; do
	log "Converting MyISAM ${table} to InnoDB..."
	exec_query="$( ( echo "ALTER TABLE \`${table}\` ENGINE = InnoDB" | ${mysql_command} ${db_name} ) 2>&1 )"
	if [ -z "${exec_query}" ]
	then
		log "Table ${table} converted successfully"
	else
		echo "error when trying to convert table ${table}." | logMsg
		echo "${exec_query}" | logMsg
		echo "Please check ${general_log} for details about the conversion"
		echo -e "${red}Apache${nc} is not started automatically by this script in event of failure !"
		echo "Don't forget to start it with after recovering the database from back up !"
		echo "Exiting this script..." | logMsg
		exit 2
	fi
    done
    echo -e "${green}All tables were converted successfully! Starting post conversion checks...${nc}"
    
    # count primary keys and indexes after conversion
    post_pk_count=$(echo "SELECT COUNT(*) FROM information_schema.table_constraints WHERE \`constraint_schema\` = '${db_name}'" | ${mysql_command} | grep -vi 'count')
    echo "Primary key count after conversion: $post_pk_count" | logMsg
    post_indx_count=$(echo "SELECT count(*) FROM information_schema.statistics WHERE \`TABLE_SCHEMA\` = '${db_name}'" | ${mysql_command} | grep -vi 'count')
    echo "Index count after conversion: $post_indx_count" | logMsg

    if [ "${pre_pk_count}" != "${post_pk_count}" ] || [ "${pre_indx_count}" != "${post_indx_count}" ]
    then
	    echo -e "${red}Private keys or Indexes do not match! Restore ${db_name} from the generated backup.${nc}"
            echo "Backup is located at ${user_home}/${db_name}-${tstamp}.sql"
    else
	    echo -e "${green}Primary keys and index count match after conversion.${nc}"
    fi
}

if  [ "$#" -ne 1 ]
then
    echo "Usage: ./convert_myisam_to_innodb.sh [OPTION]"
    echo "Try './convert_myisam_to_innodb.sh --help' for more information."
    exit 0
fi
host_serv="$(hostname)"
mode="$1"

red='\033[0;31m'
green='\033[0;32m'
nc='\033[0m'

initialize

case "$mode" in
	--backup)
		get_db_info
		gen_backup
		;;
	--export-schema)
		get_db_info
		export_schema
		;;
	--check-myisam)
		get_db_info
		check_myisam
		;;
	--partial)
		get_db_info
		pre_conv
		gen_backup
		count
		get_tables
		start_convert
		post_conv
		;;
	--full)
		get_db_info
		pre_conv
		gen_backup
		count
		check_myisam
		start_convert
		post_conv
		;;
	--count)
		get_db_info
		count
		;;
	--help)
		show_help
		;;
	*)
		show_help
esac
