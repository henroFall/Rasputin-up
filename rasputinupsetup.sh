#!/bin/bash

TARGET_SIZE=400000 # Target size in KB
LOG_DIR="/var/log"

echo "Starting setup script..."

# Initial warning and instructions
echo "WARNING: This script will shrink the log directory to under 400 MB by identifying and purging the largest log files."
echo "All current logs will be configured to roll over every 7 days. Note that any new applications you install later will need to be manually configured to use logrotate."
echo "Refer to this article for more information on how to use the logrotate.d folder: https://linuxhandbook.com/logrotate/"
echo "Press any key to continue or CTRL+C to abort."
read -n 1 -s

# Step 0: Clean up prior runs
echo "Cleaning up prior installations of More Ram and log2ram..."

# Stop and disable More Ram service if it exists
if systemctl is-active --quiet more-ram.service; then
    echo "Stopping and disabling More Ram service..."
    sudo systemctl stop more-ram.service
    sudo systemctl disable more-ram.service
fi

# Uninstall More Ram if the uninstall script exists
if [ -f "/opt/More_RAM/uninstall" ]; then
    echo "Uninstalling More Ram using the provided uninstall script..."
    sudo chmod +x /opt/More_RAM/uninstall
    sudo bash /opt/More_RAM/uninstall
elif [ -d "/opt/More_RAM" ]; then
    echo "Uninstalling More Ram manually..."
    sudo rm -rf /opt/More_RAM
    sudo rm -f /usr/local/bin/more-ram
fi

# Stop and disable log2ram service if it exists
if systemctl is-active --quiet log2ram.service; then
    echo "Stopping and disabling log2ram service..."
    sudo systemctl stop log2ram.service
    sudo systemctl disable log2ram.service
fi

# Uninstall log2ram
if dpkg -l | grep -q log2ram; then
    echo "Uninstalling log2ram..."
    sudo apt remove -y log2ram
fi

# Remove leftover temporary directories
echo "Removing leftover temporary directories..."
rm -rf /tmp/more_ram_install

# Step 0: Vacuum journalctl down to 64MB
echo -n "Vacuuming journalctl logs down to 64MB..."
sudo journalctl --vacuum-size=64M > /dev/null
echo " Done."

# Step 0: Create logrotate configuration for syslog
echo "Creating logrotate configuration for syslog..."
sudo bash -c 'cat <<EOL > /etc/logrotate.d/syslog
/var/log/syslog {
    daily
    rotate 7
    missingok
    notifempty
    delaycompress
    compress
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
EOL'

# Step 0: Update logrotate configurations for Zabbix components
echo "Updating logrotate configurations for Zabbix components..."
for service in zabbix-agent2 zabbix-proxy zabbix-proxy-psql zabbix-agent; do
    if [ -f /etc/logrotate.d/$service ]; then
        sudo sed -i 's/rotate [0-9]*/rotate 14/' /etc/logrotate.d/$service
        sudo sed -i 's/daily/daily/' /etc/logrotate.d/$service
    fi
done

# Calculate the total size of the log directory
get_log_size() {
    du -sk $LOG_DIR | cut -f1
}

# Find the largest log files
find_largest_logs() {
    find $LOG_DIR -type f -exec du -k {} + | sort -rn | head -n 10
}

# Purge a log file
purge_log() {
    local log_file=$1
    echo "Purging log file: $log_file"
    : > "$log_file"
}

# Setup logrotate configuration for a directory
setup_logrotate() {
    local log_dir=$1
    local logrotate_conf="/etc/logrotate.d/$(basename "$log_dir")"
    echo "Setting up logrotate for $log_dir"
    sudo bash -c "cat <<EOL > $logrotate_conf
$log_dir/*.log {
    weekly
    rotate 4
    missingok
    notifempty
    compress
    delaycompress
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate > /dev/null 2>&1 || true
    endscript
}
EOL"
}

# Main logic to clean up and configure log rotation
log_cleanup() {
    current_size=$(get_log_size)
    
    echo "Current log directory size: $current_size KB"

    if [ $current_size -le $TARGET_SIZE ]; then
        echo "Log directory is already under the target size of 400 MB."
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

log_cleanup

# Step 1: Install "More RAM" from the botspot/pi-apps github
echo "Installing More RAM from the botspot/pi-apps github..."
mkdir -p /tmp/more_ram_install
cd /tmp/more_ram_install
wget https://raw.githubusercontent.com/Botspot/pi-apps/master/apps/More%20RAM/install
bash install

# Ensure uninstall script is placed in the correct location
echo "Placing More RAM uninstall script in the correct location..."
wget https://raw.githubusercontent.com/Botspot/pi-apps/master/apps/More%20RAM/uninstall -O /opt/More_RAM/uninstall
chmod +x /opt/More_RAM/uninstall

# Enable More RAM service
echo "Enabling More RAM service..."
sudo systemctl enable more-ram.service

# Step 2: Install log2ram via apt and configure
echo "Adding log2ram repository and installing log2ram via apt..."
echo "deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ bookworm main" | sudo tee /etc/apt/sources.list.d/azlux.list
sudo wget -O /usr/share/keyrings/azlux-archive-keyring.gpg https://azlux.fr/repo.gpg
sudo apt update
sudo apt install -y log2ram

echo "Configuring log2ram options..."
sudo sed -i 's/SIZE=.*$/SIZE=512M/' /etc/log2ram.conf
sudo sed -i 's/MAIL=.*$/MAIL=false/' /etc/log2ram.conf
sudo sed -i 's/LOG_DISK_SIZE=.*$/LOG_DISK_SIZE=2048/' /etc/log2ram.conf

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

# Reboot the system
sudo reboot

# Inform the user to check log2ram status after reboot
echo "After the reboot, you can check the status of log2ram by running 'systemctl status log2ram'."
