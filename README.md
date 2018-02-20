Mail-in-a-Box (Ubuntu 16.04 aware)
==================================

**This is a fork**

For original sources, see [Mail-in-a-Box](https://github.com/mail-in-a-box/mailinabox)!

Why is this fork special?
-------------------------

Using this fork, one may easily install mail-in-a-box on **Ubuntu 16.04.03**!

Features
--------

* [spreed](https://nextcloud.com/webrtc/) in Nextcloud by default
    * private and secure voice & videoconference calls
* [nextant](https://github.com/nextcloud/nextant#nextant) in Nextcloud by default
    * fulltext search built on top of Apache Solr
	* you can search text within all of your JPGs, PNGs, PDFs, Office documents, etc. (it's using [OCR](https://en.wikipedia.org/wiki/Optical_character_recognition))
* all services run in an systemd init system (much better UX)
* no php5 anywhere! - all running on php7, so there is no need to maintain two versions of php
* lesser hardware requirements (I run it on 512 MB RAM & 1 CPU without any hassle - from [DigitalOcean](https://www.digitalocean.com/?refcode=210c1aeb22bb&utm_campaign=Referral_Invite&utm_medium=Referral_Program&utm_source=CopyPaste) )

Disadvantages
-------------

* lack of dovecot-lucene in Ubuntu 16.04 brought me to a decision to don't include fulltext search into the roundcube
    * but that seems not to be an issue because all modern email clients have this already installed

Quick Install
-------------

```bash
# Clone this fork
git clone https://github.com/jirislav/mailinabox.git
cd mailinabox

git checkout v0.26c-ubuntu16

# Run installation
setup/start.sh
```

## Toubleshooting

In case of some trouble, please issue `setup/start.sh` command once again. If that doesn't help, please also try this command:
```bash
INSTALL_NEXTANT=no setup/start.sh
```

Otherwise, you are welcome to [file a new issue](https://github.com/jirislav/mailinabox/issues/new).

For further info, see [the original documentation for obtaining mail-in-a-box](https://mailinabox.email/guide.html).
