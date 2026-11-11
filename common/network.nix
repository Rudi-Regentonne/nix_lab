# Central Network Inventory
# Single source of truth for hosts, IPs, and DHCP reservations.
rec {
  domain = "home";
  publicDomain = "rudiregentonne.de";
  acmeEmail = "admin@rudiregentonne.de";
  subnet = "192.168.10.0/24";
  gateway = "192.168.10.1";

  # Dedicated public-ingress tunnel. The VPS terminates TLS and forwards HTTP
  # to compute0 without exposing the home LAN or application ports directly.
  ingressWireguard = {
    interface = "wg-ingress";
    port = 51821;
    subnet = "10.20.0.0/24";
    shrek.address = "10.20.0.1";
    compute.address = "10.20.0.2";
    # Public keys are populated alongside the encrypted private keys.
    shrek.publicKey = "LmAZAKMHf0PBOmODp+Znj4ixtce8LYLCDSPwoDuS2Ek=";
    compute.publicKey = "LEBv7AQTiGs9FtrPudSN90954HjwZjpVGofwi/DDSyg=";
  };

  # RustDesk runs on compute0 and is exposed by shrek over wg-ingress.
  # The web-client ports (21118/21119) intentionally remain closed.
  rustdesk = {
    publicHost = "rustdesk.${publicDomain}";
    serverAddress = ingressWireguard.compute.address;
    relayPort = 21117;
    tcpPorts = [
      21115
      21116
      21117
    ];
    udpPorts = [ 21116 ];
  };

  # Hub-and-spoke WireGuard overlay:
  #   LAN -> Renate --wg--> shrek -> internet
  #   phones/laptops --wg--> shrek -> LAN (and internet)
  wireguard = {
    interface = "wg0";
    # Hub listen port. Road-warrior clients dial clientPort (DNAT on shrek).
    port = 51820;
    clientPort = 1194;
    subnet = "10.10.10.0/24";
    subnet6 = "fd10:10:10::/64";

    shrek = {
      address = "10.10.10.1";
      address6 = "fd10:10:10::1";
      publicKey = "ADH2MRs6M1iwPcdmQmr4RB78D7/DDQ1+5nRlYs+EUlw=";
    };

    renate = {
      address = "10.10.10.2";
      address6 = "fd10:10:10::2";
      publicKey = "iVuWvfO8vq6auerV1cryu5RRUkJxxtjsclk6UyBVK1k=";
    };

    clients = {
      phone = {
        address = "10.10.10.10";
        address6 = "fd10:10:10::10";
        publicKey = "T9X7BTJ+6E0VurUTcvep4pzVRYQbX6bsVn97CiBc9CA=";
      };
      frank = {
        address = "10.10.10.11";
        address6 = "fd10:10:10::11";
        publicKey = "KXr7u/J9Lf+5FdBbc/dX4kNQmfuTxqh6rYsDNeC30AQ=";
      };
    };
  };

  hosts = {
    router = {
      hostName = "renate";
      ip = "192.168.10.1";
      lanInterface = "enp0s21f0u1";
      wanInterface = "eno1";
    };

    shrek = {
      hostName = "shrek";
      wanInterface = "ens6";
      disk = "/dev/vda";
      ip = wireguard.shrek.address;
    };

    switch = {
      hostName = "switch";
      ip = "192.168.10.2";
      description = "Dell PowerConnect 2724 Core Switch";
    };

    compute = {
      hostName = "compute0";
      lanInterface = "enp8s0u1";
      ip = "192.168.10.16";
    };

    nas = {
      hostName = "nas";
      ip = "192.168.10.20";
    };
  };
}
