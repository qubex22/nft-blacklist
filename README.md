# nft-blacklist

A Bash shell script which uses nftables sets to ban a large number of IP addresses published in IP blacklists. Working with vyos network groups.

## What's new

- 20/05/2025: Add vyos support

## Quick start for VyOS 1.4 installations
0. Create the vyos network group `set firewall group network-group blackhole` This will create the set N_blackhole inside vyos_filter table (see https://forum.vyos.io/t/how-to-load-networks-from-a-file-to-add-them-into-the-firewall-group-in-vyos-1-4-with-ntf-command-to-replace-removed-ipset/13997/2)
1. `wget -O /config/scripts/nft-blacklist.sh https://raw.githubusercontent.com/qubex22/nft-blacklist/master/nft-blacklist.sh`
2. `chmod +x /config/scripts/nft-blacklist.sh`
3. `mkdir -p /config/user-data/nft-blacklist && mkdir -p /config/user-data/cache/nft-blacklist ; wget -O /config/user-data/nft-blacklist/nft-blacklist.conf https://raw.githubusercontent.com/qubex22/nft-blacklist/master/nft-blacklist.conf`
4. Modify `nft-blacklist.conf` according to your needs. Per default, the blacklisted IP addresses will be saved to `/config/user-data/nft-blacklist/blacklist.nft`
5. Download `cidr-merger` from https://github.com/zhanhb/cidr-merger/releases
6. Create the nftables blacklist (see below). After proper testing, make sure to persist it in your firewall script or similar or the rules will be lost after the next reboot.
7. Auto-update the blacklist using a task
8. Use the new network group in the usual vyos firewall config. Example:
   ```
   set firewall ipv4 name WAN_IN rule 1 action 'drop'
   set firewall ipv4 name WAN_IN rule 1 description 'blacklist'
   set firewall ipv4 name WAN_IN rule 1 log
   set firewall ipv4 name WAN_IN rule 1 protocol 'all'
   set firewall ipv4 name WAN_IN rule 1 source group network-group 'blackhole'
   ```

## First run, create the list

to generate the `/config/user-data/ip-blacklist.restore`:

```sh
/config/scripts/nft-blacklist.sh /config/user-data/nft-blacklist/nft-blacklist.conf
```

## nftables filter rule

```sh
# Enable blacklists
nft -f /config/user-data/nft-blacklist/blacklist.nft
```


## Task scheduler

```
set system task-scheduler task Update-Blacklists executable path '/config/scripts/nft-blacklist.sh'
set system task-scheduler task Update-Blacklists interval '500m'
```

## Check for dropped packets

Using nftables, you can check how many packets got dropped using the blacklist:

```sh
leshniak@raspberrypi ~> sudo nft list counter ip blackhole blacklist_v4
table inet blackhole {
        counter blacklist_v4 {
                packets 52 bytes 2303
        }
}
leshniak@raspberrypi ~> sudo nft list counter inet blackhole blacklist_v6
table inet blackhole {
        counter blacklist_v6 {
                packets 0 bytes 0
        }
}
```

## Modify the blacklists you want to use

Edit the BLACKLIST array in /etc/nft-blacklist/nft-blacklist.conf to add or remove blacklists, or use it to add your own blacklists.

```sh
BLACKLISTS=(
"http://www.mysite.me/files/mycustomblacklist.txt" # Your personal blacklist
"http://www.projecthoneypot.org/list_of_ips.php?t=d&rss=1" # Project Honey Pot Directory of Dictionary Attacker IPs
# I don't want this: "http://www.openbl.org/lists/base.txt"  # OpenBL.org 30 day List
)
```

If you for some reason want to ban all IP addresses from a certain country, have a look at [IPverse.net's](http://ipverse.net/ipblocks/data/countries/) aggregated IP lists which you can simply add to the BLACKLISTS variable. For a ton of spam and malware related blacklists, check out this github repo: https://github.com/firehol/blocklist-ipsets
