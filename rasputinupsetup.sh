#!/bin/bash


# I am ROOT?
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

is_number() {
    [[ $1 =~ ^[0-9]+$ ]]
}

LOG_DIR="/var/log"
# Get the total amount of RAM in MB
total_ram=$(free -m | awk '/^Mem:/{print $2}')
# Determine the appropriate SIZE value based on the total RAM
if [ "$total_ram" -ge 8192 ]; then
    size_value="512"
elif [ "$total_ram" -ge 4096 ]; then
    size_value="384"
else
    size_value="256"
fi
echo "Welcome to the Rasputin-up setup script."
echo "----------------------------------------"
echo
echo "For the installation, we need to temporarily shrink the log directory size down to $TARGET_SIZE MB"
echo "This is the amount of space in RAM that Log2Ram will occoupy. Do not worry," 
echo "after the installation, the log directory will be allowed to grow to well over 5GB if necessary."
echo "Log2Ram will handle compressing the contents in RAM."
echo "All current logs will be configured to roll over every 7 days. Note that any new applications"
echo "you install later will need to be manually configured to use logrotate."
echo "Refer to this article for more information on how to use the logrotate.d folder: https://linuxhandbook.com/logrotate/"
echo
echo "If you played with an earlier version of this and now I've added something new, the installer is going to remain defensive"
echo "against anything leftover from prior installs, and clean up accordingly. If you run it twice by accident, it won't hurt, either."
echo
echo "I haven't done anything yet. When you are done reading, press any key to continue or CTRL+C to abort."
read -n 1 -s

TARGET_SIZE=$((TARGET_SIZE * 1024))

# Clean up any prior runs
echo "Cleaning up prior installations of More Ram and log2ram..."

if systemctl is-active --quiet more-ram.service; then
    echo "Stopping and disabling More Ram service..."
    systemctl stop more-ram.service
    systemctl disable more-ram.service
fi
echo "Placing More RAM uninstall script in the correct location..."
if [ ! -f "/opt/More_RAM/uninstall" ]; then
    wget https://raw.githubusercontent.com/Botspot/pi-apps/master/apps/More%20RAM/uninstall -O /opt/More_RAM/uninstall
fi
if [ -f "/opt/More_RAM/uninstall" ]; then
    echo "Uninstalling More Ram using the provided uninstall script..."
    chmod +x /opt/More_RAM/uninstall
    bash /opt/More_RAM/uninstall
elif [ -d "/opt/More_RAM" ]; then
    echo "Uninstalling More Ram manually..."
    rm -rf /opt/More_RAM
    rm -f /usr/local/bin/more-ram
fi
if systemctl is-active --quiet log2ram.service; then
    echo "Stopping and disabling log2ram service..."
    systemctl stop log2ram.service
    systemctl disable log2ram.service
fi
if dpkg -l | grep -q log2ram; then
    echo "Uninstalling log2ram..."
    apt remove -y log2ram
fi
echo "Removing leftover temporary directories..."
rm -rf /tmp/more_ram_install

# Vacuum journalctl down to 64MB
echo -n "Vacuuming journalctl logs down to 64MB..."
journalctl --vacuum-size=64M > /dev/null
echo " Done."

# Create logrotate configuration for syslog
echo "Creating logrotate configuration for syslog..."
bash -c 'cat <<EOL > /etc/logrotate.d/syslog
/var/log/syslog {
    daily
    rotate 7
    missingok
    notifempty
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
EOL'

# Update logrotate configurations
# Function to create or update logrotate configuration
configure_logrotate() {
    local log_file=$1
    local logrotate_conf="/etc/logrotate.d/$(basename $log_file .log)"
    
    echo "Configuring logrotate for $log_file..."
    bash -c "cat <<EOL > $logrotate_conf
$log_file {
    daily
    rotate 7
    missingok
    notifempty
    postrotate
        /usr/bin/systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOL"
}
echo "Updating logrotate configurations..."
echo "Configuring logrotate to retain logs for 7 days..."
find /var/log -type f -name "*.log" ! -name "*.gz" ! -name "*.1" ! -name "*.2" ! -name "*.old" ! -name "*.[0-9]*" ! -name "*-[0-9][0-9]*" | while read log_file; do
    configure_logrotate $log_file
done
echo "Logrotate configuration complete. Logs will be retained for 7 days."

#Log dir purge to SIZE variable
# Cleanup functions
get_log_size() {
    du -sk $LOG_DIR | cut -f1
}
find_largest_logs() {
    find $LOG_DIR -type f -exec du -k {} + | sort -rn | head -n 10
}
log_cleanup() {
    current_size=$(get_log_size)
    echo "Current log directory size: $current_size KB"

    if [ $current_size -le $TARGET_SIZE ]; then
        echo "Log directory is already under the target size of $TARGET_SIZE MB."
        return
    fi

    while [ $current_size -gt $TARGET_SIZE ]; do
        largest_logs=$(find_largest_logs)
        while read -r log_entry; do
            log_file=$(echo "$log_entry" | awk '{print $2}')
            log_dir=$(dirname "$log_file")
            purge_log "$log_file"
            setup_logrotate "$log_dir"
            current_size=$(get_log_size)
            echo "Current log directory size after purging: $current_size KB"
            if [ $current_size -le $TARGET_SIZE ]; then
                echo "Log directory size is now under the target size of 400 MB."
                return
            fi
        done <<< "$largest_logs"
    done
}
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.log" -mtime +14 -exec rm -f {} \;
log_cleanup

# Install "More RAM" from the botspot/pi-apps github
echo "Installing More RAM from the botspot/pi-apps github..."
mkdir -p /tmp/more_ram_install
cd /tmp/more_ram_install
wget https://raw.githubusercontent.com/Botspot/pi-apps/master/apps/More%20RAM/install
bash install

# Ensure uninstall script is placed in the correct location
wget https://raw.githubusercontent.com/Botspot/pi-apps/master/apps/More%20RAM/uninstall -O /opt/More_RAM/uninstall
chmod +x /opt/More_RAM/uninstall

# Install log2ram via apt and configure
echo "Adding log2ram repository and installing log2ram via apt..."
echo "deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ bookworm main" | tee /etc/apt/sources.list.d/azlux.list
wget -O /usr/share/keyrings/azlux-archive-keyring.gpg https://azlux.fr/repo.gpg
apt update
apt install -y log2ram

echo "Configuring log2ram options..."
sed -i "s/SIZE=.*$/SIZE=$size_value/" /etc/log2ram.conf
sed -i 's/MAIL=.*$/MAIL=false/' /etc/log2ram.conf
sed -i 's/LOG_DISK_SIZE=.*$/LOG_DISK_SIZE=2048/' /etc/log2ram.conf
echo "Updated /etc/log2ram.conf with SIZE=$size_value based on total RAM of $total_ram MB."

# Clean up
echo "Cleaning up..."
cd ~
rm -rf /tmp/more_ram_install

# Inform the user about the reboot
echo "Setup script completed successfully. The system will now reboot in 10 seconds. Press CTRL+C to abort."
for i in $(seq 10 -1 1); do
    echo -ne "\rRebooting in $i seconds..."
    sleep 1
done

# Inform the user to check log2ram status after reboot
echo "After the reboot, you can check the status of log2ram by running 'systemctl status log2ram'."

# Reboot the system
reboot