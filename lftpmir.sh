#!/bin/bash

###############################
#
# LFTPMir v2 - November 2024
# Uses LFTP to perform multi-threaded transfers from remote server to local filesystem
# Includes basic tuning capabilities with speed measurement
#
###############################

USERNAME="[username]"
KEY_FILE="[/path/to/public/key]" # Preferred; the pre-shared key file for SSH authentication; this or PASSWORD must be specified
PASSWORD= # The password for SSH authentication; this or KEY_FILE must be specified 
REMOTE_SERVER="[FQDN of remote server]"
CIPHER="aes128-ctr" # Cipher used by SSH for transfer; leave blank to use SSH default if -e isn't specified
THREADS=28 # Number of transfer threads to use by default if -n isn't specified
LOG_FILE="[path to log file]"

# Display usage guide on unusable input
usage() { 
    echo "Usage: lftpmir [-c|-m] [-n num_threads; default 20] [-e encryption_cipher] [Remote Source] [Local Destination]"; echo; exit 1 
}

# Helper function to calculate the MiB/s of the transfer
calc_mibs() {
    local duration="$1"
    local size=
    local mibs=
    size="$(du -s -BM "${mirror_dir}"/.lftptmp)"
    size="${size%%M*}"
    mibs="$(( size / duration ))"

    echo "Transfer of ${size}MiB completed in $(date -d@"${duration}" -u +%H:%M:%S). Average speed ${mibs}MiB/s."
}

# Main LFTP command; downloads to temprary dir, calculates average speed, then moves to specified destination
# Dumps output of set -x on error
lftpmir() {
    exec 3>> "${LOG_FILE}"
    BASH_XTRACEFD=3
    set -ex
    mkdir -p "${mirror_dir}/.lftptmp"
    SECONDS=0
    lftp -c "set ssl:verify-certificate no; \
        set sftp:auto-confirm yes; \
        set sftp:connect-program 'ssh -v -a -x ${encryption_cipher}${id_file}'; \
        open sftp://${credentials}@${REMOTE_SERVER}; \
        mirror -c --use-pget-n=${num_threads} --verbose=3 ${move_switch}--no-perms --only-missing \
        '${source_dir}' '${mirror_dir}/.lftptmp'; \
        bye" 2>&1 | tee -a "${LOG_FILE}"
    duration=$SECONDS
    calc_mibs "${duration}" 2>&1 | tee -a "${LOG_FILE}"
    mv "${mirror_dir}/.lftptmp/"* "${mirror_dir}" | tee -a "${LOG_FILE}"
    rmdir "${mirror_dir}/.lftptmp" | tee -a "${LOG_FILE}"
    set +ex
    BASH_XTRACEFD=2
    exec 3>&-
}

# Ensure a password or key file was specified, then use it
if [[ -n "${KEY_FILE}" ]]; then
    id_file="-i ${KEY_FILE}"
    credentials="${USERNAME}:"
elif [[ -n "${PASSWORD}" ]]; then
    id_file=
    credentials="${USERNAME}:${PASSWORD}"
else
    echo "[ERROR] - Pre-shared key path or password must be specified in script file."; exit 1
fi

copy=false
move=false
declare -i num_threads
num_threads="${THREADS}"
encryption_cipher=
move_switch=

# Create commandline options for copy, move, and an optional specification for number of transfer threads
while getopts ":cmn:e:" option; do
    case $option in
        c) copy=true ;;
        m) move=true ;;
        n) num_threads="$OPTARG" ;;
        e) encryption_cipher="$OPTARG" ;;
        :) echo "-n requires an integer for thread count."; usage ;;
        *) usage ;;
    esac
done

# Get source and destination directories from user input
shift "$((OPTIND - 1))"
source_dir="$1"
mirror_dir="$2"

# Check if a cipher was specified and add its switch to the LFTP command if so
if [[ -z "${encryption_cipher}" && -n "${CIPHER}" ]]; then
    encryption_cipher="-c ${CIPHER} "
elif [[ -n "${encryption_cipher}" ]]; then
    encryption_cipher="-c ${encryption_cipher} "
fi   

# Remove trailing slash in destination dir if it exists
if [[ "${mirror_dir}" == */ ]]; then
    mirror_dir="${mirror_dir%/}"
fi

# Clear the log before beginning
cat /dev/null > "${LOG_FILE}"

# Main script body
if [[ -z "${source_dir}" || -z "${mirror_dir}" ]] ; then
    echo "Missing source or destination directory."
    usage
elif [[ $copy = true && $move = true ]] ; then
    echo "-c Copy and -m Move cannot be used simultaneously."
    usage
elif [[ $copy = false && $move = false ]] ; then
    echo "Either -c Copy or -m Move must be used."
    usage
elif [[ $copy = true ]] ; then
    lftpmir
elif [[ $move = true ]] ; then
    move_switch="--Move "
    lftpmir
fi
