#MmD
#!/bin/bash

GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
GOLD=$(tput setaf 3)
NC=$(tput sgr0) # No Color

# Root check
check_root_user() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as ${RED}root!${NC}"
    exit 1
  fi
}

# OpenVPN setup
openvpn_setup() {
    echo "Setting up OpenVPN..."
    bash openvpn/openvpn_install.sh
}

# tun2socks setup for openvpn
tun2socks_openvpn_setup() {
    echo "Setting up tun2socks OpenVPN..."

    # Create the TUN interface
    ip tuntap add mode tun dev tunx_openvpn
    ip addr add 198.19.0.1/15 dev tunx_openvpn
    ip link set dev tunx_openvpn up

    # Add custom route table
    echo "300 tunx_openvpn_table" >> /etc/iproute2/rt_tables
    ip route add 10.8.0.0/24 dev tunx_openvpn table tunx_openvpn_table
    ip route add default dev tunx_openvpn table tunx_openvpn_table
    ip rule add from 10.8.0.0/24 table tunx_openvpn_table

    # Set up iptables rules for traffic forwarding
    iptables -A FORWARD -i tun0 -o tunx_openvpn -j ACCEPT
    iptables -A FORWARD -i tunx_openvpn -o tun0 -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip rule add to 8.8.8.8 table main

    # Save iptables rules and make them persistent depending on the system
    if command -v iptables-persistent &>/dev/null; then
        apt install -y iptables-persistent
        netfilter-persistent save
    else
        # For other systems using iptables-save and restore
        iptables-save > /etc/iptables/rules.v4
        iptables-save > /etc/iptables/rules.v6
    fi

        cat <<EOF > /etc/systemd/system/tun2socks_openvpn_setup.service
[Unit]
Description=tun2socks OpenVPN Service
After=network.target

[Service]
ExecStartPre=/bin/sh -c "/usr/sbin/ip tuntap del mode tun dev tunx_openvpn || true"
ExecStart=/usr/sbin/ip tuntap add mode tun dev tunx_openvpn
ExecStartPost=/usr/sbin/ip addr add 198.19.0.1/15 dev tunx_openvpn
ExecStartPost=/usr/sbin/ip link set dev tunx_openvpn up
ExecStartPost=/bin/bash -c "echo '300 tunx_openvpn_table' >> /etc/iproute2/rt_tables"
ExecStartPost=/usr/sbin/ip route add 10.8.0.0/24 dev tunx_openvpn table tunx_openvpn_table
ExecStartPost=/usr/sbin/ip route add default dev tunx_openvpn table tunx_openvpn_table
ExecStartPost=/usr/sbin/ip rule add from 10.8.0.0/24 table tunx_openvpn_table
ExecStartPost=/usr/sbin/ip rule add to 8.8.8.8 table main
ExecStartPost=/usr/sbin/iptables -A FORWARD -i tun0 -o tunx_openvpn -j ACCEPT
ExecStartPost=/usr/sbin/iptables -A FORWARD -i tunx_openvpn -o tun0 -m state --state ESTABLISHED,RELATED -j ACCEPT

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable tun2socks_openvpn_setup.service
        systemctl start tun2socks_openvpn_setup.service


    echo "tun2socks OpenVPN setup complete. Service started."
}

# tun2socks interface for OpenVPN
tun2socks_openvpn_interface() {
    echo "Setting up tun2socks interface for OpenVPN..."

    # Check if tun2socks binary is available
    if [[ ! -f /opt/tun2socks ]]; then
        echo "tun2socks binary not found in /opt. Please ensure it is downloaded and installed first."
        exit 1
    fi

    # Create systemd service for tun2socks
    cat <<EOF > /etc/systemd/system/tun2socks_openvpn_interface.service
[Unit]
Description=tun2socks interface for OpenVPN
After=network.target

[Service]
ExecStart=/opt/tun2socks -device tunx_openvpn -proxy socks5://127.0.0.1:10808
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd to recognize the new service
    systemctl daemon-reload

    # Enable and start the tun2socks service
    systemctl enable tun2socks_openvpn_interface.service
    systemctl start tun2socks_openvpn_interface.service

    
    echo "tun2socks interface for OpenVPN service has been started and enabled to run on boot."
}

# L2TP setup script
l2tp_setup() {
    echo "Setting up L2TP..."
    bash l2tp/install.sh
	ipsec restart
    echo "L2TP installation complete."
}

