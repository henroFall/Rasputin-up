#!/bin/bash
VER=0.984

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
echo
echo
echo "Welcome to the Rasputin-up setup script."
echo "----------------------------------------"
echo "Version: $VER"
echo
echo "Why am I doing this? Well, this is something I run on every SBC as I get started. So you're here to do what I do."
echo "Basically, you'll save wear and tear on the SD card and give an overall speed boost to alot of the day-to-day operations."
echo "You're doing this by moving the swap file to a compressed ram disk (translation, small ram footprint, swap when needed to"
echo "compressed RAM vs burning the SD), reconfiguring and moving all of the log files to a RAM disk (which is regularly flushed"
echo "to nonvolitle storage), and also, if a desktop GUI is detected, you can optionally install Tightvnc instead Real."
echo "Why? Because my reasons. Mostly MobaXTerm. - https://mobaxterm.mobatek.net/demo.html"
echo
echo "For the installation, we need to shrink the log directory size down to $size_value MB. This is the amount of space in RAM"
echo "that Log2Ram will occoupy. and how big logs can grow. Log2Ram will handle compressing the contents in RAM, so logs can grow"
echo "through runtime. But, at shutdown, the logs will again be pruned to fit into the alloted space."
echo
echo "All current logs will be configured to roll over every 7 days. Note that any new applications you install later will need to"
echo "be manually configured to use logrotate. A future version will automate this at shutdown."
echo "Refer to this article for more information on how to use the logrotate.d folder: https://linuxhandbook.com/logrotate/"
echo
echo "If you played with an earlier version of this and now I've added something new, the installer is going to remain defensive"
echo "against anything leftover from prior installs, and clean up accordingly. If you run it twice by accident, it won't hurt, either."
echo "You can optionally run with --uninstall to clean up and exit."
echo
echo "I haven't done anything yet. When you are done reading, PRESS:"
echo "  V,             to install tightvncserver if a desktop is present, with no further questions"
echo "  N,             to NOT install tightvnc   if a desktop is present, with no further questions"
echo "  ANY OTHER KEY, to continue and be prompted for VNC install later"
if [[ ! " $@ " =~ " --uninstall " ]]; then
    read -n 1 -s contkey
else
    echo "UNINSTALLING..."
fi
size_valueMB=$size_value
size_value=$((size_value * 1024))

echo "Cleaning up prior installations of More Ram and log2ram..."
if systemctl is-active --quiet zram-swap.service; then
    echo "Stopping and disabling More Ram service..."
    systemctl stop zram-swap.service
    systemctl disable zram-swap.service
fi
if [ -f "/opt/More_RAM/uninstall" ]; then
    echo "Uninstalling More Ram using the provided uninstall script..."
    bash /opt/More_RAM/uninstall
    rm -R /opt/More_RAM/
elif [ ! -d "/opt/More_RAM" ]; then
    echo "More Ram not installed by me, or does not exist."
fi
if systemctl is-active --quiet log2ram.service; then
    echo "Stopping and disabling log2ram service..."
    systemctl stop log2ram.service
    systemctl disable log2ram.service
fi
if dpkg -l | grep -q log2ram; then
    echo "Uninstalling log2ram..."
    apt remove -y log2ram
    echo "Removing conf file."
    rm -f /etc/log2ram.conf
fi
echo "Removing leftover temporary directories..."
rm -rf /tmp/more_ram_install

if [[ " $@ " =~ " --uninstall " ]]; then
    echo "Uninstall flag detected. Exiting now."
    exit 0
fi
#####################################################################
# Vacuum journalctl down to 32MB
echo -n "Vacuuming journalctl logs down to 32MB..."
journalctl --vacuum-size=64M > /dev/null
echo " Done."
sed -i 's/SystemMaxUse=.*$/SystemMaxUse=32M/' /etc/systemd/journald.conf
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
echo "Current SIZE value: $size_valueMB MB."
LOG_DIR="/var/log"

get_log_size() {
    du -sk $LOG_DIR | cut -f1
}

find_largest_logs() {
    find $LOG_DIR -type f -exec du -k {} + | sort -rn | head -n 10
}

purge_log() {
    local log_file=$1
    echo "Purging log file: $log_file"
    rm -f "$log_file"
}

setup_logrotate() {
    local log_dir=$1
    echo "Setting up logrotate for directory: $log_dir"
    # Add your logrotate setup commands here
}

