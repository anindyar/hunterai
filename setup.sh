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

# Function to validate domain name
validate_domain() {
    local domain=$1
    # Updated regex to handle more valid domain formats
    if [[ $domain =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9](?:\.[a-zA-Z]{2,})+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Get domain name from user
while true; do
    read -p "Enter your domain name (e.g., example.com): " DOMAIN
    if validate_domain "$DOMAIN"; then
        break
    else
        echo -e "${RED}Invalid domain name. Please try again.${NC}"
    fi
done

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo -e "${YELLOW}Creating .env file...${NC}"
    
    # Generate random passwords and tokens
    ELASTIC_PASSWORD=$(openssl rand -base64 32)
    KIBANA_PASSWORD=$(openssl rand -base64 32)
    FLEET_SERVER_TOKEN=$(openssl rand -base64 32)
    NPM_ADMIN_PASSWORD=$(openssl rand -base64 32)
    
    # Create subdomains
    KIBANA_DOMAIN="kibana.${DOMAIN}"
    FLEET_DOMAIN="fleet.${DOMAIN}"
    
    cat > .env << EOL
# Elastic Stack Configuration
ELASTIC_VERSION=${ELASTIC_VERSION}
ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
KIBANA_PASSWORD=${KIBANA_PASSWORD}
FLEET_SERVER_TOKEN=${FLEET_SERVER_TOKEN}
FLEET_SERVER_HOST=${FLEET_DOMAIN}

# Cloudflare Configuration
CLOUDFLARE_TOKEN=your_cloudflare_token_here
CLOUDFLARE_DOMAIN=${DOMAIN}
KIBANA_DOMAIN=${KIBANA_DOMAIN}
FLEET_DOMAIN=${FLEET_DOMAIN}

# Nginx Proxy Manager Configuration
NPM_ADMIN_EMAIL=admin@${DOMAIN}
NPM_ADMIN_PASSWORD=${NPM_ADMIN_PASSWORD}
EOL
    echo -e "${GREEN}Created .env file with generated credentials.${NC}"
fi

# Create necessary directories
echo -e "${YELLOW}Creating necessary directories...${NC}"
mkdir -p data/elasticsearch
mkdir -p data/kibana
mkdir -p data/fleet
mkdir -p data/npm

# Set proper permissions
echo -e "${YELLOW}Setting proper permissions...${NC}"
chmod -R 777 data/elasticsearch

# Pull Docker images
echo -e "${YELLOW}Pulling Docker images...${NC}"
$DOCKER_COMPOSE_CMD pull

# Start the services
echo -e "${YELLOW}Starting services...${NC}"
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
echo -e "Email: admin@${DOMAIN}"
echo -e "Password: ${NPM_ADMIN_PASSWORD}"

echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "1. Log in to your Cloudflare Zero Trust dashboard"
echo -e "2. Create a new tunnel and copy the token"
echo -e "3. Update the CLOUDFLARE_TOKEN in the .env file"
echo -e "4. Create DNS records in Cloudflare for:"
echo -e "   - ${KIBANA_DOMAIN}"
echo -e "   - ${FLEET_DOMAIN}"
echo -e "5. Access Nginx Proxy Manager at http://localhost:81"
echo -e "6. Create proxy hosts for Kibana and Fleet Server"
echo -e "7. Restart the services:"
echo -e "   $DOCKER_COMPOSE_CMD down && $DOCKER_COMPOSE_CMD up -d" 