# tun2socks setup for L2TP
tun2socks_l2tp_setup() {
    echo "Setting up tun2socks for L2TP..."

    # Create the TUN interface
    ip tuntap add mode tun dev tunx_l2tp
    ip addr add 198.18.0.1/15 dev tunx_l2tp
    ip link set dev tunx_l2tp up

    # Add custom route table
    echo "200 tunx_l2tp_table" >> /etc/iproute2/rt_tables
    ip route add 172.18.0.0/24 dev tunx_l2tp table tunx_l2tp_table
    ip route add default dev tunx_l2tp table tunx_l2tp_table
    ip rule add from 172.18.0.0/24 table tunx_l2tp_table

    # Set up iptables rules for traffic forwarding
    iptables -A FORWARD -i ppp0 -o tunx_l2tp -j ACCEPT
    iptables -A FORWARD -i tunx_l2tp -o ppp0 -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip rule add to 8.8.8.8 table main

    # Save iptables rules and make them persistent depending on the system
    if command -v iptables-persistent &>/dev/null; then
        apt-get install -y iptables-persistent
        netfilter-persistent save
    elif command -v service &>/dev/null; then
        # For other systems using iptables-save and restore
        iptables-save > /etc/iptables/rules.v4
        iptables-save > /etc/iptables/rules.v6 
    fi
        cat <<EOF > /etc/systemd/system/tun2socks_l2tp_setup.service
[Unit]
Description=tun2socks L2TP Service
After=network.target

[Service]
ExecStartPre=/bin/sh -c "/usr/sbin/ip tuntap del mode tun dev tunx_l2tp || true"
ExecStart=/usr/sbin/ip tuntap add mode tun dev tunx_l2tp
ExecStartPost=/usr/sbin/ip addr add 198.18.0.1/15 dev tunx_l2tp
ExecStartPost=/usr/sbin/ip link set dev tunx_l2tp up
ExecStartPost=/bin/bash -c "echo '200 tunx_l2tp_table' >> /etc/iproute2/rt_tables"
ExecStartPost=/usr/sbin/ip route add 172.18.0.0/24 dev tunx_l2tp table tunx_l2tp_table
ExecStartPost=/usr/sbin/ip route add default dev tunx_l2tp table tunx_l2tp_table
ExecStartPost=/usr/sbin/ip rule add from 172.18.0.0/24 table tunx_l2tp_table
ExecStartPost=/usr/sbin/ip rule add to 8.8.8.8 table main
ExecStartPost=/usr/sbin/iptables -A FORWARD -i ppp0 -o tunx_l2tp -j ACCEPT
ExecStartPost=/usr/sbin/iptables -A FORWARD -i tunx_l2tp -o ppp0 -m state --state ESTABLISHED,RELATED -j ACCEPT

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable tun2socks_l2tp_setup.service
        systemctl start tun2socks_l2tp_setup.service
		
    echo "Tun2Socks L2TP setup complete. Service started."
}

# tun2socks interface for L2TP
tun2socks_l2tp_interface() {
    echo "Setting up tun2socks..."

    # Check if tun2socks binary is available
    if [[ ! -f /opt/tun2socks ]]; then
        echo "tun2socks binary not found in /opt. Please ensure it is downloaded and installed first."
        exit 1
    fi

    # Create systemd service for tun2socks
    cat <<EOF > /etc/systemd/system/tun2socks_l2tp_interface.service
[Unit]
Description=tun2socks Interface for L2TP Service
After=network.target

[Service]
ExecStart=/opt/tun2socks -device tunx_l2tp -proxy socks5://127.0.0.1:10808
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd to recognize the new service
    systemctl daemon-reload

    # Enable and start the tun2socks service
    systemctl enable tun2socks_l2tp_interface.service
    systemctl start tun2socks_l2tp_interface.service

    # Log that the service was started
    echo "tun2socks interface for L2TP service has been started and enabled to run on boot."
}

