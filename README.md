# Rasputin-up
### The Tune-up Suite for Your Raspberry Pi

---

## Introduction

Welcome to **Rasputin-up**! This suite is designed to optimize and enhance the performance of your Raspberry Pi. The Mad Monk and Holy Healer - **Rasputin-up** mashes up log2ram and the pi-apps version of zram-swap to reduce wear on your SD card and reduce overall I/O overhead. I'm also going to change some logging settings to keep things under control.

## Features

- **Log Management**: 
  - Setting the system journal (and Zabbix if you've got it) to wrap after 7 days.
  - **SD Card Optimization**: Utilize log2ram to reduce writes to SD Card.
  - **Automated Cleanup**: Starts by reducing system journal to 64MB so we can start up with a smalller storage location.

## Installation

To install **Rasputin-up**, simply run the following command:

```bash
curl -L https://github.com/henroFall/Rasputin-up/setup.sh | bash
```

## Usage

After installation, your Raspberry Pi will automatically reboot. Once it's back up, you can check the status of log2ram with the following:

```bash
systemctl status log2ram
```

That's it! Once you reboot, everything is all set.

## Credits

All I did here was hack together an install script, and even used AI so I wouldn't have to type as much. All credit to the original authors of the zram-swap scripts that later got ported into what is now **[Pi-Apps](https://github.com/Botspot/pi-apps)** . I borrowed the "More RAM" script. 

Also, full credit to **[log2ram](https://github.com/azlux/log2ram)**, another great script, essential for Raspi or any OS running on fragile media. 

