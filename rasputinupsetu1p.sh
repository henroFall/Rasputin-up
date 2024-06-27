#!/bin/bash

echo "Starting setup script..."

# Warn the user about the upcoming reboot
echo "This script will reboot your system at the end."
echo "Press any key to continue or CTRL+C to abort."
read -n 1 -s

# Step 0: Clean up prior runs
echo "Cleaning up prior installations of More Ram and log2ram..."

# Stop and disable More Ram service if it exists
if systemctl is-active --quiet more-ram; then
    echo "Stopping and disabling More Ram service..."
    sudo systemctl stop more-ram
    sudo systemctl disable more-ram
fi

# Uninstall More Ram if the uninstall script exists
if [ -f "/opt/More RAM/uninstall" ]; then
    echo "Uninstalling More Ram using the provided uninstall script..."
    sudo chmod +x /opt/More\ RAM/uninstall
    sudo bash /opt/More\ RAM/uninstall
elif [ -d "/opt/More RAM" ]; then
    echo "Uninstalling More Ram manually..."
    sudo rm -rf /opt/More\ RAM
    sudo rm -f /usr/local/bin/more-ram
fi

# Stop and disable log2ram service if it exists
if systemctl is-active --quiet log2ram; then
    echo "Stopping and disabling log2ram service..."
    sudo systemctl stop log2ram
    sudo systemctl disable log2ram
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

# Step 1: Install "More Ram" from the botspot/pi-apps github
echo "Installing More Ram from the botspot/pi-apps github..."
mkdir -p /tmp/more_ram_install
cd /tmp/more_ram_install
wget https://raw.githubusercontent.com/Botspot/pi-apps/master/apps/More%20RAM/install
bash install

# Ensure uninstall script is placed in the correct location
echo "Placing More Ram uninstall script in the correct location..."
wget https://raw.githubusercontent.com/Botspot/pi-apps/master/apps/More%20RAM/uninstall -O /opt/More\ RAM/uninstall
chmod +x /opt/More\ RAM/uninstall

# Enable More Ram service
echo "Enabling More Ram service..."
sudo systemctl enable more-ram

# Step 2: Install log2ram via apt and configure
echo "Adding log2ram repository and installing log2ram via apt..."
echo "deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ bookworm main" | sudo tee /etc/apt/sources.list.d/azlux.list
sudo wget -O /usr/share/keyrings/azlux-archive-keyring.gpg https://azlux.fr/repo.gpg
sudo apt update
sudo apt install -y log2ram

# Enable log2ram service
echo "Enabling log2ram service..."
sudo systemctl enable log2ram

echo "Configuring log2ram..."
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