# xray setup for tunnel
xray_tunnel() {
    echo "Setting up Xray Tunnel..."
    cp configs/xray/xray_tunnel.json /opt/xray_tunnel.json
    echo "xray_tunnel.json copied to /opt"
	
    # Create the systemd service file for Xray Tunnel
    SYSTEMD_SERVICE="/etc/systemd/system/xray_tunnel.service"
    cat <<EOF > "$SYSTEMD_SERVICE"
[Unit]
Description=Xray Tunnel Service
After=network.target

[Service]
ExecStart=/opt/xray run -c /opt/xray_tunnel.json
WorkingDirectory=/opt
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd to recognize the new service
    echo "Reloading systemd..."
    systemctl daemon-reload

    # Enable and start the service
    echo "Enabling and starting Xray Tunnel service..."
    systemctl enable xray_tunnel
    systemctl start xray_tunnel

    echo "Xray Tunnel setup complete."
}

xray_edge() {
    echo "Setting up Xray Edge..."
    cp configs/xray/xray_edge.json /opt/xray_edge.json
    echo "xray_edge.json copied to /opt"

    # Create the systemd service file for Xray Tunnel
    SYSTEMD_SERVICE="/etc/systemd/system/xray_edge.service"
    cat <<EOF > "$SYSTEMD_SERVICE"
[Unit]
Description=Xray Edge Service
After=network.target

[Service]
ExecStart=/opt/xray run -c /opt/xray_edge.json
WorkingDirectory=/opt
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd to recognize the new service
    echo "Reloading systemd..."
    systemctl daemon-reload

    # Enable and start the service
    echo "Enabling and starting Xray Tunnel service..."
    systemctl enable xray_edge.service
    systemctl start xray_edge.service

    echo "Xray Edge setup complete."
}

# Download latest xray-core
download_xray() {
    echo "Fetching latest Xray-core version..."
    LATEST_XRAY_VERSION=$(curl -sL https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep -oP '"tag_name": "\K(.*?)(?=")')
    echo "Latest Xray-core version: $LATEST_XRAY_VERSION"

    echo "Downloading Xray-core..."
    CPU_ARCH=$(uname -m)
    XRAY_BASE_URL="https://github.com/XTLS/Xray-core/releases/download"
    
    case "$CPU_ARCH" in
        "aarch64")
            XRAY_FILE="Xray-linux-arm64-v8a.zip"
            ;;
        "armv7l")
            XRAY_FILE="Xray-linux-arm32-v7a.zip"
            ;;
        *)
            XRAY_FILE="Xray-linux-64.zip"
            ;;
    esac

    wget -O /opt/"$XRAY_FILE" "$XRAY_BASE_URL/$LATEST_XRAY_VERSION/$XRAY_FILE"
    unzip -o /opt/"$XRAY_FILE" -d /opt
    rm -f /opt/Xray*.zip  # Remove the downloaded zip file
    mv /opt/xray* /opt/xray
    chmod +x /opt/xray  # Make the binary executable
}

# rathole tunnel setup
rathole_tunnel() {
    echo "Setting up Rathole Tunnel..."
    cp configs/rathole/rathole_tunnel.toml /opt/rathole_tunnel.toml
    echo "rathole_tunnel.toml copied to /opt"

    # Create the systemd service file for Rathole Tunnel
    SYSTEMD_SERVICE="/etc/systemd/system/rathole_tunnel.service"
    cat <<EOF > "$SYSTEMD_SERVICE"
[Unit]
Description=Rathole Tunnel Service
After=network.target

[Service]
ExecStart=/opt/rathole /opt/rathole_tunnel.toml
WorkingDirectory=/opt
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd to recognize the new service
    echo "Reloading systemd..."
    systemctl daemon-reload

    # Enable and start the service
    echo "Enabling and starting Rathole Tunnel service..."
    systemctl enable rathole_tunnel
    systemctl start rathole_tunnel

    echo "Rathole Tunnel setup complete."
}

rathole_edge() {
    echo "Setting up Rathole Edge..."
    cp configs/rathole/rathole_edge.toml /opt/rathole_edge.toml
    echo "rathole_edge.toml copied to /opt"

    # Create the systemd service file for Rathole Tunnel
    SYSTEMD_SERVICE="/etc/systemd/system/rathole_edge.service"
    cat <<EOF > "$SYSTEMD_SERVICE"
[Unit]
Description=Rathole Edge Service
After=network.target

[Service]
ExecStart=/opt/rathole /opt/rathole_edge.toml
WorkingDirectory=/opt
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd to recognize the new service
    echo "Reloading systemd..."
    systemctl daemon-reload

    # Enable and start the service
    echo "Enabling and starting Rathole Edge service..."
    systemctl enable rathole_edge.service
    systemctl start rathole_edge.service

    echo "Rathole Edge setup complete."
}

