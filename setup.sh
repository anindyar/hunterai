#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Elastic Stack Setup with Nginx Proxy Manager and Cloudflare ZTNE${NC}"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Please install Docker first.${NC}"
    exit 1
fi

# Check if Docker Compose is installed and determine the command
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo -e "${RED}Neither 'docker-compose' nor 'docker compose' is available. Please install Docker Compose first.${NC}"
    exit 1
fi

# Check if cloudflared is installed
if ! command -v cloudflared &> /dev/null; then
    echo -e "${YELLOW}Installing cloudflared...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install cloudflared
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        sudo dpkg -i cloudflared.deb
        rm cloudflared.deb
    else
        echo -e "${RED}Unsupported operating system. Please install cloudflared manually.${NC}"
        exit 1
    fi
fi

# Get Elastic Stack version
echo -e "${YELLOW}Available Elastic Stack versions:${NC}"
echo -e "1. 8.17.0 (Latest stable)"
echo -e "2. 8.16.0"
echo -e "3. 8.15.0"
echo -e "4. Custom version"

while true; do
    read -p "Select Elastic Stack version (1-4): " VERSION_CHOICE
    case $VERSION_CHOICE in
        1) ELASTIC_VERSION="8.17.0"; break ;;
        2) ELASTIC_VERSION="8.16.0"; break ;;
        3) ELASTIC_VERSION="8.15.0"; break ;;
        4) 
            read -p "Enter custom version (e.g., 8.17.0): " CUSTOM_VERSION
            if [[ $CUSTOM_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ELASTIC_VERSION=$CUSTOM_VERSION
                break
            else
                echo -e "${RED}Invalid version format. Please use format like 8.17.0${NC}"
            fi
            ;;
        *) echo -e "${RED}Invalid choice. Please select 1-4.${NC}" ;;
    esac
done

# Get domain name from user
while true; do
    read -p "Enter your domain name (e.g., example.com or sub.example.com): " DOMAIN
    if [[ -n "$DOMAIN" ]]; then
        break
    else
        echo -e "${RED}Domain name cannot be empty. Please try again.${NC}"
    fi
done

# Extract the base domain (last two parts) for subdomain creation
BASE_DOMAIN=$(echo $DOMAIN | rev | cut -d. -f1,2 | rev)
if [[ "$DOMAIN" != "$BASE_DOMAIN" ]]; then
    echo -e "${YELLOW}Detected subdomain in input. Using base domain: ${BASE_DOMAIN}${NC}"
fi

# Create subdomains
KIBANA_DOMAIN="kibana.${BASE_DOMAIN}"
FLEET_DOMAIN="fleet.${BASE_DOMAIN}"

# Cloudflare setup
echo -e "${YELLOW}Setting up Cloudflare...${NC}"

# Check if user is logged in to Cloudflare
if ! cloudflared tunnel list &> /dev/null; then
    echo -e "${YELLOW}Please log in to Cloudflare...${NC}"
    cloudflared login
fi

# Create tunnel
echo -e "${YELLOW}Creating Cloudflare tunnel...${NC}"
TUNNEL_NAME="elastic-stack-$(date +%s)"
cloudflared tunnel create $TUNNEL_NAME

# Get tunnel ID and token
TUNNEL_ID=$(cloudflared tunnel list | grep $TUNNEL_NAME | awk '{print $1}')
TUNNEL_TOKEN=$(cloudflared tunnel token $TUNNEL_ID)

# Create DNS records
echo -e "${YELLOW}Creating DNS records...${NC}"
cloudflared tunnel route dns $TUNNEL_ID $KIBANA_DOMAIN
cloudflared tunnel route dns $TUNNEL_ID $FLEET_DOMAIN

# Create necessary directories
echo -e "${YELLOW}Creating necessary directories...${NC}"
mkdir -p data/elasticsearch
mkdir -p data/fleet
mkdir -p data/npm
mkdir -p cloudflared

# Set proper permissions
echo -e "${YELLOW}Setting proper permissions...${NC}"
chmod -R 777 data/elasticsearch

# Generate initial passwords and tokens
ELASTIC_PASSWORD=$(openssl rand -base64 32)
NPM_ADMIN_PASSWORD=$(openssl rand -base64 32)

# Create initial .env file
cat > .env << EOL
# Elastic Stack Configuration
ELASTIC_VERSION=${ELASTIC_VERSION}
ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
FLEET_SERVER_HOST=${FLEET_DOMAIN}

# Cloudflare Configuration
CLOUDFLARE_TOKEN=${TUNNEL_TOKEN}
CLOUDFLARE_DOMAIN=${BASE_DOMAIN}
KIBANA_DOMAIN=${KIBANA_DOMAIN}
FLEET_DOMAIN=${FLEET_DOMAIN}
TUNNEL_ID=${TUNNEL_ID}

# Nginx Proxy Manager Configuration
NPM_ADMIN_EMAIL=admin@${BASE_DOMAIN}
NPM_ADMIN_PASSWORD=${NPM_ADMIN_PASSWORD}
EOL

# Start Elasticsearch first
echo -e "${YELLOW}Starting Elasticsearch...${NC}"
$DOCKER_COMPOSE_CMD up -d elasticsearch

# Wait for Elasticsearch to be ready
echo -e "${YELLOW}Waiting for Elasticsearch to be ready...${NC}"
until curl -s -u elastic:${ELASTIC_PASSWORD} http://localhost:9200/_cluster/health | grep -q '"status":"green\|yellow"'; do
    echo -e "${YELLOW}Waiting for Elasticsearch...${NC}"
    sleep 5
done

# Create service accounts and get tokens
echo -e "${YELLOW}Creating service accounts...${NC}"

# Create Kibana service account
echo -e "${YELLOW}Creating Kibana service account...${NC}"
curl -X POST -u elastic:${ELASTIC_PASSWORD} -H "Content-Type: application/json" http://localhost:9200/_security/service/elastic/kibana -d '{
  "roles": [ "kibana_system" ]
}'

