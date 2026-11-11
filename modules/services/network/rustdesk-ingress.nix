{ ... }:

let
  network = import ../../../common/network.nix;
  rustdesk = network.rustdesk;
  ingress = network.ingressWireguard;
  wan = network.hosts.shrek.wanInterface;
  incomingInterfaces = [
    wan
    network.wireguard.interface
  ];
  tcpPorts = builtins.concatStringsSep "," (map toString rustdesk.tcpPorts);
  udpPorts = builtins.concatStringsSep "," (map toString rustdesk.udpPorts);

  ingressRules =
    action: onFailure:
    builtins.concatStringsSep "" (
      map (interface: ''
        iptables -t nat ${action} PREROUTING -i ${interface} -p tcp -m multiport --dports ${tcpPorts} -j DNAT --to-destination ${rustdesk.serverAddress} ${onFailure}
        iptables -t nat ${action} PREROUTING -i ${interface} -p udp -m multiport --dports ${udpPorts} -j DNAT --to-destination ${rustdesk.serverAddress} ${onFailure}

        iptables ${action} FORWARD -i ${interface} -o ${ingress.interface} -d ${rustdesk.serverAddress} -p tcp -m multiport --dports ${tcpPorts} -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT ${onFailure}
        iptables ${action} FORWARD -i ${interface} -o ${ingress.interface} -d ${rustdesk.serverAddress} -p udp -m multiport --dports ${udpPorts} -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT ${onFailure}
        iptables ${action} FORWARD -i ${ingress.interface} -o ${interface} -s ${rustdesk.serverAddress} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT ${onFailure}
      '') incomingInterfaces
    );

  firewallRules = action: onFailure: ''
    ${ingressRules action onFailure}

    # Keep replies on wg-ingress instead of compute0's LAN default route.
    iptables -t nat ${action} POSTROUTING -o ${ingress.interface} -d ${rustdesk.serverAddress} -p tcp -m multiport --dports ${tcpPorts} -j SNAT --to-source ${ingress.shrek.address} ${onFailure}
    iptables -t nat ${action} POSTROUTING -o ${ingress.interface} -d ${rustdesk.serverAddress} -p udp -m multiport --dports ${udpPorts} -j SNAT --to-source ${ingress.shrek.address} ${onFailure}
  '';
in
{
  networking.firewall = {
    extraCommands = firewallRules "-A" "";
    extraStopCommands = ''
      # Cleanup must also succeed when a previous firewall start was partial.
      ${firewallRules "-D" "2>/dev/null || true"}
    '';
  };
}
