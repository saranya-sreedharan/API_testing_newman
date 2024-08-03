#!/bin/bash

# Colors for formatting
RED='\033[0;31m'    # Red colored text
GREEN='\033[0;32m'  # Green colored text
NC='\033[0m'        # Normal text

# Function to display error message and exit
display_error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Function to display success message
display_success() {
    echo -e "${GREEN}$1${NC}"
}

# Update package lists
sudo apt update || display_error "Failed to update package lists"

# Check if Docker is installed, if not install it
if ! command -v docker &> /dev/null; then
    display_success "Installing Docker..."
    sudo apt install docker.io -y || display_error "Failed to install Docker"
else
    display_success "Docker is already installed"
fi

# Create jenkins_data directory and Docker volume
read -p "Enter the absolute path to create jenkins_data directory: " jenkins_data_location
mkdir -p "$jenkins_data_location" || display_error "Failed to create jenkins_data directory"
sudo docker volume create jenkins_data || display_error "Failed to create Docker volume jenkins_data"
sudo docker volume create --driver local --opt type=none --opt device=/mnt/jenkins_data --opt o=bind jenkins_data || error_exit "Failed to create Docker volume jenkins_data."

# Set proper permissions for jenkins_data directory
sudo chown -R 1000:1000 "$jenkins_data_location" || display_error "Failed to set permissions for jenkins_data directory"

# Create Dockerfile
echo -e "
# Dockerfile
FROM jenkins/jenkins:lts

# Expose ports for Jenkins web UI and agent communication
EXPOSE 8080 50000

# Set up a volume to persist Jenkins data
VOLUME /var/jenkins_home

# Set up the default command to run Jenkins
CMD [\"java\", \"-jar\", \"/usr/share/jenkins/jenkins.war\"]" > Dockerfile || display_error "Failed to create Dockerfile"

# Build custom Jenkins image
sudo docker build -t my-custom-jenkins . || display_error "Failed to build custom Jenkins image"

# Run Jenkins container
sudo docker run -d -p 8080:8080 -p 50000:50000 -v "$jenkins_data_location:/var/jenkins_home" --name jenkins --restart always my-custom-jenkins || display_error "Failed to run Jenkins container"

# Wait for Jenkins to generate initial admin password
echo "Waiting for initial admin password..."
sleep 30

# Retrieve initial admin password
password=$(sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword) || display_error "Failed to retrieve initial admin password"

# Print initial admin password
display_success "Initial admin password: $password"

sleep 30

# Install necessary packages inside Jenkins container
sudo docker exec -u root jenkins apt-get update || display_error "Failed to update package lists inside Jenkins container"
sudo docker exec -u root jenkins apt-get install -y wget nano || display_error "Failed to install necessary packages inside Jenkins container"

# Get Jenkins container ID and IP address
CONTAINER_ID=$(sudo docker ps -aqf "name=jenkins")
CONTAINER_IP=$(sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_ID")

# Download Jenkins CLI JAR file
sudo docker exec -u root jenkins wget "http://$CONTAINER_IP:8080/jnlpJars/jenkins-cli.jar" || display_error "Failed to download Jenkins CLI JAR file"

# Restart Jenkins container
sudo docker restart jenkins || display_error "Failed to restart Jenkins container"

display_success "Initial admin password: $password"

echo -e "setup username and password for jenkins"

sleep 120

read -p "Enter Jenkins admin username: " username
read -sp "Enter Jenkins admin password: " password

sudo docker exec -u root jenkins java -jar jenkins-cli.jar -auth $username:$password -s http://$CONTAINER_IP:8080:8080/ install-plugin git
lab-plugin || error_exit "Failed to install GitLab plugin."

sudo docker exec -u root jenkins java -jar jenkins-cli.jar -auth $username:$password -s http://$CONTAINER_IP:8080/ install-plugin htmlpublisher || error_exit "Failed to install HTML publisher."


sudo docker exec -u root jenkins curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
sudo docker exec -u root jenkins apt-get install -y nodejs
sudo docker exec -u root jenkins apt-get install -y npm

sudo docker exec -u root jenkins npm -v
sudo docker exec -u root jenkins node -v

sudo docker exec -u root jenkins npm install -g newman
sudo docker exec -u root jenkins newman -v

echo -e "Create gitlab login credentails and token credential in jenkins"

sleep 120

CONTAINER_NAME="jenkins"
SCRIPT_PATH="/usr/share/jenkins/ref/init.groovy.d"
SCRIPT_NAME="custom-csp.groovy"
SCRIPT_CONTENT="System.setProperty('hudson.model.DirectoryBrowserSupport.CSP', \"\")"

# Create the script content
echo "$SCRIPT_CONTENT" > "$SCRIPT_NAME"

# Copy the script into the Jenkins container
sudo docker cp "$SCRIPT_NAME" "$CONTAINER_NAME":"$SCRIPT_PATH"/"$SCRIPT_NAME"

# Clean up: remove the local copy of the script
rm "$SCRIPT_NAME"

# Restart the Jenkins container to apply changes
sudo docker restart "$CONTAINER_NAME"

sudo docker exec -u root jenkins npm install -g newman-reporter-html
sudo docker exec -u root jenkins npm install -g newman-reporter-htmlextra

read -p "Enter project name : " project_name

# Define the job configuration XML content
JOB_CONFIG_XML=$(cat <<EOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.42">
  <actions/>
  <description></description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <org.jenkinsci.plugins.pipeline.modeldefinition.config.FolderConfig plugin="pipeline-model-definition@1.10.2">
      <dockerLabel></dockerLabel>
      <registry plugin="docker-commons@1.17"/>
      <registryCredentialId></registryCredentialId>
    </org.jenkinsci.plugins.pipeline.modeldefinition.config.FolderConfig>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps@2.90">
    <script>
    pipeline {
    agent any
    
    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', credentialsId: 'gitlab-login', url: 'https://gitlab.com/saruSaranya/api-testing_project.git'
            }
        }
        
        
        stage('Run API Tests') {
            steps {
                script {
                    sh 'newman run /var/jenkins_home/workspace/$project_name/mmdev2api.postman_collection.json -r htmlextra'
                }
            }
        }
    }
    
    post {
        always {
            publishHTML([allowMissing: false, alwaysLinkToLastBuild: false, keepAll: true, reportDir: 'newman', reportFiles: 'index.html', reportName: 'Newman Test Report', reportTitles: ''])
        }
    }
}
    </script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
  <!-- GitLab configuration -->
  <scm class="hudson.plugins.git.GitSCM" plugin="git@4.12.0">
    <configVersion>2</configVersion>
    <userRemoteConfigs>
      <hudson.plugins.git.UserRemoteConfig>
        <url>https://gitlab.com</url> 
        <credentialsId>glpat-2EtbzAKMa1csSM9eb7av</credentialsId> 
      </hudson.plugins.git.UserRemoteConfig>
    </userRemoteConfigs>
  </scm>
