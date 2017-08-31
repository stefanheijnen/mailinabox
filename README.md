Mail-in-a-Box (Ubuntu 16.04 aware)
==================================

**This is a fork**

For original sources, see [Mail-in-a-Box](https://github.com/mail-in-a-box/mailinabox)!

Why is this fork special?
-------------------------

Using this fork, one may easily install mail-in-a-box on **Ubuntu 16.04.03**!

Quick Install
-------------

```bash
# Clone this fork
git clone https://github.com/jirislav/mailinabox.git
cd mailinabox

# Add upstream sources
git remote add mail-in-a-box https://github.com/mail-in-a-box/mailinabox.git

# Actualize on top of the master
git rebase mail-in-a-box/master

# Run installation
setup/start.sh
```

For further info, see [the original documentation for obtaining mail-in-a-box](https://mailinabox.email/guide.html).

Troubleshooting
---------------

Feel free to email me at [developer@jkozlovsky.cz](mailto://developer@jkozlovsky.cz) or start an Issue here, at my fork - describing your problem deep enough.

Features
--------

* there is installed [spreed app](https://nextcloud.com/webrtc/) into the Nextcloud by default (Josh refused it)
* all services run in an systemd init system (much better UX)
* no php5 anywhere! - all running on php7, so there is no need to maintain two versions of php
* lesser hardware requirements (I run it on 500 MB RAM & 1 CPU without any hassle - from [DigitalOcean](https://www.digitalocean.com/?refcode=210c1aeb22bb&utm_campaign=Referral_Invite&utm_medium=Referral_Program&utm_source=CopyPaste))

Disadvantages
-------------

* lack of dovecot-lucene in Ubuntu 16.04 brought me to a decision to don't include fulltext search into the roundcube (all modern email clients have this already installed)
* sometimes, I may not notice updates in upstream - in that case you may easilly rebase their changes on top of my master as shown in the Quick Install section