# Create Fleet service account
echo -e "${YELLOW}Creating Fleet service account...${NC}"
curl -X POST -u elastic:${ELASTIC_PASSWORD} -H "Content-Type: application/json" http://localhost:9200/_security/service/elastic/fleet -d '{
  "roles": [ "fleet_system" ]
}'

# Create Fleet Server service account
echo -e "${YELLOW}Creating Fleet Server service account...${NC}"
curl -X POST -u elastic:${ELASTIC_PASSWORD} -H "Content-Type: application/json" http://localhost:9200/_security/service/elastic/fleet-server -d '{
  "roles": [ "fleet_server" ]
}'

sleep 5

# Create Kibana service account token
echo -e "${YELLOW}Creating Kibana service token...${NC}"
KIBANA_SERVICE_TOKEN=$(curl -s -X POST -u elastic:${ELASTIC_PASSWORD} -H "Content-Type: application/json" http://localhost:9200/_security/service/elastic/kibana/credential/token | jq -r '.token.value')

# Create Fleet service account token
echo -e "${YELLOW}Creating Fleet service token...${NC}"
FLEET_SERVICE_TOKEN=$(curl -s -X POST -u elastic:${ELASTIC_PASSWORD} -H "Content-Type: application/json" http://localhost:9200/_security/service/elastic/fleet/credential/token | jq -r '.token.value')

# Create Fleet enrollment token
echo -e "${YELLOW}Creating Fleet enrollment token...${NC}"
FLEET_ENROLLMENT_TOKEN=$(curl -s -X POST -u elastic:${ELASTIC_PASSWORD} -H "Content-Type: application/json" http://localhost:9200/_security/service/elastic/fleet-server/credential/token | jq -r '.token.value')

# Verify tokens were created
if [ -z "$KIBANA_SERVICE_TOKEN" ] || [ -z "$FLEET_SERVICE_TOKEN" ] || [ -z "$FLEET_ENROLLMENT_TOKEN" ]; then
    echo -e "${RED}Failed to create service tokens. Please check Elasticsearch logs.${NC}"
    exit 1
fi

echo -e "${GREEN}Successfully created service accounts and tokens${NC}"

# Update .env with service tokens
cat >> .env << EOL

# Service Account Tokens
KIBANA_SERVICE_TOKEN=${KIBANA_SERVICE_TOKEN}
FLEET_SERVICE_TOKEN=${FLEET_SERVICE_TOKEN}
FLEET_ENROLLMENT_TOKEN=${FLEET_ENROLLMENT_TOKEN}
EOL

# Start the remaining services
echo -e "${YELLOW}Starting remaining services...${NC}"
$DOCKER_COMPOSE_CMD up -d

# Wait for services to be ready
echo -e "${YELLOW}Waiting for services to be ready...${NC}"
sleep 30

# Print access information
echo -e "${GREEN}Setup completed! Here are the access details:${NC}"
echo -e "Elasticsearch: http://localhost:9200"
echo -e "Kibana: https://${KIBANA_DOMAIN}"
echo -e "Fleet Server: https://${FLEET_DOMAIN}"
echo -e "Nginx Proxy Manager Admin: http://localhost:81"
echo -e "\nCredentials:"
echo -e "Elastic Stack:"
echo -e "Username: elastic"
echo -e "Password: ${ELASTIC_PASSWORD}"
echo -e "\nNginx Proxy Manager:"
echo -e "Email: admin@${BASE_DOMAIN}"
echo -e "Password: ${NPM_ADMIN_PASSWORD}"

# Save the credentials to a file for reference
cat > credentials.txt << EOL
Elastic Stack Credentials:
------------------------
Username: elastic
Password: ${ELASTIC_PASSWORD}

Service Account Tokens:
--------------------
Kibana: ${KIBANA_SERVICE_TOKEN}
Fleet: ${FLEET_SERVICE_TOKEN}
Fleet Enrollment: ${FLEET_ENROLLMENT_TOKEN}

Nginx Proxy Manager Credentials:
-----------------------------
Email: admin@${BASE_DOMAIN}
Password: ${NPM_ADMIN_PASSWORD}

Domains:
-------
Kibana: ${KIBANA_DOMAIN}
Fleet Server: ${FLEET_DOMAIN}

Cloudflare Tunnel:
----------------
Tunnel ID: ${TUNNEL_ID}
Tunnel Name: ${TUNNEL_NAME}
EOL

echo -e "\n${GREEN}Credentials have been saved to credentials.txt${NC}" 