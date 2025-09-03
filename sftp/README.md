# SFTP Backup Script

⚠️ Authentication with SFTP is required, so credentials will need to be either hardcoded in the script, or a local unecrypted SSH private kay needs to be present on the host. Use with caution even in trusted environments.

This script backs up a local directory to a remote server using SFTP. It supports both password and key-based authentication and is suitable for use as in cronjob.

## Requirements

- `sftp` (OpenSSH client)
- `sshpass` (for password authentication, optional)

## Configuration

Edit the following variables in the script before running:

- `sftp_user` – SFTP username
- `sftp_pass` – SFTP password (leave empty if using key)
- `sftp_key` – Path to private key file (leave empty if using password)
- `proxy_command` – SSH proxy command (optional)

## Usage

```bash
./sftp_backup.sh --local-dir=/path/to/source --sftp-host=example.com --remote-dir=/path/to/remote/dir
```

### Optional arguments

- `--sftp-port=PORT` – SFTP server port (default: 22)
- `--log-file=PATH` – Log file path (default: /var/log/sftp_backup.log)
- `--debug=MODE` – Debug mode (0=none, 1=basic, 2=verbose)
- `--help` – Show usage information

## Notes

- Do not pass sensitive credentials via command line; set them in the script.
- The script logs all operations to the specified log file.
- Only regular files in the local directory are uploaded.

For more details, see comments in the script.