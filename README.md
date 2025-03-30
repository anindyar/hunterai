# Elastic Stack with Nginx Proxy Manager and Cloudflare ZTNE

This repository contains a complete setup for running Elastic Stack (Elasticsearch, Kibana, Fleet Server, Elastic Agent) with Nginx Proxy Manager and Cloudflare Zero Trust Network Exchange (ZTNE) for secure remote access.

## Prerequisites

- Docker and Docker Compose installed
- A Cloudflare account with Zero Trust enabled
- A domain name managed by Cloudflare

## Components

- Elasticsearch 8.12.0
- Kibana 8.12.0
- Fleet Server 8.12.0
- Elastic Agent 8.12.0
- Nginx Proxy Manager
- Cloudflare ZTNE (using cloudflared)

## Quick Start

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd <repository-name>
   ```

2. Make the setup script executable:
   ```bash
   chmod +x setup.sh
   ```

3. Run the setup script:
   ```bash
   ./setup.sh
   ```
   The script will:
   - Ask for your domain name
   - Generate secure passwords and tokens
   - Create necessary subdomains (kibana.yourdomain.com, fleet.yourdomain.com)
   - Set up all required services

4. Update the `.env` file with your Cloudflare token:
   ```bash
   CLOUDFLARE_TOKEN=your_cloudflare_token_here
   ```

5. Access the services:
   - Elasticsearch: http://localhost:9200
   - Kibana: https://kibana.yourdomain.com
   - Fleet Server: https://fleet.yourdomain.com
   - Nginx Proxy Manager Admin: http://localhost:81

## Configuration

### Nginx Proxy Manager Setup

1. Access the Nginx Proxy Manager admin panel at http://localhost:81
2. Login with the credentials from the .env file
3. Create proxy hosts for:
   - Kibana:
     - Domain: kibana.yourdomain.com
     - Forward Hostname: kibana
     - Forward Port: 5601
   - Fleet Server:
     - Domain: fleet.yourdomain.com
     - Forward Hostname: fleet-server
     - Forward Port: 8220

### Cloudflare ZTNE Setup

1. Log in to your Cloudflare Zero Trust dashboard
2. Create a new tunnel
3. Copy the tunnel token
4. Update the CLOUDFLARE_TOKEN in the .env file
5. Create DNS records for:
   - kibana.yourdomain.com
   - fleet.yourdomain.com
6. Restart the services:
   ```bash
   docker-compose down
   docker-compose up -d
   ```

## Security Notes

- All passwords and tokens are randomly generated and stored in the .env file
- Elastic Stack is configured with security enabled
- Fleet Server and Elastic Agent are pre-configured with secure tokens
- Nginx Proxy Manager provides SSL/TLS termination
- Cloudflare ZTNE ensures secure remote access

## Maintenance

### Updating Services

To update all services to their latest versions:

```bash
docker-compose pull
docker-compose up -d
```

### Backup

The following directories contain persistent data:
- data/elasticsearch
- data/kibana
- data/fleet
- data/npm

Regular backups of these directories are recommended.

## Troubleshooting

1. Check service logs:
   ```bash
   docker-compose logs -f [service-name]
   ```

2. Common issues:
   - Elasticsearch memory issues: Adjust ES_JAVA_OPTS in docker-compose.yml
   - Permission issues: Ensure proper permissions on data directories
   - Cloudflare tunnel issues: Verify token and domain configuration
   - Fleet Server connection issues: Check FLEET_SERVER_TOKEN and FLEET_SERVER_HOST in .env

## License

MIT License 