# Download latest rathole
download_rathole() {
    echo "Fetching latest Rathole version..."
    LATEST_RATHOLE_VERSION=$(curl -sL https://api.github.com/repos/rapiz1/rathole/releases/latest | grep -oP '"tag_name": "\K(.*?)(?=")')
    echo "Latest Rathole version: $LATEST_RATHOLE_VERSION"

    echo "Downloading Rathole..."
    CPU_ARCH=$(uname -m)
    RATHOLE_BASE_URL="https://github.com/rapiz1/rathole/releases/download"
    
    case "$CPU_ARCH" in
        "aarch64")
            RATHOLE_FILE="rathole-aarch64-unknown-linux-musl.zip"
            ;;
        "armv7l")
            RATHOLE_FILE="rathole-armv7-unknown-linux-musleabihf.zip"
            ;;
        *)
            RATHOLE_FILE="rathole-x86_64-unknown-linux-gnu.zip"
            ;;
    esac

    wget -O /opt/"$RATHOLE_FILE" "$RATHOLE_BASE_URL/$LATEST_RATHOLE_VERSION/$RATHOLE_FILE"
    unzip -o /opt/"$RATHOLE_FILE" -d /opt
    rm -f /opt/rathole*.zip
    mv /opt/rathole* /opt/rathole
    chmod +x /opt/rathole
}


# Download latest rathole
download_tun2socks() {
    echo "Fetching latest tun2socks version..."
    LATEST_TUN2SOCKS_VERSION=$(curl -sL https://api.github.com/repos/xjasonlyu/tun2socks/releases/latest | grep -oP '"tag_name": "\K(.*?)(?=")')
    echo "Latest tun2socks version: $LATEST_TUN2SOCKS_VERSION"

    echo "Downloading tun2socks..."
    CPU_ARCH=$(uname -m)
    TUN2SOCKS_BASE_URL="https://github.com/xjasonlyu/tun2socks/releases/download"
    
    case "$CPU_ARCH" in
        "aarch64")
            TUN2SOCKS_FILE="tun2socks-linux-arm64.zip"
            ;;
        "armv7l")
            TUN2SOCKS_FILE="tun2socks-linux-armv7.zip"
            ;;
        *)
            TUN2SOCKS_FILE="tun2socks-linux-amd64.zip"
            ;;
    esac

    wget -O /opt/"$TUN2SOCKS_FILE" "$TUN2SOCKS_BASE_URL/$LATEST_TUN2SOCKS_VERSION/$TUN2SOCKS_FILE"
    unzip -o /opt/"$TUN2SOCKS_FILE" -d /opt
    rm -f /opt/tun2socks*.zip
    mv /opt/tun2socks-* /opt/tun2socks
    chmod +x /opt/tun2socks
}

# Setup tunnel server
setup_tunnel() {
    echo "Setting up Tunnel server..."
    apt update && apt install unzip git wget -y
	
    
    # Create /opt directory if it doesn't exist
    mkdir -p /opt

    download_rathole
    download_xray
    download_tun2socks
    rathole_tunnel
	vpn_type
	xray_tunnel
	echo
	echo "${GREEN}All Done!${NC} You can use ${RED}'rtxvpn_manage.sh'${NC} to manage users"
	echo	
}
TUNNEL_SERVER_IP=""
# Setup edge server
setup_edge() {
    echo "Setting up Edge server..."
    # Ask for Tunnel Server's IP
    read -p "Enter the Tunnel Server's IP address: " TUNNEL_SERVER_IP
	
	apt update && apt install unzip git wget -y
	
    download_rathole
    download_xray
    download_tun2socks
	rathole_edge
	xray_edge
	
	echo "Tunnel Server IP set to: $TUNNEL_SERVER_IP"

    # Update remote_addr in /opt/rathole_edge.toml
    CONFIG_FILE="/opt/rathole_edge.toml"
    
    if [ -f "$CONFIG_FILE" ]; then
        sed -i "s/remote_addr = \".*:[0-9]\+\"/remote_addr = \"$TUNNEL_SERVER_IP:7081\"/" "$CONFIG_FILE"
        echo "Updated remote_addr in $CONFIG_FILE"
    else
        echo "Error: $CONFIG_FILE not found!"
    fi
	echo
	echo "${GREEN}All Done!${NC} Enjoy your ${GOLD}FREEDOM${NC}"
	echo	
}

