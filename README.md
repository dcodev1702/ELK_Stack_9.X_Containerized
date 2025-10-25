# ELK Stack 9.2.0 Containerized - Network Monitoring PoC

A production-ready ELK Stack (Elasticsearch & Kibana) deployment using Docker Compose, designed to support Windows VMs running Packetbeat 9.2.0 for efficient network monitoring with minimal noise.

## 📋 Overview

This Proof of Concept provides a containerized ELK Stack optimized for network traffic analysis from Windows environments. The solution features:

- **Elasticsearch 9.2.0** - Single-node deployment with security enabled
- **Kibana 9.2.0** - Web UI for visualization and analysis  
- **Packetbeat Support** - Pre-configured for Windows VM integration with aggressive noise filtering
- **Automated Lifecycle Management** - Smart bash script for stack operations

## 🎯 Use Case

This PoC demonstrates efficient network monitoring for Windows VMs in enterprise environments, particularly useful for:
- DNS traffic analysis and anomaly detection
- Reduced storage footprint through intelligent filtering
- Security operations center (SOC) visibility
- Quick deployment for incident response scenarios

## 📦 Prerequisites

### Docker Installation (Ubuntu 24.04 LTS)

This project requires Docker and Docker Compose. If not already installed, follow these steps:

```bash
# Download and run the Docker installation script
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to the docker group (allows running Docker without sudo)
sudo usermod -aG docker $USER

# Apply the group changes (or log out and back in)
newgrp docker

# Verify installation
docker --version
docker compose version
```

**Note:** After adding your user to the docker group, you may need to log out and log back in for the changes to take effect.

## 🚀 Quick Start

```bash
# Start the stack
./run_elk_stack.sh start

# Check health status
./run_elk_stack.sh status

# Stop and remove volumes
./run_elk_stack.sh stop

# Complete cleanup (including images)
./run_elk_stack.sh destroy
```

## 📁 Project Structure

```
.
├── docker-compose.yml      # ELK Stack service definitions
├── dot.env                # Environment variables (rename to .env)
├── run_elk_stack.sh       # Lifecycle management script
├── packetbeat/
│   └── packetbeat.yml     # Filtered Packetbeat configuration
└── README.md
```

## 🔧 Configuration

### Environment Setup

1. Rename `dot.env` to `.env` and customize:
```bash
STACK_VERSION=9.2.0
ELASTIC_PASSWORD=your_secure_password
KIBANA_PASSWORD=your_kibana_password
ES_PORT=9200
KIBANA_ENCRYPTION_KEY=your_32_byte_key_here
HOST_IP=10.0.0.9  # Your host IP
```

### Packetbeat Configuration

The `packetbeat.yml` is highly optimized to reduce noise in enterprise environments:

#### Key Filtering Features

1. **Port Exclusions** - Ignores common administrative and service ports:
   - SSH (22), HTTPS (443), RDP (3389)
   - Elastic stack ports (5601, 9200, 9300)
   - High ephemeral ports (49152-65535)

2. **DNS Noise Reduction** - Filters out:
   - Azure/Microsoft telemetry domains
   - Windows Update traffic
   - Internal/local DNS queries
   - Analytics and telemetry services
   - Private IP responses

3. **Metadata Minimization** - Drops unnecessary fields:
   - Process, service, and related metadata
   - Host OS and MAC information
   - Agent identifiers
   - Network byte/packet counts

4. **Protocol Focus** - Currently configured for:
   - DNS traffic analysis (port 53)
   - Flows disabled to reduce volume

#### Windows VM Integration

Deploy Packetbeat 9.2.0 on your Windows VMs with this configuration:

```powershell
# On Windows VM
# 1. Install Packetbeat 9.2.0
# 2. Replace packetbeat.yml with the provided configuration
# 3. Update HOST_IP in the yml to point to your Docker host
# 4. Start Packetbeat service
```

## 🎯 Script Efficiencies

The `run_elk_stack.sh` script provides intelligent automation:

### Smart Features

