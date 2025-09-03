#!/bin/bash

###################################################################
# Poor man's script to backup local directory to remote server    #
# using SFTP. Expected to be ran as a cronjob.                    #
#                                                                 #
# It supports both password and key-based authentication.         #
#                                                                 #                                                                 #
# Requires sshpass for password authentication.                   #
#                                                                 #
###################################################################

set -euo pipefail

sftp_bin=$(which sftp || true)
sshpass_bin=$(which sshpass || true)
if [[ -z "$sftp_bin" ]]; then
    echo "Error: sftp command not found. Please install OpenSSH client."
    exit 1
fi
if [[ -z "$sshpass_bin" ]]; then
    echo "Warning: sshpass not found. Password authentication will not work."
fi  

# Configuration variables - edit these in the script
sftp_user=""
sftp_pass=""
sftp_key=""
proxy_command=""

# Default values for optional parameters
sftp_host=""
sftp_port="22"
log_file="/var/log/sftp_backup.log"

# sftp options
sftp_ssh_opts=""

# temp files
sftp_batch_file=$(mktemp /tmp/sftp_backup_batch.XXXXXX)
ssh_custom_config=$(mktemp /tmp/sftp_backup_ssh_config.XXXXXX)

# export SSHPASS for sshpass if password auth is used
export SSHPASS=$sftp_pass

# Print usage information and exit
help() {
    cat << EOF
Usage: $0 --local-dir=PATH --sftp-host=HOST --remote-dir=PATH [options]

Uploads files from local_dir to sftp_host:remote_dir using SFTP.

Required options:
  --local-dir=PATH   Local directory containing files to backup
  --sftp-host=HOST   SFTP server hostname or IP address
  --remote-dir=PATH  Remote directory on the SFTP server

Optional:
  --sftp-port=PORT   SFTP server port (default: $sftp_port)
  --log-file=PATH    Log file to record operations (default: $log_file)
  --debug=MODE       Enable debug mode (0=none, 1=basic, 2=verbose)

Script config(edit script to configure so we don't pass sensitive info via CLI):
  sftp_user   SFTP username (currently: $sftp_user)
  sftp_pass   SFTP password (currently: $sftp_pass)
  sftp_key    Path to private key file (currently: $sftp_key)
  proxy_cmd    Proxy command for SSH (currently: $proxy_command)

Example:
    $0 --host example.com --sftp-user myuser --pass mypass --log /path/to/logfile
EOF
}

# Log to stdout and to log file
log() {
    local level=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" | tee -a "$log_file"
}

# Cleanup temporary files on exit
cleanup() {
    rm -f $sftp_batch_file
    rm -f $ssh_custom_config
}
trap cleanup EXIT

# Parse command line arguments
argparse() {
    local_dir=""
    sftp_host=""
    remote_dir=""
    debug_mode=0 
    for arg in "$@"; do
        case $arg in
            --local-dir=*) local_dir="${arg#*=}"; shift ;;
            --sftp-host=*) sftp_host="${arg#*=}"; shift ;;
            --remote-dir=*) remote_dir="${arg#*=}"; shift ;;
            --sftp-port=*) sftp_port="${arg#*=}"; shift ;;
            --log-file=*) log_file="${arg#*=}"; shift ;;
            --debug=*) debug_mode="${arg#*=}"; shift ;;
            --help) help; exit 0 ;;
            *) echo "Unknown option: $arg"; help; exit 1 ;;
        esac
    done
}

# Select debug mode for sftp
set_sftp_debug_mode() {
    case $debug_mode in
        0) sftp_debug="" ;;
        1) sftp_debug="-v" ;;
        2) sftp_debug="-vvv" ;;
        *) echo "Invalid debug mode: $debug_mode"; exit 1 ;;
    esac
}

# Validate required parameters
validate_params() {
    if [[ -z "$local_dir" || -z "$sftp_host" || -z "$remote_dir" ]]; then
        echo "Error: --local-dir, --sftp-host, and --remote-dir are required."
        help
        exit 1
    fi
    if [[ ! -d "$local_dir" ]]; then
        echo "Error: Local directory $local_dir does not exist or is not a directory."
        exit 1
    fi
    if [[ -z "$sftp_user" ]]; then
        echo "Error: sftp_user is not set in the script."
        exit 1
    fi
    if [[ -z "$sftp_pass" && -z "$sftp_key" ]]; then
        echo "Error: Either sftp_pass or sftp_key must be set in the script."
        exit 1
    fi
    if [[ -n "$sftp_key" && ! -f "$sftp_key" ]]; then
        echo "Error: SFTP key file $sftp_key does not exist."
        exit 1
    fi
}

# Create custom ssh config for proxy command if needed
create_ssh_config() {
    [ $debug -eq 2 ] && log "DEBUG" "Proxy command: $proxy_command"
    [ $debug -eq 2 ] && log "DEBUG" "Creating custom SSH config at $ssh_custom_config"

    cat <<EOF > $ssh_custom_config
Host $sftp_host
    ProxyCommand $proxy_command
EOF
    chmod 600 $ssh_custom_config
    sftp_ssh_opts="-F $ssh_custom_config"

    [ $debug -eq 2 ] && log "DEBUG" "SSH config content:"
    [ $debug -eq 2 ] && cat $ssh_custom_config | while read line; do log "DEBUG" "$line"; done
}

# Create sftp batch file
create_sftp_batch() {
    [ $debug -eq 2 ] && log "DEBUG" "Creating SFTP batch file at $sftp_batch_file"

    for file in "$local_dir"/*; do
        if [[ -f "$file" ]]; then
            log "INFO" "Queueing upload: $file"
            echo "put \"$file\" \"$remote_dir\"" >> $sftp_batch_file
        fi
    done

    if [[ ! -s $sftp_batch_file ]]; then
        log "INFO" "No files to backup."
        exit 0
    fi

    [ $debug -eq 2 ] && log "DEBUG" "SFTP batch file content:"
    [ $debug -eq 2 ] && cat $sftp_batch_file | while read line; do log "DEBUG" "$line"; done
}

main() {
    argparse "$@"
    validate_params
    set_sftp_debug_mode

    if [[ -n "$proxy_command" ]]; then
        create_ssh_config
    fi

    create_sftp_batch

    local sftp_args="-o BatchMode=no $sftp_debug $sftp_ssh_opts -b $sftp_batch_file -P $sftp_port"
    local sftp_command="$sftp_bin $sftp_args"

    if [[ -n "$sftp_key" ]]; then
        sftp_command="$sftp_command -i $sftp_key $sftp_user@$sftp_host"
    else
        if [[ -z "$sshpass_bin" ]]; then
            echo "Error: sshpass is required for password authentication but not found."
            exit 1
        fi
        sftp_command="$sshpass_bin -e $sftp_command $sftp_user@$sftp_host"
    fi

    log "INFO" "Starting SFTP backup to $sftp_user@$sftp_host:$remote_dir"

    set +e 
    $sftp_command 2>&1 | tee -a "$log_file"
    rc=${PIPESTATUS[0]}
    set -e
    if [[ $rc -ne 0 ]]; then
        log "INFO" "SFTP backup completed successfully."
    else
        log "ERROR" "SFTP backup failed."
        exit 1
    fi
}

main "$@"