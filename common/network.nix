# Central Network Inventory
# Single source of truth for hosts, IPs, and DHCP reservations.
rec {
  domain = "home";
  subnet = "192.168.10.0/24";
  gateway = "192.168.10.1";

  hosts = {
    router = {
      hostName = "Renate";
      ip = "192.168.10.1";
      lanInterface = "enp0s21f0u1";
      wanInterface = "eno1";
    };

    switch = {
      hostName = "switch";
      ip = "192.168.10.2";
      description = "Dell PowerConnect 2724 Core Switch";
    };

    k8s-node = {
      hostName = "node0";
      ip = "192.168.10.16";
      # mac = "bc:24:11:xx:xx:xx"; # Uncomment and set to enable static DHCP lease
    };

    nas = {
      hostName = "nas";
      ip = "192.168.10.20";
    };

    room = {
      hostName = "room";
      ip = "192.168.10.93";
    };
  };
}
