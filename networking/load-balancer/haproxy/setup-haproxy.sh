#!/bin/bash
# networking/load-balancer/haproxy/setup-haproxy.sh

echo "⚖️ Setting up HAProxy Load Balancer"

# Install HAProxy
sudo apt update
sudo apt install -y haproxy

# Configure HAProxy
cat > /etc/haproxy/haproxy.cfg << EOF
global
    daemon
    maxconn 4000
    user haproxy
    group haproxy

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    log global

frontend http_front
    bind *:80
    bind *:443 ssl crt /etc/ssl/infokes.pem
    stats uri /haproxy?stats
    default_backend http_back

backend http_back
    balance roundrobin
    server app1 10.0.10.11:3000 check
    server app2 10.0.10.12:3000 check
    option httpchk GET /health

frontend https_redirect
    bind *:8080
    redirect scheme https code 301 if !{ ssl_fc }
EOF

# Enable and start HAProxy
systemctl enable haproxy
systemctl start haproxy

echo "✅ HAProxy setup completed!"