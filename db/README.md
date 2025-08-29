# Database scripts

## MariaDB MyISAM to InnoDB Conversion

This script automates the process of converting MyISAM tables to InnoDB in a MariaDB database. It is designed for cPanel servers and handles backups, schema exports, and service management.

### Features

- Converts MyISAM tables to InnoDB
- Creates database backups
- Exports database schema
- Counts primary keys and indexes
- Supports partial and full conversion modes
- Logs all actions to a file in the user's home directory

### Usage

```bash
./mariadb_convert_myisam_to_innodb.sh [OPTION]
```

#### Options

- `--help`              Show usage information
- `--check-myisam`      List MyISAM tables in the database
- `--count`             Count primary keys and indexes
- `--export-schema`     Dump only the schema of a database
- `--backup`            Only backup a database
- `--partial`           Full backup and convert selected tables
- `--full`              Full backup and convert all MyISAM tables

#### Example

```bash
./mariadb_convert_myisam_to_innodb.sh --full
```

### Notes

- Run as root for system-wide operations; as a cPanel user for user-level operations.
- Backup and log files are created in `/root` (if root) or `/home/[user]`.
- Ensure sufficient disk space for backups.
- Websites using the database will experience downtime during conversion.
