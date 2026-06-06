#!/bin/bash
set -e

########################################
# 🧱 SYSTEM UPDATE & PREREQUISITES
########################################
echo "=== Updating system and installing prerequisites ==="
sudo apt update && sudo apt upgrade -y
sudo apt-get install -y software-properties-common unzip wget curl gnupg

########################################
# 📊 INSTALL GRAFANA
########################################
echo "=== Installing Grafana ==="
sudo add-apt-repository -y "deb https://packages.grafana.com/oss/deb stable main"
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo apt update
sudo apt install grafana -y
sudo systemctl enable --now grafana-server
sudo systemctl status grafana-server --no-pager

########################################
# 📜 INSTALL LOKI
########################################
echo "=== Installing Loki ==="
cd /tmp
wget https://github.com/grafana/loki/releases/latest/download/loki-linux-amd64.zip
unzip -o loki-linux-amd64.zip
sudo mv loki-linux-amd64 /usr/local/bin/loki
sudo chmod +x /usr/local/bin/loki

sudo mkdir -p /etc/loki /var/lib/loki/index /var/lib/loki/chunks /var/lib/loki/wal
sudo useradd --system --no-create-home --shell /bin/false loki || true
sudo chown -R loki:loki /var/lib/loki

# Loki config
cat <<EOF | sudo tee /etc/loki-config.yaml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 5m
  max_chunk_age: 1h

schema_config:
  configs:
    - from: 2025-09-23
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb:
    directory: /var/lib/loki/index
  filesystem:
    directory: /var/lib/loki/chunks

limits_config:
  allow_structured_metadata: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
EOF

# Loki service
cat <<EOF | sudo tee /etc/systemd/system/loki.service
[Unit]
Description=Loki Log Aggregation System
After=network.target

[Service]
ExecStart=/usr/local/bin/loki --config.file=/etc/loki-config.yaml
Restart=always
User=loki
Group=loki
WorkingDirectory=/var/lib/loki

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable loki
sudo systemctl start loki
sudo systemctl status loki --no-pager

########################################
# 📦 INSTALL PROMTAIL
########################################
echo "=== Installing Promtail ==="
cd /tmp
wget https://github.com/grafana/loki/releases/latest/download/promtail-linux-amd64.zip
unzip -o promtail-linux-amd64.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
sudo chmod +x /usr/local/bin/promtail
sudo mkdir -p /etc/promtail

# Promtail config
cat <<EOF | sudo tee /etc/promtail/config.yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: systemd-journal
    journal:
      path: /var/log/journal
      labels:
        job: systemd
        host: ${HOSTNAME}
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'

  - job_name: apache2
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          host: ${HOSTNAME}
          __path__: /var/log/apache2/access.log

  - job_name: varerror
    static_configs:
      - targets:
          - localhost
        labels:
          job: varerror
          host: ${HOSTNAME}
          __path__: /var/log/apache2/error.log
          
  - job_name: python-app
    static_configs:
      - targets:
          - localhost
        labels:
          job: python-app
          host: ${HOSTNAME}
          __path__: /var/log/python-app/*.log

EOF

# Promtail service
cat <<EOF | sudo tee /etc/systemd/system/promtail.service
[Unit]
Description=Promtail service
After=network.target

[Service]
ExecStart=/usr/local/bin/promtail --config.file=/etc/promtail/config.yaml
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable promtail
sudo systemctl start promtail
sudo systemctl status promtail --no-pager

########################################
# ⏱ INSTALL TEMPO
########################################
echo "=== Installing Tempo ==="
cd /tmp
wget https://github.com/grafana/tempo/releases/download/v2.8.2/tempo_2.8.2_linux_amd64.tar.gz
tar -xvf tempo_2.8.2_linux_amd64.tar.gz
sudo mv tempo /usr/local/bin/
sudo chmod +x /usr/local/bin/tempo
sudo mkdir -p /etc/tempo /var/lib/tempo

# Tempo config
cat <<EOF | sudo tee /etc/tempo/config.yaml
server:
  http_listen_port: 3200
  grpc_listen_port: 9096

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
        http:

ingester:
  trace_idle_period: 10s
  max_block_duration: 5m

compactor:
  compaction:
    block_retention: 1h

storage:
  trace:
    backend: local
    local:
      path: /var/lib/tempo/traces
EOF

# Tempo service
cat <<EOF | sudo tee /etc/systemd/system/tempo.service
[Unit]
Description=Grafana Tempo service
After=network.target

[Service]
ExecStart=/usr/local/bin/tempo --config.file=/etc/tempo/config.yaml
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable tempo
sudo systemctl start tempo
sudo systemctl status tempo --no-pager

########################################
# ✅ COMPLETION MESSAGE
########################################
echo "=================================================="
echo "✅ Installation complete!"
echo "Grafana running on: http://<your-server-ip>:3000"
echo "Loki listening on: http://localhost:3100"
echo "Promtail sending logs to Loki"
echo "Tempo listening on: http://localhost:3200"
echo "=================================================="
