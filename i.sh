#!/bin/bash

# Set the PATH to include common command directories
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Tìm tên của card mạng
INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n 1)

# Kiểm tra xem có card mạng nào được tìm thấy không
if [ -z "$INTERFACE" ]; then
    echo "Không tìm thấy card mạng."
    exit 1
fi

echo "Card mang: $INTERFACE"

# Set username and password
USERNAME="vlt"
PASSWORD="vltpro"

# Tạo số ngẫu nhiên trong khoảng từ 1000 đến 2000
RANDOM_PORT=$((10000 + RANDOM % 10001))

# In ra số cổng ngẫu nhiên
echo "Cổng ngẫu nhiên: $RANDOM_PORT"

# Generate hashed password
HASHED_PASSWORD=$(openssl passwd -apr1 "$PASSWORD")

# Check if Squid configuration directory exists, if not, create it
CONFIG_DIR="/etc/squid"
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir "$CONFIG_DIR"
fi

# Generate squid.passwords file with hashed password
echo "$USERNAME:$HASHED_PASSWORD" > "$CONFIG_DIR/squid.passwords"

# Get IP addresses
IP4=$(curl -4 -s icanhazip.com)
IP6_PREFIX=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

# Display IP information
echo "Internal ip = ${IP4}. Prefix for ip6 = ${IP6_PREFIX}"

# Function to generate a random IPv6 address with 64 bits prefix
gen_ipv6() {
    for i in $(seq 1 4096); do
        echo "${IP6_PREFIX}:$(openssl rand -hex 4):$(openssl rand -hex 4):$(openssl rand -hex 4):$(openssl rand -hex 4)"
    done
}

# Generate random IPv6 addresses and save to file
gen_ipv6 > "$CONFIG_DIR/ipv6add.acl"

# Function to generate ports configuration
generate_ports_config() {
    for port in $(seq 1000 5096); do
        echo "http_port ${IP4}:${port}"
    done
}

# Generate ACLs and tcp_outgoing_address lines
generate_acls() {
    for port in $(seq 1000 5096); do
        port_var="port$port"
        echo "acl ${port_var} localport ${port}"
        echo "tcp_outgoing_address $(head -n 1 "$CONFIG_DIR/ipv6add.acl") ${port_var}"
    done
}

# Function to add iptables rules for random ports
add_random_port_rules() {
    NUM_PORTS=$1
    for ((i=1; i<=$NUM_PORTS; i++)); do
        RANDOM_PORT=$((10000 + RANDOM % 10001))
        echo "Thêm quy tắc cho cổng ngẫu nhiên: $RANDOM_PORT"
        iptables -A INPUT -p tcp -m tcp --dport $RANDOM_PORT -m state --state NEW -j ACCEPT
    done
}

# Add iptables rules for 5 random ports
add_random_port_rules 5096

# Add IPv6 addresses to the network interface
generate_interfaces() {
    while IFS= read -r ip; do
        ip -6 addr add "$ip/64" dev "$INTERFACE"
    done < "$CONFIG_DIR/ipv6add.acl"
}

# Restart Squid service
restart_squid() {
    systemctl restart squid
}

# Set up crontab job to run the entire script every 20 minutes
setup_cron_job() {
    if ! crontab -l | grep -q "/root/setup.sh"; then
        (crontab -l; echo "*/20 * * * * /bin/bash /root/setup.sh >> /root/cron.log 2>&1") | crontab -
        echo "Added cron job to run the script every 20 minutes."
    else
        echo "Cron job already exists."
    fi
}

# Main function to execute all steps
main() {
    generate_ports_config > "$CONFIG_DIR/ports.conf"
    generate_acls > "$CONFIG_DIR/outgoing.conf"
    generate_interfaces
    restart_squid
    setup_cron_job
}

# Execute main function
main

echo "Finished"

# Ping google.com bằng IPv6
ping_google6() {
    ping6 -c 3 google.com
}

ping_google6
