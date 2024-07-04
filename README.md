# Rasputin-up
### The Tune-up Suite for My (Your) Raspberry Pi

---

## Introduction

Welcome to **Rasputin-up**! I cobbled this together becuase I got tired of doing this all manually every time I built a new SBC. For now, I've got log2ram and the pi-apps version of zram-swap to reduce wear on your SD card and reduce overall I/O overhead. I'm also configure all the log files I can find to roll every 7 days. Plus TightVNC, cause reasons.

You can technically run this on any Debian / Ubuntu based thing, but the problems this solves affect SBCs (1GB and up) with SD based main storage. Plus, I thought the name was clever. Try to say it out loud. I think it works. 

## Features

  - **Log Management**: Setting the system journal (and anything else I find) to wrap after 7 days.
  - **SD Card Optimization**: Utilize log2ram to reduce writes to SD Card.
  - **SWAP Optimization**: Sure, swapping to RAM is stupid. I could go on and on. BUT - swapping to an SD is also stupid. And, no swap on a SBC is pretty hard, and mostly stupid. Hence, ZRAM-SWAP. You'll lose a couple hundred meg of RAM for lots of usable swap space, it works for me.
  - **TightVNC**: Why? [You know why](https://youtu.be/qraa_1EX9GY?si=78f3KR4CXlxlk74m). But, seriously, I use [MobaXTerm](https://mobaxterm.mobatek.net/demo.html) and it doesn't like RealVNC. Plus, RealVNC lost me at "pricing." So I was constantly running the TightVNC installer, now it's in here for me, and you!

## Installation

To install **Rasputin-up**, simply run the following command:

```bash
curl -L https://raw.githubusercontent.com/henroFall/Rasputin-up/main/rasputinupsetup.sh -o /tmp/rasputinupsetup.sh && sudo bash /tmp/rasputinupsetup.sh
```
There are no options, there is no stopping it. The script is heavily commented so you can see what you're getting yourself into. Well, OK, there is one option. There is an --uninstall switch, if you want. It will revert your Pie back to what it was before the Mad Monk got ahold of it.

## Usage

Just execute the installer, there aren't really any options except to VNC, or not to VNC. As a limit of how log2ram first starts, I will prune down your existing logs to a size that the OS will allow to move over. Log2ram compresses everything, so your actual log storage can be quite large, but when the OS tries to set it up for the first time, the /var/log folder can't be larger than the ramdisk. Anyway, who cares? If you're installing this, you probably aren't worried about what's in your logs to-date.

After installation, your Raspberry Pi will automatically reboot. Once it's back up, you can check the status of log2ram with the following:

```bash
systemctl status log2ram
```

That's it! Once you reboot, everything is all set.

## Credits

All credit to the original authors of the zram-swap scripts that later got ported into what is now **[Pi-Apps](https://github.com/Botspot/pi-apps)** . I'm hooked into the "More RAM" script. 

Also, full credit to **[log2ram](https://github.com/azlux/log2ram)**, another great script, essential for Raspi or any OS running on fragile media. 

## Contributions

Drop a note if you have a regular hack you lay on top of your SBCs that I should sprinkle on top of this... I think this one will be maintained for the long term.

## License

Licensed under the Bob Barker. This software is completely free to use, fork, modify, distribute, talk bad about, whatever. 

Just remember: Always get your pets spayed or neutered. 

