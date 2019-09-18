#SET VARIABLES
:global ifaces 8;
:global mIface "wlan1"
:global prefix "wlan"
:global gw 10.204.10.1
:global lanAddress 10.10.0.1
:global ssid "WIFI_ETECSA"
:global rootRoute "$gw%$mIface"
for route from=2 to=$ifaces do={ :set $rootRoute ($rootRoute,"$gw%$prefix$route") }

#SET CLIENTS INTERFACES
interface wireless set $mIface ssid=$ssid disabled=no
for iface from=2 to=$ifaces  do={ interface wireless add ssid=$ssid master-interface=$mIface mode=station name="$prefix$iface" disabled=no }

#SET IP ADDRESS CONFIGURATION AND DHCP SERVER
:global startIP ($lanAddress + 1);
:global endIP (($lanAddress|0.0.0.255)-1);
ip address add address="$lanAddress/24" interface=ether1
ip pool add name=LANsubnet ranges="$startIP-$endIP"
ip dhcp-server add address-pool=LANsubnet interface=ether1 lease-time=1d name=dhcpLAN disabled=no
ip dhcp-server network add address=10.10.0.0/24 dns-server=10.10.0.1 gateway=10.10.0.1 netmask=24

#SET DHCP CLIENTS
for iface from=1 to=$ifaces do={ ip dhcp-client add interface="$prefix$iface" use-peer-dns=no use-peer-ntp=no disabled=no }

#SET DNS SERVERS
ip dns set servers=181.225.231.110,181.225.231.120,181.225.233.30,181.225.233.40 allow-remote-requests=yes

#FIREWALL MANGLE
for rule from=1 to=$ifaces do={ ip firewall mangle add action=mark-routing new-routing-mark="$prefix$rule" src-address-list="$prefix$rule" chain=prerouting dst-address-type=!local passthrough=yes }
for rule from=1 to=$ifaces do={ ip firewall mangle add action=mark-connection new-connection-mark="$prefix$rule_con" chain=prerouting passthrough=yes nth=1,1 dst-address-type=!local disabled=yes src-address-list="full" connection-state=new; ip firewall mangle add action=mark-routing new-routing-mark="$prefix$rule" connection-mark="$prefix$rule_con" chain=prerouting src-address-list="full" dst-address-type=!local passthrough=no}
ip firewall mangle set comment="MARCADO DE RUTAS PARA CADA INTERFAZ >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>" numbers=0
ip firewall mangle set comment="MARCADO DE CONEXIONES Y RUTAS PARA NTH  >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>" numbers=8


#FIREWALL NAT
for nat from=1 to=$ifaces do={ ip firewall nat add chain=srcnat action=masquerade routing-mark="$prefix$nat" out-interface="$prefix$nat" }

#ROUTES
for route from=1 to=$ifaces do={ ip route add gateway="$gw%$prefix$route" dst-address=0.0.0.0/0 routing-mark="$prefix$route" }
for route from=1 to=$ifaces do={ ip route add gateway="$gw%$prefix$route" dst-address="1.1.1.10$route" }
ip route add gateway=$rootRoute dst-address=0.0.0.0/0 comment=for_router

#NETWATCH
for netw from=1 to=$ifaces do={ tool netwatch add down-script="ip firewall mangle disable [find new-connection-mark=$prefix$netw_con \
    and src-address-list=\"full\"];\r\
    \nsystem script run Failover;" host="1.1.1.10$netw" interval=5s timeout=3s \
    up-script="ip firewall mangle enable [find new-connection-mark=$prefix$netw_con and\
    \_src-address-list=\"full\"];\r\
    \nsystem script run Failover;" }

foreach var in=[system script environment find] do={ system script environment remove $var }
system scheduler add name=init start-time=startup on-event="delay 5;\r\ \nsystem script run Failover;"

#FAILOVER
:local iface "wlan1"
:local steps 0;
:local tempSteps 1;
:local addrs (10.10.0.9,10.10.0.10);
:local ruleIDs [/ip firewall mangle find new-connection-mark~"_con" and disabled=no];
:local ruleIDs [/ip firewall mangle find comment=NTH and disabled=no];
:local steps ([:len $ruleIDs ]);
:foreach ruleID in=$ruleIDs do {
    ip firewall mangle set [find .id=$ruleID] nth="$steps,$tempSteps";
    set tempSteps ($tempSteps + 1);
}
if ([$steps]=0) do {
    foreach addr in=$addrs do {
        do {
            if ([ip firewall address-list get value-name=list [find where address=$addr && comment="auto"]]="full") do {
                ip firewall address-list set list=$iface [find where list=full && comment="auto"];
            }
        } on-error {
            log warning "Ocurrio un error recuperando $addr de la lista";
        }
    }
} else {
    foreach addr in=$addrs do {
        do {
            if ([ip firewall address-list get value-name=list [find where address=$addr && comment="auto"]]=$iface) do {
                ip firewall address-list set list=full [find where list=$iface && comment="auto"];
            }
        } on-error {
            log warning "Ocurrio un error recuperando $addr de la lista";
        }
    }
}