1. **Health Status Monitoring (NEW)**
   - Real-time cluster health display with `./run_elk_stack.sh status`
   - Shows Elasticsearch cluster state with color-coded status (green ✅)
   - Displays Kibana access URL and authentication details
   - Container health table with uptime metrics (e.g., "Up 38 minutes")
   - Port mapping visualization for all services
   - Helpful tip reminder for viewing live logs

   ![ELK Stack Health Status](./docs/health-status.png)
   
   *The status command provides an at-a-glance health summary with connection details and container states*

2. **Automatic IP Detection**
   - Discovers host IP via default route interface
   - Multiple fallback mechanisms (hostname -I, localhost)
   - No manual IP configuration needed

3. **Health Monitoring**
   - Waits for Elasticsearch cluster health (green/yellow)
   - Configurable retry logic (30 attempts, 10s intervals)
   - Prevents premature operations

4. **Container Lifecycle Management**
   - Monitors and cleans up one-shot setup containers
   - Prevents orphaned containers from cluttering the system
   - Automatic removal after successful initialization

5. **Interactive Mode**
   - Prompts for action if none provided
   - Supports: start, stop, destroy, and status commands
   - Case-insensitive input handling
   - Clear feedback throughout operations

6. **Complete Cleanup Options**
   - `stop`: Removes containers and named volumes
   - `destroy`: Full cleanup including images and anonymous volumes
   - System prune to reclaim disk space

### Error Handling

- Set -e for immediate exit on errors
- Set -u for undefined variable protection  
- Set -o pipefail for pipeline error detection
- Graceful fallbacks for missing commands

## 📊 Access Points

Once started, access your stack at:

- **Elasticsearch**: http://[HOST_IP]:9200
- **Kibana**: http://[HOST_IP]:5601

Default credentials:
- Username: `elastic`
- Password: (as configured in .env)

## 📊 Health Status Monitoring

The script includes a comprehensive health status command that provides real-time visibility into your ELK Stack:

```bash
./run_elk_stack.sh status
```

This command displays:

### Health Summary Output
- **Elasticsearch Section**:
  - 🔗 URL: Connection endpoint
  - ✅ Status: Cluster health (green/yellow/red)
  - 🔢 Version: Running version
  - 🔧 Cluster: Cluster name
  
- **Kibana Login Section**:
  - 🔗 URL: Web UI endpoint
  - 👤 Username: Authentication user
  - 🔑 Password: Login credentials

- **Container Status Table**:
  - Container names and states (running/stopped)
  - Health status (healthy/unhealthy)
  - Uptime information
  - Port mappings for all services

The status command provides a quick way to verify that all components are operational and to retrieve connection information without checking logs or Docker commands.

## 🔒 Security Considerations

- X-Pack security is enabled by default
- Separate passwords for elastic and kibana_system users
- Encryption keys for Kibana saved objects and reporting
- Consider using TLS in production environments

## 📈 Performance Optimization

The filtered Packetbeat configuration significantly reduces:
- **Storage Requirements**: ~80% reduction in event volume
- **Network Overhead**: Minimal impact on monitored systems
- **Processing Load**: Lower CPU usage on Elasticsearch nodes
- **Query Performance**: Faster searches due to reduced index size

## 🧪 Testing the Setup

```bash
# Verify Elasticsearch
curl -u elastic:your_password http://localhost:9200/_cluster/health

# Check Kibana status
curl -u elastic:your_password http://localhost:5601/api/status

# View Packetbeat data streams (after Windows VM connected)
curl -u elastic:your_password http://localhost:9200/_data_stream/
```

## 🔍 Troubleshooting

```bash
# View all logs
docker compose logs -f

# Check specific service
docker compose logs elasticsearch
docker compose logs kibana

# Verify containers are running
docker compose ps

# Inspect network
docker network ls
docker network inspect elk_stack_92_containerized_elastic
```

## 📝 License

MIT License - See LICENSE file for details

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

---

**Author**: DCODEV1702  
**Version**: 1.0.0  
**Last Updated**: 2025
