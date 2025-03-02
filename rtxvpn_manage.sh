#MmD
#!/bin/bash
l2tp_manage() {
    echo
    echo "Choose an option:"
    echo "1. Add User"
    echo "2. Remove User"
    read -p "Enter your choice (1 or 2): " choice

    case "$choice" in
        1)
            bash l2tp/adduser.sh
            ;;
        2)
            bash l2tp/deluser.sh
            ;;
        *)
            echo "Invalid choice. Please enter 1 or 2."
            ;;
    esac
}

# Main menu
while true; do
    echo
    echo "Choose VPN type"
    echo
    echo "1) L2TP"
    echo "2) OpenVPN"
    echo
    read -p "Enter your choice (1 or 2): " choice

    case "$choice" in
        1)
            l2tp_manage
            ;;
        2)
            bash openvpn/openvpn_install.sh
            ;;
        *)
            echo "Invalid choice. Please enter 1 or 2."
            ;;
    esac
done