# Select VPN type
vpn_type() {
    echo "Select your VPN type:"
    echo "1. L2TP"
    echo "2. OpenVPN"
    echo "3. Both"
    read -p "Enter your choice (1, 2, or 3): " choice

    case "$choice" in
        1)
            echo "You selected L2TP."
            l2tp_setup
			tun2socks_l2tp_interface
			tun2socks_l2tp_setup
            ;;
        2)
            echo "You selected OpenVPN."
            openvpn_setup
			tun2socks_openvpn_interface
			tun2socks_openvpn_setup
            ;;
        3)
            echo "You selected Both L2TP and OpenVPN."
            l2tp_setup
			tun2socks_l2tp_interface
			tun2socks_l2tp_setup
			openvpn_setup
			tun2socks_openvpn_interface
			tun2socks_openvpn_setup
            ;;
        *)
            echo "Invalid choice. Please enter 1, 2, or 3."
            vpn_type
            ;;
    esac
}

check_root_user
# Main menu
while true; do
  echo
  echo
  echo "${GREEN} ▄▄▄▄▄▄▄▄▄▄▄  ▄▄▄▄▄▄▄▄▄▄▄  ▄       ▄       ▄               ▄  ▄▄▄▄▄▄▄▄▄▄▄  ▄▄        ▄ "
  echo "▐░░░░░░░░░░░▌▐░░░░░░░░░░░▌▐░▌     ▐░▌     ▐░▌             ▐░▌▐░░░░░░░░░░░▌▐░░▌      ▐░▌"
  echo "▐░█▀▀▀▀▀▀▀█░▌ ▀▀▀▀█░█▀▀▀▀  ▐░▌   ▐░▌       ▐░▌           ▐░▌ ▐░█▀▀▀▀▀▀▀█░▌▐░▌░▌     ▐░▌"
  echo "▐░▌       ▐░▌     ▐░▌       ▐░▌ ▐░▌         ▐░▌         ▐░▌  ▐░▌       ▐░▌▐░▌▐░▌    ▐░▌${NC}"
  echo "▐░█▄▄▄▄▄▄▄█░▌     ▐░▌        ▐░▐░▌${GOLD}▄▄▄▄▄▄▄▄▄▄▄${NC}▐░▌       ▐░▌   ▐░█▄▄▄▄▄▄▄█░▌▐░▌ ▐░▌   ▐░▌"
  echo "▐░░░░░░░░░░░▌     ▐░▌         ▐░▌${GOLD}▐  FREEDOM  ▌${NC}▐░▌     ▐░▌    ▐░░░░░░░░░░░▌▐░▌  ▐░▌  ▐░▌"
  echo "▐░█▀▀▀▀█░█▀▀      ▐░▌        ▐░▌░▌${GOLD}▀▀▀▀▀▀▀▀▀▀▀${NC}  ▐░▌   ▐░▌     ▐░█▀▀▀▀▀▀▀▀▀ ▐░▌   ▐░▌ ▐░▌"
  echo "${RED}▐░▌     ▐░▌       ▐░▌       ▐░▌ ▐░▌             ▐░▌ ▐░▌      ▐░▌          ▐░▌    ▐░▌▐░▌"
  echo "▐░▌      ▐░▌      ▐░▌      ▐░▌   ▐░▌             ▐░▐░▌       ▐░▌          ▐░▌     ▐░▐░▌"
  echo "▐░▌       ▐░▌     ▐░▌     ▐░▌     ▐░▌             ▐░▌        ▐░▌          ▐░▌      ▐░░▌"
  echo " ▀         ▀       ▀       ▀       ▀               ▀          ▀            ▀        ▀▀ ${NC}"

                                                                                    
	echo
    echo "Which server you are trying to setup?"
	echo
    echo "1) Tunnel"
    echo "2) Edge"
	echo
    read -p "Enter your choice (1 or 2): " choice

    case "$choice" in
        1)
            setup_tunnel
            break
            ;;
        2)
            setup_edge
            break
            ;;
        *)
            echo "Invalid choice. Please enter 1 or 2."
            ;;
    esac
done
