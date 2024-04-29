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

# Tạo số ngẫu nhiên trong khoảng từ 1000 đến 2000
RANDOM_PORT=$((1000 + RANDOM % 1001))

# In ra số cổng ngẫu nhiên
echo "Cổng ngẫu nhiên: $RANDOM_PORT"

# Set username and password
USERNAME="vlt"
PASSWORD="vltpro"

INTERFACE="$INTERFACE"

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

# Function to generate a random IPv6 address with 48 bits prefix
gen48() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Generate random IPv6 addresses and save to file
gen_ipv6() {
    for port in $(seq 1000 2000); do
        echo "$(gen48 $IP6_PREFIX)"
    done
}
gen_ipv6 > "$CONFIG_DIR/ipv6add.acl"

# Function to generate ports configuration
generate_ports_config() {
    for port in $(seq 1000 2000); do
        echo "http_port ${IP4}:${port}"
    done
}
generate_ports_config > "$CONFIG_DIR/acls/ports.conf"

# Generate ACLs and tcp_outgoing_address lines
generate_acls() {
    for port in $(seq 1000 2000); do
        port_var="port$port"
        echo "acl ${port_var} localport ${port}"
        echo "tcp_outgoing_address $(head -n 1 "$CONFIG_DIR/ipv6add.acl") ${port_var}"
    done
}
generate_acls > "$CONFIG_DIR/acls/outgoing.conf"

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
    if ! crontab -l | grep -q "/root/i.sh"; then
        (crontab -l; echo "*/20 * * * * /bin/bash /root/i.sh >> /root/cron.log 2>&1") | crontab -
        echo "Added cron job to run the script every 20 minutes."
    else
        echo "Cron job already exists."
    fi
}

# Main function to execute all steps
main() {
    generate_interfaces
    restart_squid
    setup_cron_job
}

# Execute main function
main

echo "Finished"

#!/bin/bash

# Định nghĩa các biến
LOG_FILE="/var/log/squid_check.log"
SQUID_IP="14.224.163.75"
SQUID_PORT="1000-2000"
SQUID_IPV6="2001:ee0:4f9b:92b0"

# Kiểm tra kết nối đến Squid sử dụng cổng và địa chỉ IPv6
echo "$(date '+%Y-%m-%d %H:%M:%S') - Kiểm tra kết nối đến Squid..." >> $LOG_FILE
nc -zv -w 5 $SQUID_IP $SQUID_PORT >> $LOG_FILE 2>&1
nc -6 -zv -w 5 $SQUID_IPV6 $SQUID_PORT >> $LOG_FILE 2>&1

# Kiểm tra trạng thái của Squid service
echo "$(date '+%Y-%m-%d %H:%M:%S') - Kiểm tra trạng thái Squid service..." >> $LOG_FILE
systemctl status squid >> $LOG_FILE 2>&1

# Kiểm tra xem tệp squid.conf đã được tạo chưa
echo "$(date '+%Y-%m-%d %H:%M:%S') - Kiểm tra xem tệp squid.conf đã được tạo chưa..." >> $LOG_FILE
if [ -f "/etc/squid/squid.conf" ]; then
    echo "Tệp squid.conf đã được tạo." >> $LOG_FILE
else
    echo "Lỗi: Tệp squid.conf chưa được tạo." >> $LOG_FILE
fi
