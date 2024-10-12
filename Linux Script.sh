#!/bin/bash

# check if augeas is installed; if not, install it
if ! command -v augtool &> /dev/null; then
    echo "Augeas is not installed. Installing it now..."
    sudo apt-get update
    sudo apt-get install -y augeas-tools
fi

# set variables for password policy
MAX_DAYS=30
MIN_LEN=8
MIN_DAYS=0
WARN_DAYS=7

# update /etc/login.defs for password aging
augtool -s <<EOF
set /files/etc/login.defs/UMASK 077
set /files/etc/login.defs/PASS_MAX_DAYS $MAX_DAYS
set /files/etc/login.defs/PASS_MIN_LEN $MIN_LEN
set /files/etc/login.defs/PASS_MIN_DAYS $MIN_DAYS
set /files/etc/login.defs/PASS_WARN_AGE $WARN_DAYS
EOF

# update PAM configuration
PAM_CONFIG="/etc/pam.d/common-password"

if grep -q 'pam_unix.so' "$PAM_CONFIG"; then
    augtool -s <<EOF
    set /files$PAM_CONFIG/pam_unix.so/remember 5
    set /files$PAM_CONFIG/pam_unix.so/minlen $MIN_LEN
    set /files$PAM_CONFIG/pam_unix.so/sha512 1
EOF
fi

echo "Password policies updated successfully."

# function to manage regular users
manage_users() {
    echo "Managing Regular Users"
    for user in $(getent passwd | awk -F: '{print $1}' | grep -vE '^(root|nobody|systemd-timesync)$'); do
        read -p "Is $user meant to be a user? (Y/N): " response
        case "$response" in
            [Yy]* ) 
                echo "$user remains a user."
                ;;
            [Nn]* ) 
                echo "Deleting user $user..."
                sudo deluser --remove-home "$user"
                ;;
            * ) 
                echo "Invalid response. Please type 'Y' or 'N'."
                ;;
        esac
    done
}

# function to manage administrators
manage_admins() {
    echo "Managing Admin Privileges"
    
    # get all regular users excluding system users
    for user in $(getent passwd | awk -F: '{print $1}' | grep -vE '^(root|nobody|systemd-timesync)$'); do
        # check if the user is an admin
        if id "$user" &>/dev/null && id -nG "$user" | grep -qw "sudo"; then
            admin_status="an administrator"
        else
            admin_status="a regular user"
        fi
        
        # ask if the user should remain
        read -p "Is $user meant to be $admin_status? (Y/N): " response
        case "$response" in
            [Yy]* ) 
                echo "$user remains $admin_status."
                ;;
            [Nn]* ) 
                # If the user is an admin, remove privileges
                if [[ $admin_status == "an administrator" ]]; then
                    echo "Removing admin privileges from $user..."
                    sudo deluser "$user" sudo
                else
                    echo "$user remains a regular user."
                fi
                ;;
            * ) 
                echo "Invalid response. Please type 'Y' or 'N'."
                ;;
        esac

        # if the user is not an admin, ask if they should be granted admin privileges
        if [[ $admin_status == "a regular user" ]]; then
            read -p "Should $user be granted admin privileges? (Y/N): " admin_response
            case "$admin_response" in
                [Yy]* ) 
                    echo "Granting admin privileges to $user..."
                    sudo usermod -aG sudo "$user"
                    ;;
                [Nn]* ) 
                    echo "$user remains a regular user."
                    ;;
                * ) 
                    echo "Invalid response. Please type 'Y' or 'N'."
                    ;;
            esac
        fi
    done
}

# functions execution
manage_users
manage_admins

echo "User management complete."

# define lockout parameters
MAX_FAILED_ATTEMPTS=5
LOCKOUT_TIME=600  # lockout time in seconds (10 minutes)

# backup existing configuration files
sudo cp /etc/pam.d/common-auth /etc/pam.d/common-auth.bak
sudo cp /etc/pam.d/common-account /etc/pam.d/common-account.bak

# configure account lockout in /etc/pam.d/common-auth
echo "Configuring account lockout settings..."
sudo bash -c "echo 'auth required pam_tally2.so onerr=fail deny=$MAX_FAILED_ATTEMPTS even_deny_root' >> /etc/pam.d/common-auth"
sudo bash -c "echo 'auth required pam_tally2.so reset' >> /etc/pam.d/common-auth"

# configure account lockout time in /etc/pam.d/common-account
sudo bash -c "echo 'account required pam_tally2.so' >> /etc/pam.d/common-account"
sudo bash -c "echo 'account required pam_tally2.so deny=$MAX_FAILED_ATTEMPTS even_deny_root unlock_time=$LOCKOUT_TIME' >> /etc/pam.d/common-account"

echo "Account lockout settings configured. Users will be locked out after $MAX_FAILED_ATTEMPTS failed login attempts for $LOCKOUT_TIME seconds."
