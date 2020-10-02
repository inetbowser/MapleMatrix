# 🍁 Maple Matrix 🕸️

This code is a fork of [Brannon Dorsey's mitm-router](https://github.com/brannondorsey/mitm-router) which has been updated and improved.

#### mitm-router Summary
Turn any linux computer into a public Wi-Fi network that silently mitms all HTTP traffic. Runs inside a Docker container using [hostapd](https://wiki.gentoo.org/wiki/Hostapd), [dnsmasq](http://www.thekelleys.org.uk/dnsmasq/doc.html), and [mitmproxy](https://mitmproxy.org/) to create an open honeypot wireless network.

## Improvements and Changes
Building on mitm-router, MapleMatrix makes some improvements:

|                                 |      mitm-router     |     MapleMatrix    |
|---------------------------------|----------------------|--------------------|
| Operating System                | Debian jessie        | Debian buster      |
| Architecture                    | x86-64 only          | multiarch          |
| mitmproxy version               | 2.0.2 (April, 2017)  | 5.1.1 (June, 2020) |
| Transparent mode                | no                   | yes                |
| HTTPS traffic                   | no                   | yes                |
| Default binary                  | `mitmdump`           | `mitmweb`          |
| Network dump                    | `mitmdump`           | `tshark`           |
| Build / run                     | Docker commands      | Makefile           |
| Docker config                   | shell scripts        | Docker .env file   |
| Certificate Generation          | no                   | yes                |
| Easy to adjust host ignore list | no                   | yes                |
| mitmproxy script support        | no                   | yes                |
| ANSI logo                       | no                   | yes                |

In more detail:

* *Updated OS*: now built with Debian buster
* *Multiarch*: The same code will work on both intel and ARM hardware which speeds up testing
    * This requires building mitmproxy from source which can be slow though should be cached by docker.
* *mitmproxy v5.1.1*: Using the latest stable release as of June, 2020
    * It is trivial to move to a different version; just change the variable in the Dockerfile.
* *HTTPS traffic + Transparent Mode*: As long as the certificate file in the `fake_ca` directory is [correctly installed](https://docs.mitmproxy.org/stable/concepts-certificates/#installing-the-mitmproxy-ca-certificate-manually) on a machine that joins the network served by the appliance, it will be transparently mitm'd, including its HTTPS traffic(!).  No need to setup/use an HTTP(S) proxy.
* *mitmweb*: mitmproxy's web-interface is used by default (port 8081)
    * Since `--net host` is used this should be accessible from outside the container without the need for forwarding ports
    * The other two mitmproxy binaries, `mitmdump` and `mitmproxy` are available if needed; just modify the entrypoint script!
* *pcapng dump*: All traffic will be written out using `tshark` in pcapng format to `data/` along with the Pre-Master-Secret Key Log file.
    * These files can be married together in `wireshark` to view all of the appliance's decrypted network traffic.
* *Quality of Life improvements*:
    * *Makefile*: Building and running the image is simplified using a makefile, as inspired by other docker repos
    * *.env file*: appliance-settings (network name, password, etc) all live in a proper docker `.env` file
    * *Tidying*: A few other minor style changes / organizational updates
    * *Better configuration*: Configuration files are broken out in a more logical way
        * mitmproxy's config is displayed when the appliance starts
    * *ANSI Art*: A logo is display in the shell for maximum geek cred
* *mitmproxy scripts*: the 'scripts' directory is volume-mounted into the container so [mitmproxy scripts](https://docs.mitmproxy.org/stable/addons-scripting/) can be developed and run.  Any script loaded into mitmproxy is reloaded when it's saved so you don't even have to restart the appliance.

## Installation and Use
### Appliance Setup
```bash
# edit the (self-documenting) basic-env file to your liking
$ vim basic-env

# Generate your own self-signed CA if the one commited to the repo has expired or you want to
# Either way, save a copy of the `mitmproxy-ca.crt` file; you'll need this later.
$ make generateCA

# build the image
# (you might need sudo here, depending on how docker is configured)
# Also, as a guideline, this took:
#   * around 20 minutes on my Raspberry Pi 3B+!
#   * around 4 minutes on my i3 intel NUC
$ make build

# run the appliance
# (you might need sudo here, depending on how docker is configured)
$ make run
```

Once you see `proxy server listening...` the Appliance is ready to mitm traffic.  By default, the appliance uses `mitmweb`, `mitmproxy`'s web interface.

### Client setup
```bash
# Now, connect to the network served by the appliance from a device
$ curl https://http.cat/404 # should fail with an HTTPS error
$ curl --cacert /path/to/mitmproxy-ca.crt https://http.cat/404 # should work without error
```

If this is working, install the `mitmproxy-ca.crt` file permanently by following the standard mitmproxy instructions, found [here](https://docs.mitmproxy.org/stable/concepts-certificates/#installing-the-mitmproxy-ca-certificate-manually).  Note that browsers oftain maintain their own browser chains so you may have to install the certificate in a few places (eg: The OS itself but also chrome, firefox, etc).

If you wish to MITM an android device, there is another `make` command to convert the generated cert into the proper "subject_hash_old" format.

Otherwise, this code should operate like mitm-router.

#### Configuring the Appliance
You'll probably need to tweak the `templates/mitm-config.yml` file, for example the list of 'ignored hosts' or `raw_tcp` mode.

The `(sudo) make shell` command from the Makefile is a really helpful debugging tool; it starts an instance of the appliance but stops short of running `entrypoint.sh`.

You'll almost certainly want to replace the ANSI art as well :-)

#### Decrypting TLS traffic from pcapng dumps
1. Run the appliance for as long as desired.
2. From the host, start `wireshark` and load the `.pcapng` file from `data/`
3. Following [these steps](https://wiki.wireshark.org/TLS?action=show&redirect=SSL#Using_the_.28Pre.29-Master-Secret), load the `sslkeylogfile.txt` into wireshark by going to *Preferences -> Protocols -> TLS -> (Pre)-Master-Secret log filename* and choosing the file.
    * Note that for older versions of `wireshark`, *TLS* may be called *SSL*
4. Upon saving the preference, 'new' HTTPS traffic will be revealed from the decoded TLS packets.

### Troubleshooting
Check out mitm-router's source repo's [README](https://github.com/brannondorsey/mitm-router/blob/master/README.md) (and the linked [troubleshooting](https://github.com/brannondorsey/mitm-router/blob/master/troubleshooting.md) page) since some info that hasn't changed has been removed for simplicity.

Some other suggestions that came up in development:
* Make sure WIFI hardware is enabled (eg `rfkill unblock all`)
* Make sure the firewall on the host isn't interfering with the appliance
    * This can cause a dhcp lease to never be granted, for example
* Make sure the `dnsmasq` server the appliance spins up doesn't conflict with other `dnsmasq` processes

Feel free to drop me a line if you have questions about the changes I've made though!

### Future Work
* **Modular Configs**: Having to manually edit a bunch of config files to switch between MITM targets is a drag; there should be a system to allow 'bundles' of configs to be pre-defined and more modularly loaded and unloaded, for example different apps or devices.

* **WiFi only mode**: It'd be really useful to have a `make` command to run the appliance as normal but without any interception at all for testing / debugging.  Currently this can be achieved by setting `mitmproxy` to ignore all hosts but this is sloppy.

* **Host firewall changes**: There are conflicts between the appliance and the host's firewall, if extant.  I worked around this by completely disabling the firewall on my host but there must be a better way (precise ports to open, etc).  This should be documented.

* **Make the PI work more than once**: A strange error running this appliance on the Pi that I couldn't figure out lead to it only working one time per reboot.  I think it has something to do with the firewall settings within the appliance affected the host via `--net host` or perhaps with the software versions?  The same appliance works fine on my Intel NUC, both of which run debian.

* **Better capture filters**: There might be better ways to configure `tshark` when capturing MapleMatrix networking activity.  In particular, it seemed to only work if the interface was the NIC connected to the internet and not the wifi adaptor, which seemed odd.  This bears more exploration.

* **Run on startup**: It'd be nice to bundle in some systemd scripts or whatever to allow the appliance to run at startup on some device so it could truly work as an appliance.  Perhaps some configure network share could be mounted as well for logging captures.

* **Multistage Build**: Given that the appliance must, at present, compile `mitmproxy` from src in order to work on multiple architectures, it'd be great to use Docker's multi-stage builds to shrink the resultant image / speed up build times (though it usually does a pretty good job of caching between builds).

* **Concise FW rules**: This is pretty much cosmetic but there are a bunch of very verbose `iptables` commands in the `entrypoint.sh` script; I thought they could be combined using `--dports` (for example, 2 of the rules are identical except for one is on port `80` and one is on port `443`.  Despite this, I couldn't get these commands to work.   More info [here](https://serverfault.com/questions/353130/iptables-and-multiple-ports).
