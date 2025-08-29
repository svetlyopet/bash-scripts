# Mail server scripts

## Exim mainlog lookup

This script analyzes an Exim mainlog and provides useful statistics to help identify suspicious or malicious email activity.

### Features

- Lists most repetitive email subjects
- Shows most active senders using dovecot_login and dovecot_plain SMTP authentication
- Displays sending IP addresses for a specific email account
- Reports most outbound connections
- Identifies accounts with the most mail delivery failure notifications

### Usage

1. Run the script:
   ```bash
   ./exim_mainlog_lookup.sh
   ```

2. When prompted, enter the path to your `exim_mainlog` file.

3. Choose the desired check from the menu.

### Notes

- Requires read access to the Exim log file.
- Useful for mail server administrators investigating compromised accounts or spam activity.
