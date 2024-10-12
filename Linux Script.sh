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