</flow-definition>
EOF
)

# Create the job configuration XML file
echo -e "${JOB_CONFIG_XML}" | sudo tee job_config.xml > /dev/null

# Get the container ID
CONTAINER_ID=$(sudo docker ps -aqf "name=jenkins")

# Extract the IP address of the container
CONTAINER_IP=$(sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_ID")

# Copy job_config.xml to Jenkins container
echo -e "${YELLOW}... Copying job_config.xml to Jenkins container....${NC}"
sudo docker cp job_config.xml "$CONTAINER_ID":/var/jenkins_home/ || { echo -e "${RED}Failed to copy job_config.xml to Jenkins container.${NC}"; exit 1; }

# Restart Jenkins container
echo -e "${YELLOW}... Restarting Jenkins container....${NC}"
sudo docker restart "$CONTAINER_ID" || { echo -e "${RED}Failed to restart Jenkins container.${NC}"; exit 1; }

sleep 30

# Create job
echo -e "${YELLOW}... Creating job API_Testing....${NC}"
sudo docker exec -i "$CONTAINER_ID" sh -c "java -jar jenkins-cli.jar -auth $username:$password -s http://$CONTAINER_IP:8080/ create-job $project_name < /var/jenkins_home/job_config.xml" || { echo -e "${RED}Failed to create job.${NC}"; exit 1; }
sleep 30

# List jobs
echo -e "${YELLOW}... Listing jobs....${NC}"
sudo docker exec -i "$CONTAINER_ID" sh -c "java -jar jenkins-cli.jar -auth $username:$password -s http://$CONTAINER_IP:8080/ list-jobs" || { echo -e "${RED}Failed to list jobs.${NC}"; exit 1; }

# Build the job
echo -e "${YELLOW}... Building job mn-serviceproviders-website....${NC}"
sudo docker exec -i "$CONTAINER_ID" sh -c "java -jar jenkins-cli.jar -auth $username:$password -s http://$CONTAINER_IP:8080/ build API_Testing" || { echo -e "${RED}Failed to build job.${NC}"; exit 1; }

echo -e "${YELLOW}Job created and built successfully.${NC}"