log_cleanup() {
    current_size=$(get_log_size)
    echo "Current log directory size: $current_size KB"
    if [ $current_size -le $size_value ]; then
        echo "Log directory is already under the target size of $size_value MB."
        return
    fi

    while [ $current_size -gt $size_value ]; do
        largest_logs=$(find_largest_logs)
        while read -r log_entry; do
            log_file=$(echo "$log_entry" | awk '{print $2}')
            log_dir=$(dirname "$log_file")
            purge_log "$log_file"
            setup_logrotate "$log_dir"
            current_size=$(get_log_size)
            echo "Current log directory size after purging: $current_size KB"
            if [ $current_size -le $size_value ]; then
                echo "Log directory size is now under the target size of $size_valueMB MB."
                return
            fi
        done <<< "$largest_logs"
    done
}
get_log_size() {
    du -sk $LOG_DIR | cut -f1
}
find_largest_logs() {
    find $LOG_DIR -type f -exec du -k {} + | sort -rn | head -n 10
}
log_cleanup() {
    current_size=$(get_log_size)
    echo "Current log directory size: $current_size KB"
    if [ $current_size -le $size_value ]; then
        echo "Log directory is already under the target size of $size_valueMB MB."
        return
    fi

    while [ $current_size -gt $size_value ]; do
        largest_logs=$(find_largest_logs)
        while read -r log_entry; do
            log_file=$(echo "$log_entry" | awk '{print $2}')
            log_dir=$(dirname "$log_file")
            purge_log "$log_file"
            setup_logrotate "$log_dir"
            current_size=$(get_log_size)
            echo "Current log directory size after purging: $current_size KB"
            if [ $current_size -le $size_value ]; then
                echo "Log directory size is now under the target size of $size_valueMB MB."
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

# Put uninstaller in place
curl -L https://github.com/Botspot/pi-apps/raw/master/apps/More%20RAM/uninstall -o /tmp/uninstall
functions=$(cat <<'EOF'
error() {
  echo -e "\e[91m$1\e[0m" 1>&2
  exit 1
}
status() {
  if [[ "$1" == '-'* ]] && [ ! -z "$2" ]; then
    echo -e $1 "\e[96m$2\e[0m" 1>&2
  else
    echo -e "\e[96m$1\e[0m" 1>&2
  fi
}
status_green() {
  echo -e "\e[92m$1\e[0m" 1>&2
}
set_value() {
  local file="$2"
  [ -z "$file" ] && error "set_value: path to config-file must be specified."
  [ ! -f "$file" ] && error "Config file '$file' does not exist!"
  local setting="$1"
  local setting_without_value="$(echo "$setting" | awk -F= '{print $1}')"
  sudo sed -i "s/^${setting_without_value}=.*/${setting}/g" "$file"
  if ! grep -qxF "$setting" "$file"; then
    echo "$setting" | sudo tee -a "$file" >/dev/null
  fi
}
set_sysctl_value() {
  set_value "$1" /etc/sysctl.conf
  echo "  - $1"
  sudo sysctl "$1" >/dev/null
}
EOF
)
tmp_file="/tmp/uninstall_modified"
echo '#!/bin/bash' > "$tmp_file"
echo "$functions" >> "$tmp_file"
tail -n +2 /tmp/uninstall >> "$tmp_file"
mv -f $tmp_file /opt/More_RAM/uninstall
chmod +x /opt/More_RAM/uninstall

# Install and config log2ram
echo "Adding log2ram repository and installing log2ram via apt..."
echo "deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ bookworm main" | tee /etc/apt/sources.list.d/azlux.list
wget -O /usr/share/keyrings/azlux-archive-keyring.gpg https://azlux.fr/repo.gpg
apt update
PACKAGE_NAME="log2ram"
RETRY_LIMIT=5
RETRY_DELAY=10
attempt=0
while [ $attempt -lt $RETRY_LIMIT ]; do
    echo "Attempt $(($attempt+1)) of $RETRY_LIMIT to install $PACKAGE_NAME"
    apt install -y $PACKAGE_NAME
    
    # Check if the install command was successful
    if [ $? -eq 0 ]; then
        echo "$PACKAGE_NAME installed successfully."
        break
    else
        echo "Error installing $PACKAGE_NAME. Retrying in $RETRY_DELAY seconds..."
        attempt=$(($attempt+1))
        sleep $RETRY_DELAY
    fi
done

if [ $attempt -eq $RETRY_LIMIT ]; then
    echo "Failed to install $PACKAGE_NAME after $RETRY_LIMIT attempts."
    exit 1
else
    echo
fi
if [ ! -f /etc/log2ram.conf ]; then
    echo "Glitch! log2ram.conf does not exist!"
    curl -L https://raw.githubusercontent.com/azlux/log2ram/master/log2ram.conf -o /etc/log2ram.conf
    echo "/etc/log2ram.conf has been downloaded."
else
    echo "/etc/log2ram.conf exists."
fi
echo "Configuring log2ram options..."
sed -i "s/SIZE=.*$/SIZE=${size_valueMB}M/" /etc/log2ram.conf
sed -i 's/MAIL=.*$/MAIL=false/' /etc/log2ram.conf
sed -i 's/LOG_DISK_SIZE=.*$/LOG_DISK_SIZE=2048/' /etc/log2ram.conf
echo "Updated /etc/log2ram.conf with SIZE=$size_valueMB MB based on total RAM of $total_ram MB."

target_script="/etc/log2ramdown.sh"

# Create the script content
cat << 'EOF' > "$target_script"
#!/bin/bash

# Log dir purge to SIZE variable
# Cleanup functions
size_value=$(grep '^SIZE=' /etc/log2ram.conf | sed 's/SIZE=//')
size_valueMB=$((size_value / 1024))

echo "Current SIZE value: $size_valueMB MB."
LOG_DIR="/var/log"

get_log_size() {
    du -sk $LOG_DIR | cut -f1
}

find_largest_logs() {
    find $LOG_DIR -type f -exec du -k {} + | sort -rn | head -n 10
}

purge_log() {
    local log_file=$1
    echo "Purging log file: $log_file"
    rm -f "$log_file"
}

setup_logrotate() {
    local log_dir=$1
    echo "Setting up logrotate for directory: $log_dir"
    # Add your logrotate setup commands here
}

log_cleanup() {
    current_size=$(get_log_size)
    echo "Current log directory size: $current_size KB"
    if [ $current_size -le $size_value ]; then
        echo "Log directory is already under the target size of $size_value MB."
        return
    fi

    while [ $current_size -gt $size_value ]; do
        largest_logs=$(find_largest_logs)
        while read -r log_entry; do
            log_file=$(echo "$log_entry" | awk '{print $2}')
            log_dir=$(dirname "$log_file")
            purge_log "$log_file"
            setup_logrotate "$log_dir"
            current_size=$(get_log_size)
            echo "Current log directory size after purging: $current_size KB"
            if [ $current_size -le $size_value ]; then
                echo "Log directory size is now under the target size of $size_valueMB MB."
                return
            fi
        done <<< "$largest_logs"
    done
}

find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.log" -mtime +14 -exec rm -f {} \;
log_cleanup
EOF

chmod +x "$target_script"
sudo sed -i "/^ExecStop=\/usr\/local\/bin\/log2ram stop/a ExecStopPost=/etc/log2ramdown.sh" /etc/systemd/system/log2ram.service
echo "Shutdown script created and made executable at $target_script. Logs will be purged if needed at each service shutdown."

check_desktop_environment() {
  if [[ -n "$XDG_CURRENT_DESKTOP" || -n "$DESKTOP_SESSION" || "$(pgrep -f 'gnome-session|startkde|xfce4-session|lxsession|mate-session|lxqt-session|cinnamon-session|budgie-desktop|deepin-session|sway|i3')" ]]; then
    return 0
  else
    return 1
  fi
}

remove_default_vnc() {
  if dpkg -l | grep -q realvnc-vnc-server; then
    echo "Raspberry Pi's default VNC server detected. Removing it..."
    sudo apt-get remove -y realvnc-vnc-server
  else
    echo "Raspberry Pi's default VNC server not detected."
  fi
}

install_tightvnc() {
  echo "Installing TightVNC Server..."
  sudo apt-get update
  sudo apt-get install -y tightvncserver
}

create_service() {
  echo "Creating systemd service for TightVNC Server..."
  sudo bash -c 'cat > /etc/systemd/system/tightvncserver.service <<EOF
[Unit]
Description=TightVNC server
After=network.target

[Service]
Type=simple
User='$USER'
PAMName=login
PIDFile=/home/'$USER'/.vnc/%H%i.pid
ExecStart=/usr/bin/vncserver :1 -geometry 1920x1080 -depth 24
ExecStop=/usr/bin/vncserver -kill :1

[Install]
WantedBy=multi-user.target
EOF'
  sudo systemctl daemon-reload
  sudo systemctl enable tightvncserver.service
}

setup_vnc() {
  if [[ "$contkey" == "V" ]]; then
    do_stuff=true
  elif [[ "$contkey" == "N" ]]; then
    do_stuff=false
  else
    read -p "Do you want to do it? (yes/no): " response
    if [[ "$response" == "yes" ]]; then
      do_stuff=true
    else
      do_stuff=false
    fi
  fi

  if [[ "$do_stuff" == true ]]; then
    remove_default_vnc
    install_tightvnc
    echo "Running TightVNC Server for initial configuration..."
    vncserver :1
    vncserver -kill :1
    create_service
    echo "TightVNC Server has been installed and configured. It will start automatically at boot."
  else
    echo "Skipping the installation and configuration of TightVNC Server."
  fi
}

if check_desktop_environment; then
  echo "Desktop environment detected."
  setup_vnc
else
  echo "No desktop environment detected. Skipping VNC server setup."
fi

echo 
echo "Done."
echo
echo "After the reboot, you can check the status of zram-swap by running 'zramctl'."
echo "After the reboot, you can check the status of log2ram by running 'systemctl status log2ram'."
echo "After the reboot, you can check the status of tightvncserver by running 'systemctl status tightvncserver'."
echo
echo "Rasputin-up setup script completed successfully! The system will now reboot in 10 seconds. Press CTRL+C to abort."
for i in $(seq 10 -1 1); do
    echo -ne "\rRebooting in $i seconds..."
    sleep 1
done

reboot
