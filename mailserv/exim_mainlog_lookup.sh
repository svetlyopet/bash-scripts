#!/bin/bash

################################################################
# Interactive script to analyze Exim mail log and provide      # 
# some statistics.                                             #
#                                                              #
# Useful when looking for malicious activity and compromised   #
# email accounts.                                              #
#                                                              # 
# Author: Svetoslav Petrov                                     #
################################################################

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;36m'
nc='\033[0m'

menu () {
	echo -e  "${green}Type of checks that can be performed:${nc}"
	echo ""
	echo "1. Subject check - most repetitive Subjects"
	echo "2. Most senders using dovecot_login SMTP auth"
	echo "3. Most senders using dovecot_plain SMTP auth"
	echo "4. Sending IP addresses for a specific email account"
	echo "5. Most outbound connections"
	echo "6. Most mail delivery failure notifications"
	echo "10. Exit script"
	echo ""
	echo -e "${green}Enter your choice:${nc}"
	read input_num
	while [ ${input_num} != 10 ] ; do
		case $input_num in
			1)
				subject_check
				;;
			2)
				login_check
				;;
			3)
				plain_check
				;;
			4)
				sender_check
				;;
			5)
				sent_mails
				;;
			6)
				delivery_failure
				;;
			10)
				echo -e "${green}Exiting script...${nc}"
				exit
				;;
			*)	
				echo -e "${red}Invalid option. Ty again:${nc}"
				read input_num
				;;
		esac
	done
	exit
	}

return_menu() {
	echo ""
	echo -e "${green}Return to menu[1] or exit script[2]?:${nc}"
        read choice
	while [[ ${choice} != 1 && ${choice} != 2 ]] ; do
                echo -e "${red}Invalid choice. Try again:${nc}"
                read choice
	done
	if [ ${choice} == 1 ] ; then
		menu
	elif [ ${choice} == 2 ] ; then
		exit
	fi	      
	}

subject_check () {
	echo -e "${blue}The 10 most sent subjects:${nc}"
	subj=$(awk -F"T=\"" '/<=/ {print $2}' ${exim_mainlog} | cut -d\" -f1 | sort | uniq -c | sort -n | tail -n 10 | tac)
	printf '%s\n' "${subj[@]}"
	return_menu
	}
	
login_check () {
	echo -e "${blue}The 10 most active accounts with dovecot_login:${nc}"
	sendaddr_login=$(cat ${exim_mainlog} | grep "_login" | sed -n 's/.*_login:\(.*\)S=.*/\1/p' | sort | uniq -c | sort -nr -k1 | head -n 10)
	printf '%s\n' "${sendaddr_login[@]}"
	return_menu
	}

plain_check () {
	echo -e "${blue}The 10 most active accounts with dovecot_plain:${nc}"
	sendaddr_plain=$(cat ${exim_mainlog} | grep "_plain" | sed -n 's/.*_plain:\(.*\)S=.*/\1/p' | sort | uniq -c | sort -nr -k1 | head -n 10)
	printf '%s\n' "${sendaddr_plain[@]}"
	return_menu
	}

sender_check () {
	echo -e "${blue}Please enter email account:${nc}"
	read addr
	result=$(grep "${addr}" ${exim_mainlog} | grep -e " <= " -e " T=" | grep -o "\[[0-9.]*\]" | sort -n | uniq -c | sort -n )
	printf '%s\n' "${result[@]}"
	return_menu
	}

sent_mails () {
	echo -e "${blue}Most emails sent by:${nc}"
	sndr=$(grep @ ${exim_mainlog} | grep "U=" | grep -v "P=local" | awk '{ print $6" "$7" "$8 }' | sort | uniq -c | sort -nr -k1 | head -n 10)
	printf '%s\n' "${sndr[@]}"
	echo ""
	echo -e  "${blue}Checking number of unique IP addresses for the top 10 senders...${nc}"
	for addr in $(printf '%s\n' "${sndr[@]}" | awk '{ print $4 }' | cut -d= -f 2)
	do
		diffaddr=$(grep ${addr} ${exim_mainlog} | grep "<= " | grep -v " <> " | cut -d " " -f 1-11 | sed 's/.*\[\([^]]*\)\].*/\1/g' | sort | uniq | wc -l)	
		printf '%s%s\n' "Account ${addr} has sent mail from ${diffaddr[@]} different IP addresses"
	done
	return_menu
	}

delivery_failure () {
	echo -e "${blue}Most email accounts that received Mail delivery failure notices:${nc}"
	deliv_fail=$(grep "Mail delivery failed: returning message to sender" ${exim_mainlog} | awk '{ print $18 }' | sort | uniq -c | sort -n | tail -n 10 | tac)
	printf '%s\n' "${deliv_fail[@]}"
	return_menu
	}

echo ""
echo "Enter path to exim_mainlog:"
read exim_mainlog

if [ ! -f ${exim_mainlog} ] ; then
		echo ""
        echo "File ${exim_mainlog} not found."
		echo "Exiting script..."
        exit 1
fi

echo ""

menu
exit
