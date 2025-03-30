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

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo -e "${YELLOW}Creating .env file...${NC}"
    
    # Generate random passwords and tokens
    ELASTIC_PASSWORD=$(openssl rand -base64 32)
    KIBANA_PASSWORD=$(openssl rand -base64 32)
    FLEET_SERVER_TOKEN=$(openssl rand -base64 32)
    NPM_ADMIN_PASSWORD=$(openssl rand -base64 32)
    
    cat > .env << EOL
# Elastic Stack Configuration
ELASTIC_VERSION=${ELASTIC_VERSION}
ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
KIBANA_PASSWORD=${KIBANA_PASSWORD}
FLEET_SERVER_TOKEN=${FLEET_SERVER_TOKEN}
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
    echo -e "${GREEN}Created .env file with generated credentials.${NC}"
fi

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Create necessary directories
echo -e "${YELLOW}Creating necessary directories...${NC}"
mkdir -p data/elasticsearch
mkdir -p data/kibana
mkdir -p data/fleet
mkdir -p data/npm
mkdir -p cloudflared

# Set proper permissions
echo -e "${YELLOW}Setting proper permissions...${NC}"
chmod -R 777 data/elasticsearch

# Pull Docker images
echo -e "${YELLOW}Pulling Docker images...${NC}"
$DOCKER_COMPOSE_CMD pull

# Start Elasticsearch first to create service account
echo -e "${YELLOW}Starting Elasticsearch...${NC}"
$DOCKER_COMPOSE_CMD up -d elasticsearch

# Wait for Elasticsearch to be ready
echo -e "${YELLOW}Waiting for Elasticsearch to be ready...${NC}"
sleep 30

# Create Kibana service account and get token
echo -e "${YELLOW}Creating Kibana service account...${NC}"
KIBANA_SERVICE_TOKEN=$(docker exec elasticsearch /usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/kibana kibana-token | grep "SERVICE_TOKEN" | awk '{print $3}')

# Update .env with service account token
sed -i "s|KIBANA_PASSWORD=.*|KIBANA_SERVICE_TOKEN=${KIBANA_SERVICE_TOKEN}|" .env

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

echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "1. Access Nginx Proxy Manager at http://localhost:81"
echo -e "2. Create proxy hosts for Kibana and Fleet Server"
echo -e "3. Restart the services:"
echo -e "   $DOCKER_COMPOSE_CMD down && $DOCKER_COMPOSE_CMD up -d"

# Save the credentials to a file for reference
cat > credentials.txt << EOL
Elastic Stack Credentials:
------------------------
Username: elastic
Password: ${ELASTIC_PASSWORD}

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