#!/bin/bash -x

ROOST_DIR=/var/tmp/Roost
ROOST_BIN="${ROOST_DIR}/bin"
ROOST_LOG="${ROOST_DIR}/logs"
exec &> >(tee -a "${ROOST_LOG}/roostEnterprise.log")

# keep it in sync with bucket version - preferable
# ROOST_VER=$(cat /var/tmp/Roost/roost.json | jq .desired_version)
DEFAULT_VER=${ROOST_VER:-v1.1.0}

init() {
  set -x
}

usage() { echo "
Usage: 
$0 [-i <install cmd>] [-c <config.json>]" 1>&2; }

compulsory_options() { echo "
compulsory options:
  Option            Description                                                 Usage
    -i              install cmd [all,stun,roostai,gpt]                          -i 'all'
    -c              config file                                                 -c 'main-config.json'
" 1>&2; }

PUBLIC_IP=$(curl -s ifconfig.me)

other_options() { echo "
other options:
  Option            Description                                                 Usage
    -h              help                                                        -h
    -e              RoostAI endPoint                                            -e '$PUBLIC_IP:443'
    -d              To pull the from dev                                        -d '1'
    -a              App Name                                                    -a 'roost'
" 1>&2; }

options() {
    compulsory_options
    other_options
}

expose_docker_on_port() {
  grep "${PUBLIC_IP}:5002" /etc/docker/daemon.json
  if [ $? -eq 0 ]; then
    return
  fi

  grep "tcp" /etc/docker/daemon.json
  tcp_stat=$?

  # grep "insecure-registries" /etc/docker/daemon.json
  grep "cgroupdriver" /etc/docker/daemon.json
  registry_stat=$?
  if [ $tcp_stat -ne 0 -o $registry_stat -ne 0 ]; then
    sudo touch /etc/docker/daemon.json
    cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "hosts": ["tcp://0.0.0.0:5000", "unix:///var/run/docker.sock"]
}
EOF
  # "insecure-registries" : ["$PUBLIC_IP:5002", "local-registry:5002"],
  fi  
  sudo mkdir -p /etc/systemd/system/docker.service.d
cat <<EOF | sudo tee /etc/systemd/system/docker.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
EOF
  sudo systemctl daemon-reload
  echo "Daemon reloaded"
  sleep 5
  sudo systemctl restart docker
}

install_docker(){
    docker_out=$(sudo systemctl status docker)
    docker_status=$?
    if [ $docker_status -ne 0 ]; then
        if [ ! -f  /etc/apt/trusted.gpg.d/docker.gpg ]; then
          sudo apt-key export 0EBFCD88 | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
          sudo apt-key export EFE21092 | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/cdimage.gpg
          sudo apt-key export 991BC93C | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/ftpmaster.gpg
	  sudo apt-key export A3219F7B | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/hashicorp.gpg
	  sudo apt-key export 579E5EB5 | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/buildpacks.gpg
        fi
        sudo apt-get update -y
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -     
        sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
        sudo apt-get update -y     
        apt-cache policy docker-ce     
        sudo apt-get install -y docker-ce    
        # sudo systemctl status docker
    fi
    # sudo usermod -aG docker ubuntu
    sudo usermod -aG docker $(whoami)
    if [ ${ECS_MODE} == true ]; then
      expose_docker_on_port
    fi
}

install_nginx(){
    nginx_out=$(nginx -v >/dev/null 2>&1)
    nginx_status=$?
    if [ $nginx_status -ne 0 ]; then
        sudo apt-get update -y
        sudo apt-get install -y nginx
    fi
}

install_docker_compose(){
    docker_compose_out=$(docker-compose -v >/dev/null 2>&1)
    docker_compose_status=$?
    if [ $docker_compose_status -ne 0 ]; then
        echo "install docker compose"
        sudo curl -sL "https://github.com/docker/compose/releases/download/v2.14.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi
}

install_jq(){
    sudo apt-get update -y
    sudo apt-get install -y jq
}

# check prereqs binaries
check_prereqs_bin(){
    install_jq
    install_docker
    install_nginx
    install_docker_compose
}

read_and_check_env_file(){
    # echo $fileContent
    validateFile=$(cat $configurationFilePath | jq . > /dev/null)
    validateFileOutput=$?
    if [ $validateFileOutput -eq 4 ]; then
        exit;
    fi
    fileContent=$(cat $configurationFilePath)
    isFileRight=true

    # Client Config
    ENTERPRISE_NAME=$(echo $fileContent | jq -r '.enterprise_name')
    EAAS_SERVER_IP=$(echo $fileContent | jq -r '.roostgpt_server_ip // .eaas_server_ip')
    EAAS_SERVER_KEY_PATH=$(echo $fileContent | jq -r '.roostgpt_server_pem_key // .eaas_server_pem_key')
    EAAS_SERVER_USERNAME=$(echo $fileContent | jq -r '.roostgpt_server_username // .eaas_server_username')
    JUMPHOST_IP=$(echo $fileContent | jq -r '.jumphost_ip')
    ENTERPRISE_LOGO=$(echo $fileContent | jq -r '.enterprise_logo')
    ENTERPRISE_EMAIL_DOMAIN=$(echo $fileContent | jq -r '.enterprise_email_domain')
    ENTERPRISE_DNS=$(echo $fileContent | jq -r '.enterprise_dns')
    # REMOTE_CONSOLE_PROXY=$(echo $fileContent | jq -r '.remote_console_proxy')
    ADMIN_EMAIL=$(echo $fileContent | jq -r '.admin_email')
    
    # Email Config
    EMAIL_SENDER=$(echo $fileContent | jq -r '.email_sender')
    EMAIL_SENDER_PASS=$(echo $fileContent | jq -r '.email_sender_pass')
    EMAIL_SMTP=$(echo $fileContent | jq -r '.email_smtp_host')
    EMAIL_SMTP_PORT=$(echo $fileContent | jq -r '.email_smtp_port')
    # EMAIL_SMTP_INSECURE=$(echo $fileContent | jq -r '.email_smtp_insecure')
   
    # Other Config
    LICENSE_KEY=$(echo $fileContent | jq -r '.license_key')
    JWT_SECRET=$(echo $fileContent | jq -r '.ENV_SERVER.JWT_SECRET')
    AUTH_KEY=$(echo $fileContent | jq -r '.ENV_SERVER.AUTH_KEY')
    DEFAULT_PORT=$(echo $fileContent | jq -r '.ENV_SERVER.DEFAULT_PORT // 3000')


    ENABLE_SALESFORCE=$(echo $fileContent | jq -r '.enable_salesforce')
    ECS_MODE=$(echo $fileContent | jq -r '.ecs_mode')
    ENABLE_JUMPHOST=$(echo $fileContent | jq -r '.enable_jumphost')
    ENABLE_EAAS=$(echo $fileContent | jq -r '.enable_eaas')
    USE_NO_AUTH_ENABLED=$(echo $fileContent | jq -r '.use_no_auth')
    USE_AS_ROOST_CLOUD_SERVER_ENABLED=$(echo $fileContent | jq -r '.use_as_roost_cloud_server')
    GPT_ONLY_ENABLED=$(echo $fileContent | jq -r '.gpt_only')
    if [ ${install} == "gpt" ]; then
      GPT_ONLY_ENABLED=true
    fi
    # USE_IP_ADDRESS_ENABLED=$(echo $fileContent | jq -r '.use_ip_address')
    USE_ROOST_DEV_ENABLED=$(echo $fileContent | jq -r '.use_roost_dev')
    # IS_HTTPS_ENABLED=$(echo $fileContent | jq -r '.is_https_enabled')
    # IS_LOAD_BALANCER=$(echo $fileContent | jq -r '.load_balancer')

    IS_HTTPS_ENABLED=true
    ENTERPRISE_CERTIFICATE_PATH=$(echo $fileContent | jq -r '.enterprise_ssl_certificate_path')
    ENTERPRISE_CERTIFICATE_KEY_PATH=$(echo $fileContent | jq -r '.enterprise_ssl_certificate_key_path')
    if [ -z "$ENTERPRISE_CERTIFICATE_PATH" ] || [ "$ENTERPRISE_CERTIFICATE_PATH" = null ]; then
      ENTERPRISE_CERTIFICATE_PATH="$ROOST_DIR/certs/server.cer"
    fi
    if [ -z "$ENTERPRISE_CERTIFICATE_KEY_PATH" ] || [ "$ENTERPRISE_CERTIFICATE_KEY_PATH" = null ]; then
      ENTERPRISE_CERTIFICATE_KEY_PATH="$ROOST_DIR/certs/server.key"
    fi

    # Auth Config
    GITHUB_CLIENT_ID=$(echo $fileContent | jq -r '.ENV_SERVER.GITHUB_CLIENT_ID')
    GITHUB_CLIENT_SECRET=$(echo $fileContent | jq -r '.ENV_SERVER.GITHUB_CLIENT_SECRET')
    GOOGLE_CLIENT_ID=$(echo $fileContent | jq -r '.ENV_SERVER.GOOGLE_CLIENT_ID')
    GOOGLE_CLIENT_SECRET=$(echo $fileContent | jq -r '.ENV_SERVER.GOOGLE_CLIENT_SECRET')
    LINKEDIN_CLIENT_ID=$(echo $fileContent | jq -r '.ENV_SERVER.LINKEDIN_CLIENT_ID')
    LINKEDIN_CLIENT_SECRET=$(echo $fileContent | jq -r '.ENV_SERVER.LINKEDIN_CLIENT_SECRET')
    AZURE_CLIENT_ID=$(echo $fileContent | jq -r '.ENV_SERVER.AZURE_CLIENT_ID')
    AZURE_TENANT_ID=$(echo $fileContent | jq -r '.ENV_SERVER.AZURE_TENANT_ID')
    AZURE_CLIENT_SECRET=$(echo $fileContent | jq -r '.ENV_SERVER.AZURE_CLIENT_SECRET')
    OKTA_CLIENT_ISSUER=$(echo $fileContent | jq -r '.ENV_SERVER.OKTA_CLIENT_ISSUER')
    OKTA_CLIENT_ID=$(echo $fileContent | jq -r '.ENV_SERVER.OKTA_CLIENT_ID')
    OKTA_CLIENT_SECRET=$(echo $fileContent | jq -r '.ENV_SERVER.OKTA_CLIENT_SECRET')    
    AZURE_ADFS_CLIENT_ISSUER=$(echo $fileContent | jq -r '.ENV_SERVER.AZURE_ADFS_CLIENT_ISSUER')
    AZURE_ADFS_CLIENT_ID=$(echo $fileContent | jq -r '.ENV_SERVER.AZURE_ADFS_CLIENT_ID')
    AZURE_ADFS_CLIENT_SECRET=$(echo $fileContent | jq -r '.ENV_SERVER.AZURE_ADFS_CLIENT_SECRET')  
    AUTH0_CLIENT_ISSUER=$(echo $fileContent | jq -r '.ENV_SERVER.AUTH0_CLIENT_ISSUER')
    AUTH0_CLIENT_ID=$(echo $fileContent | jq -r '.ENV_SERVER.AUTH0_CLIENT_ID')
    AUTH0_CLIENT_SECRET=$(echo $fileContent | jq -r '.ENV_SERVER.AUTH0_CLIENT_SECRET')  
    PING_FEDERATE_CLIENT_ISSUER=$(echo $fileContent | jq -r '.ENV_SERVER.PING_FEDERATE_CLIENT_ISSUER')
    PING_FEDERATE_CLIENT_ID=$(echo $fileContent | jq -r '.ENV_SERVER.PING_FEDERATE_CLIENT_ID')
    PING_FEDERATE_CLIENT_SECRET=$(echo $fileContent | jq -r '.ENV_SERVER.PING_FEDERATE_CLIENT_SECRET')
    
    # DB config
    IS_OWN_SQL=$(echo $fileContent | jq -r '.is_own_sql // false')
    DB_HOST=$(echo $fileContent | jq -r '.ENV_DATABASE.DB_HOST')
    DB_HOST_TYPE=$(echo $fileContent | jq -r 'if .ENV_DATABASE.DB_HOST_TYPE | IN("postgres","mysql") then .ENV_DATABASE.DB_HOST_TYPE else "mysql" end')
    DB_PORT=$(echo $fileContent | jq -r '.ENV_DATABASE.DB_PORT')
    DB_USERNAME=$(echo $fileContent | jq -r '.ENV_DATABASE.DB_USERNAME')
    DB_PASSWORD=$(echo $fileContent | jq -r '.ENV_DATABASE.DB_PASSWORD')
    DB_ROOT_PASSWORD=$(echo $fileContent | jq -r '.ENV_DATABASE.DB_ROOT_PASSWORD')
    # DB_PASSWORD_ARN=$(echo $fileContent | jq -r '.ENV_DATABASE.DB_PASSWORD_ARN')
    DB_SCHEMA_NAME=$(echo $fileContent | jq -r '.ENV_DATABASE.DB_SCHEMA_NAME')

    #########################################

    ([[ -z "$ENTERPRISE_NAME" ]] || [[ "$ENTERPRISE_NAME" = null ]]) && { echo "Add enterprise_name in env file"; isFileRight=false ;}
    ([[ -z "$ENTERPRISE_DNS" ]] || [[ "$ENTERPRISE_DNS" = null ]]) && { echo "Add enterprise_dns in env file"; isFileRight=false ;}
    ([[ -z "$ADMIN_EMAIL" ]] || [[ "$ADMIN_EMAIL" = null ]]) && { echo "Add admin_email in env file"; isFileRight=false ;}

    if [[ -z "$EAAS_SERVER_IP" ]] || [[ "$EAAS_SERVER_IP" = null ]]; then EAAS_SERVER_IP="" ; fi
    if [[ -z "$EAAS_SERVER_KEY_PATH" ]] || [[ "$EAAS_SERVER_KEY_PATH" = null ]]; then EAAS_SERVER_KEY_PATH="" ; fi
    if [[ -z "$EAAS_SERVER_USERNAME" ]] || [[ "$EAAS_SERVER_USERNAME" = null ]]; then EAAS_SERVER_USERNAME="" ; fi
    if [[ -z "$JUMPHOST_IP" ]] || [[ "$JUMPHOST_IP" = null ]]; then JUMPHOST_IP="" ; fi
    if [[ -z "$ENTERPRISE_LOGO" ]] || [[ "$ENTERPRISE_LOGO" = null ]]; then ENTERPRISE_LOGO="" ; fi
    if [[ -z "$ENTERPRISE_EMAIL_DOMAIN" ]] || [[ "$ENTERPRISE_EMAIL_DOMAIN" = null ]]; then ENTERPRISE_EMAIL_DOMAIN="" ; fi

    ([[ -z "$ECS_MODE" ]] || [[ "$ECS_MODE" = null ]]) && { ECS_MODE=false ;}
    ([[ -z "$ENABLE_EAAS" ]] || [[ "$ENABLE_EAAS" = null ]]) && { ENABLE_EAAS=true ;}
    ([[ -z "$ENABLE_JUMPHOST" ]] || [[ "$ENABLE_JUMPHOST" = null ]]) && { ENABLE_JUMPHOST=false ;}

    if [[ ! -z "$USE_AS_ROOST_CLOUD_SERVER_ENABLED" && $USE_AS_ROOST_CLOUD_SERVER_ENABLED = true ]]; then
      USE_AS_ROOST_CLOUD_SERVER=true
    else
      USE_AS_ROOST_CLOUD_SERVER=false
    fi

    #########################################

    ([[ -z "$IS_HTTPS_ENABLED" ]] || [[ "$IS_HTTPS_ENABLED" = null ]]) && { echo "Add is_https_enabled in env file"; isFileRight=false ;}
    ([[ -z "$ENTERPRISE_CERTIFICATE_PATH" ]] || [[ "$ENTERPRISE_CERTIFICATE_PATH" = null ]]) && ([[ "$IS_HTTPS_ENABLED" = true ]]) && { echo "Add enterprise_ssl_certificate_path in env file"; isFileRight=false ;}
    if [[ "$IS_HTTPS_ENABLED" = true ]] && [ ! -s "$ENTERPRISE_CERTIFICATE_PATH" ]; then
      echo "File at enterprise_ssl_certificate_path is missing"
      isFileRight=false
    fi   
    ([[ -z "$ENTERPRISE_CERTIFICATE_KEY_PATH" ]] || [[ "$ENTERPRISE_CERTIFICATE_KEY_PATH" = null ]]) && ([[ "$IS_HTTPS_ENABLED" = true ]]) && { echo "Add enterprise_ssl_certificate_key_path in env file"; isFileRight=false ;}
    if [[ "$IS_HTTPS_ENABLED" = true ]] && [ ! -s "$ENTERPRISE_CERTIFICATE_KEY_PATH" ]; then
      echo "File at enterprise_ssl_certificate_key_path is missing"
      isFileRight=false
    fi

    #########################################

    if [[ -z "$IS_OWN_SQL" ]] || [[ "$IS_OWN_SQL" = null ]]; then
	    IS_OWN_SQL="false"
    fi
    ([[ -z "$DB_SCHEMA_NAME" ]] || [[ "$DB_SCHEMA_NAME" = null ]]) && { DB_SCHEMA_NAME="roostio" ;}

    if [[ "$IS_OWN_SQL" = false ]]; then
      if ([[ -z "$DB_PASSWORD" ]] || [[ "$DB_PASSWORD" = null ]]); then
        DB_PASSWORD="Roost.io"
      fi
      if ([[ -z "$DB_ROOT_PASSWORD" ]] || [[ "$DB_ROOT_PASSWORD" = null ]]); then
        # && { echo "Add DB_ROOT_PASSWORD in env file"; isFileRight=false ;}
        # Set the Root password same as the db password
        DB_ROOT_PASSWORD=$DB_PASSWORD
      fi
      DB_HOST="127.0.0.1"
      DB_PORT=3306
      DB_USERNAME="root"
      DB_PASSWORD=$DB_PASSWORD
      DB_SCHEMA_NAME="roostio"

      if [[ "$DB_HOST_TYPE" = "postgres" ]]; then
        DB_HOST="127.0.0.1"
        DB_PORT=5432
        DB_USERNAME="postgres"
        DB_PASSWORD=$DB_PASSWORD
        DB_SCHEMA_NAME="roostio"
      fi

    else
      ([[ -z "$DB_HOST" ]] || [[ "$DB_HOST" = null ]]) && { echo "Add DB_HOST in env file"; isFileRight=false ;}
      ([[ -z "$DB_PORT" ]] || [[ "$DB_PORT" = null ]]) && { echo "Add DB_PORT in env file"; isFileRight=false ;}
      ([[ -z "$DB_USERNAME" ]] || [[ "$DB_USERNAME" = null ]]) && { echo "Add DB_USERNAME in env file"; isFileRight=false ;}
      ([[ -z "$DB_PASSWORD" ]] || [[ "$DB_PASSWORD" = null ]]) && { echo "Add DB_PASSWORD in env file"; isFileRight=false ;}
    fi

    #########################################

    if [[ -z "$EMAIL_SENDER" ]] || [[ "$EMAIL_SENDER" = null ]]; then
	    EMAIL_SENDER=""
    fi

    if [[ -z "$EMAIL_SENDER_PASS" ]] || [[ "$EMAIL_SENDER_PASS" = null ]]; then
	    EMAIL_SENDER_PASS=""
    fi

    if [[ -z "$EMAIL_SMTP" ]] || [[ "$EMAIL_SMTP" = null ]]; then
	    EMAIL_SMTP=""
    fi

    if [[ -z "$EMAIL_SMTP_PORT" ]] || [[ "$EMAIL_SMTP_PORT" = null ]]; then
	    EMAIL_SMTP_PORT=""
    fi

    if [[ ! -z "$EMAIL_SENDER" ]] &&  [[ ! -z "$EMAIL_SENDER_PASS" ]] ; then
	    EMAIL_SENDER_PRESENT=true
    else
      EMAIL_SENDER_PRESENT=false
    fi

    #########################################

    if [[ -z "$LICENSE_KEY" ]] || [[ "$LICENSE_KEY" = null ]]; then LICENSE_KEY="" ; fi

    if [[ -z "$AUTH_KEY" ]] || [[ "$AUTH_KEY" = null ]]; then
      AUTH_KEY="06b5e496f8f53139de7d2cc03b1e71ce" # hard-coded for now need to put logic to random generate; think
    fi

    if [[ -z "$DEFAULT_PORT" ]] || [[ "$DEFAULT_PORT" = null ]]; then
	    DEFAULT_PORT=3000
    fi
    ([[ -z "$DEFAULT_PORT" ]] || [[ "$DEFAULT_PORT" = null ]]) && { echo "Add DEFAULT_PORT in env file"; isFileRight=false ;}
    ([[ "$DEFAULT_PORT" = 4200 ]]) && { echo "Use different DEFAULT_PORT than 4200 in env file"; isFileRight=false ;}

    if [[ -z "$JWT_SECRET" ]] || [[ "$JWT_SECRET" = null ]]; then
	    JWT_SECRET="32-character-secure-long-secret"
    fi
    ([[ -z "$JWT_SECRET" ]] || [[ "$JWT_SECRET" = null ]]) && { echo "Add JWT_SECRET in env file"; isFileRight=false ;}

    #########################################

    ([[ -z "$GITHUB_CLIENT_ID" ]] || [[ "$GITHUB_CLIENT_ID" = null ]]) && { githubLogin=false ;}
    ([[ -z "$GOOGLE_CLIENT_ID" ]] || [[ "$GOOGLE_CLIENT_ID" = null ]]) && { googleLogin=false ;}
    ([[ -z "$LINKEDIN_CLIENT_ID" ]] || [[ "$LINKEDIN_CLIENT_ID" = null ]]) && { linkedinLogin=false ;}
    ([[ -z "$AZURE_CLIENT_ID" ]] || [[ "$AZURE_CLIENT_ID" = null ]]) && { azureLogin=false ;}
    ([[ -z "$OKTA_CLIENT_ISSUER" ]] || [[ "$OKTA_CLIENT_ISSUER" = null ]]) && { oktaLogin=false ;}
    ([[ -z "$OKTA_CLIENT_ID" ]] || [[ "$OKTA_CLIENT_ID" = null ]]) && { oktaLogin=false ;}
    ([[ -z "$AZURE_ADFS_CLIENT_ISSUER" ]] || [[ "$AZURE_ADFS_CLIENT_ISSUER" = null ]]) && { azureAdfsLogin=false ;}
    ([[ -z "$AZURE_ADFS_CLIENT_ID" ]] || [[ "$AZURE_ADFS_CLIENT_ID" = null ]]) && { azureAdfsLogin=false ;}
    ([[ -z "$AUTH0_CLIENT_ISSUER" ]] || [[ "$AUTH0_CLIENT_ISSUER" = null ]]) && { auth0Login=false ;}
    ([[ -z "$AUTH0_CLIENT_ID" ]] || [[ "$AUTH0_CLIENT_ID" = null ]]) && { auth0Login=false ;}
    ([[ -z "$PING_FEDERATE_CLIENT_ISSUER" ]] || [[ "$PING_FEDERATE_CLIENT_ISSUER" = null ]]) && { pingFederateLogin=false ;}
    ([[ -z "$PING_FEDERATE_CLIENT_ID" ]] || [[ "$PING_FEDERATE_CLIENT_ID" = null ]]) && { pingFederateLogin=false ;}

    if [[ ! -z "$USE_NO_AUTH_ENABLED" && $USE_NO_AUTH_ENABLED = true ]]; then
      USE_NO_AUTH=true
    else
      USE_NO_AUTH=false
    fi

    if [[ ! -z "$GPT_ONLY_ENABLED" && $GPT_ONLY_ENABLED = true ]]; then
      GPT_ONLY=true
      USE_NO_AUTH=true
    else
      GPT_ONLY=false
    fi

    ( [[ $githubLogin = false ]] && 
      [[ $azureLogin = false ]] && 
      [[ $linkedinLogin = false ]] && 
      [[ $oktaLogin = false ]] && 
      [[ $googleLogin = false ]] && 
      [[ $azureAdfsLogin = false ]] && 
      [[ $auth0Login = false ]] && 
      [[ $pingFederateLogin = false ]] && 
      [[ $USE_NO_AUTH = false ]] 
    )  && { echo "Add atleast one third party client id"; isFileRight=false ;}

    #########################################

    # if [[ ! -z "$USE_IP_ADDRESS_ENABLED" && $USE_IP_ADDRESS_ENABLED = true ]]; then
    #   USE_IP_ADDRESS=true
    # else
    #   USE_IP_ADDRESS=false
    # fi

    if [[ ! -z "$USE_ROOST_DEV_ENABLED" && $USE_ROOST_DEV_ENABLED = true ]]; then
      USE_ROOST_DEV=true
      DEV=1
    else
      USE_ROOST_DEV=false
    fi
    if [ ! -z "$DEV" -a "$DEV" == "1" ]; then
      USE_ROOST_DEV=true
    fi

    #########################################

    # z=(`echo "$ENTERPRISE_NAME" | tr '[:upper:]' '[:lower:]'`)
    # APP_NAME=$(echo $(echo $z | sed 's/[^0-9a-zA-Z_]/_/g') | sed 's/_\{2,\}/_/g')
    z=(`echo "$ENTERPRISE_NAME" | tr -sc '[:alnum:]' '_' | sed 's/^_\(.*\)/\1/' | sed 's/\(.*\)_$/\1/' `)
    APP_NAME=$(echo $z)
    echo $APP_NAME
    ENT_DNS="$ENTERPRISE_DNS:443"
#    if [[ ! -z "$USE_IP_ADDRESS_ENABLED" && $USE_IP_ADDRESS_ENABLED = true ]]; then
#      ENT_DNS="$PUBLIC_IP:443"
#    fi
    if [[ ! -z "$isFileRight" && $isFileRight = false ]]; then
        echo "Please update the config file";
        exit 1;
    fi
    if [[ ! -z "$IS_HTTPS_ENABLED" && $IS_HTTPS_ENABLED = true ]]; then
        CONTROLPLANE_URL="https://$ENTERPRISE_DNS"
        ENT_SERVER="$ENTERPRISE_DNS:443"
    else    
        CONTROLPLANE_URL="http://$ENTERPRISE_DNS"
        ENT_SERVER="$ENTERPRISE_DNS:80"
    fi

    # if [[ ! -z "$REMOTE_CONSOLE_PROXY" && $REMOTE_CONSOLE_PROXY = null ]]; then
       REMOTE_CONSOLE_PROXY="$ENTERPRISE_DNS"
    # fi

    if [[ ! -z "$ENABLE_SALESFORCE" && $ENABLE_SALESFORCE = true ]]; then
      ENABLE_SALESFORCE=true
    else
      ENABLE_SALESFORCE=false
    fi
   

    DB_SCHEMA_NAME=${DB_SCHEMA_NAME:-"roostio"}
    mkdir -p ${ROOST_DIR}/.roost
    cat > ${ROOST_DIR}/.roost/approostai.env << EOF
REACT_APP_API_HOST="${CONTROLPLANE_URL}/api"
REACT_APP_REDIRECT_URI="${CONTROLPLANE_URL}/login"
REACT_APP_ENTERPRISE_LOGO="${ENTERPRISE_LOGO}"
REACT_APP_REMOTE_CONSOLE_PROXY="https://${REMOTE_CONSOLE_PROXY}"

REACT_APP_GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID"
REACT_APP_AZURE_CLIENT_ID="$AZURE_CLIENT_ID"
REACT_APP_AZURE_TENANT_ID="$AZURE_TENANT_ID"
REACT_APP_GITHUB_CLIENT_ID="$GITHUB_CLIENT_ID"
REACT_APP_LINKEDIN_CLIENT_ID="$LINKEDIN_CLIENT_ID"
REACT_APP_OKTA_CLIENT_ISSUER="$OKTA_CLIENT_ISSUER"
REACT_APP_OKTA_CLIENT_ID="$OKTA_CLIENT_ID"
REACT_APP_AZURE_ADFS_CLIENT_ISSUER="$AZURE_ADFS_CLIENT_ISSUER"
REACT_APP_AZURE_ADFS_CLIENT_ID="$AZURE_ADFS_CLIENT_ID"
REACT_APP_AUTH0_CLIENT_ISSUER="$AUTH0_CLIENT_ISSUER"
REACT_APP_AUTH0_CLIENT_ID="$AUTH0_CLIENT_ID"
REACT_APP_PING_FEDERATE_CLIENT_ISSUER="$PING_FEDERATE_CLIENT_ISSUER"
REACT_APP_PING_FEDERATE_CLIENT_ID="$PING_FEDERATE_CLIENT_ID"

REACT_APP_COOKIE_SECURE=$IS_HTTPS_ENABLED
REACT_APP_COOKIE_DOMAIN="$ENTERPRISE_DNS"

REACT_APP_ROOST_VER="${ROOST_VER:-$DEFAULT_VER}"
REACT_APP_DB_VER="${ROOST_VER:-$DEFAULT_VER}"

REACT_APP_EMAIL_SENDER_PRESENT=$EMAIL_SENDER_PRESENT
REACT_APP_IS_DEPLOYED_IN_ECS=$ECS_MODE
REACT_APP_ONLY_ROOSTGPT=$GPT_ONLY
REACT_APP_NO_AUTH=$USE_NO_AUTH
EOF

    if [ $IS_OWN_SQL == false ]; then
      cat > ${ROOST_DIR}/.roost/db.env << EOF
MYSQL_ROOT_PASSWORD=$DB_PASSWORD
MYSQL_DATABASE=$DB_SCHEMA_NAME
EOF
    fi

    if [ $IS_OWN_SQL == false ] && [ "$DB_HOST_TYPE" == "postgres" ]; then
      cat > ${ROOST_DIR}/.roost/db.env << EOF
POSTGRES_PASSWORD=$DB_PASSWORD
POSTGRES_USER=$DB_USERNAME
POSTGRES_DB=$DB_SCHEMA_NAME
EOF
    fi

    cat > ${ROOST_DIR}/.roost/server.env << EOF
NODE_ENV="production"
DEFAULT_PORT=$DEFAULT_PORT
API_HOST_URL="$CONTROLPLANE_URL/api"
LOGIN_REDIRECT_URL="$CONTROLPLANE_URL/login"
NODE_DOMAIN_OR_IP="$ENTERPRISE_DNS"

# Version Config
ROOST_VER="${ROOST_VER:-$DEFAULT_VER}"
DB_VER="${ROOST_VER:-$DEFAULT_VER}"

# Auth Config
GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID"
GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET"
AZURE_CLIENT_ID="$AZURE_CLIENT_ID"
AZURE_CLIENT_SECRET="$AZURE_CLIENT_SECRET"
AZURE_TENANT_ID="$AZURE_TENANT_ID"
GITHUB_CLIENT_ID="$GITHUB_CLIENT_ID"
GITHUB_CLIENT_SECRET="$GITHUB_CLIENT_SECRET"
LINKEDIN_CLIENT_ID="$LINKEDIN_CLIENT_ID"
LINKEDIN_CLIENT_SECRET="$LINKEDIN_CLIENT_SECRET"
OKTA_CLIENT_ISSUER="$OKTA_CLIENT_ISSUER"
OKTA_CLIENT_ID="$OKTA_CLIENT_ID"
OKTA_CLIENT_SECRET="$OKTA_CLIENT_SECRET"
AZURE_ADFS_CLIENT_ISSUER="$AZURE_ADFS_CLIENT_ISSUER"
AZURE_ADFS_CLIENT_ID="$AZURE_ADFS_CLIENT_ID"
AZURE_ADFS_CLIENT_SECRET="$AZURE_ADFS_CLIENT_SECRET"
AUTH0_CLIENT_ISSUER="$AUTH0_CLIENT_ISSUER"
AUTH0_CLIENT_ID="$AUTH0_CLIENT_ID"
AUTH0_CLIENT_SECRET="$AUTH0_CLIENT_SECRET"
PING_FEDERATE_CLIENT_ISSUER="$PING_FEDERATE_CLIENT_ISSUER"
PING_FEDERATE_CLIENT_ID="$PING_FEDERATE_CLIENT_ID"
PING_FEDERATE_CLIENT_SECRET="$PING_FEDERATE_CLIENT_SECRET"

# Client Config
ORG_NAME="$ENTERPRISE_NAME"
ORG_ADMIN_EMAIL="$ADMIN_EMAIL"
ORG_EMAIL_DOMAIN="$ENTERPRISE_EMAIL_DOMAIN"
ORG_APP_NAME="$APP_NAME"
JUMPHOST_SVC="$JUMPHOST_IP"
EAAS_SVC="$EAAS_SERVER_IP"
EAAS_SERVER_USERNAME="$EAAS_SERVER_USERNAME"
EAAS_SERVER_KEY_PATH="$EAAS_SERVER_KEY_PATH"

# DB Config
DB_HOST_TYPE="$DB_HOST_TYPE"
DB_HOST="$DB_HOST"
DB_PORT=$DB_PORT
DB_USERNAME="$DB_USERNAME"
DB_PASSWORD="$DB_PASSWORD"
DB_SCHEMA_NAME="$DB_SCHEMA_NAME"

# Email Config
EMAIL_SENDER="$EMAIL_SENDER"
EMAIL_SENDER_PASS="$EMAIL_SENDER_PASS"
EMAIL_SMTP="$EMAIL_SMTP"
EMAIL_SMTP_PORT="$EMAIL_SMTP_PORT"

# Other Config
LICENSE_KEY="$LICENSE_KEY"
JWT_SECRET="$JWT_SECRET"

ENABLE_SALESFORCE=$ENABLE_SALESFORCE
# USE_IP_ADDRESS=$USE_IP_ADDRESS
USE_ROOST_DEV=$USE_ROOST_DEV
ECS_MODE=$ECS_MODE
USE_NO_AUTH=$USE_NO_AUTH
USE_AS_ROOST_CLOUD_SERVER=$USE_AS_ROOST_CLOUD_SERVER

EOF

    if [ ${ECS_MODE} == true ]; then
      cat >> ${ROOST_DIR}/.roost/server.env << EOF
LOCAL_AUTH_KEY="LocalKey/$AUTH_KEY"
JUMPHOST_SVC=127.0.0.1
EAAS_SVC=127.0.0.1
EOF
    fi

    cat > ${ROOST_DIR}/.roost/jumphost.env << EOF
VERBOSE_LEVEL=4
JUMPHOST=true
RUN_AS_CONTAINER=true
ENT_SERVER="$ENTERPRISE_DNS"
ROOST_LOCAL_KEY=$AUTH_KEY
EOF

    cat > ${ROOST_DIR}/.roost/release.env << EOF
VERBOSE_LEVEL=4
ENT_SERVER=${ENTERPRISE_DNS}
AUTH_KEY=$AUTH_KEY
ROOST_VER="${ROOST_VER:-$DEFAULT_VER}"
EOF

    cat > ${ROOST_DIR}/.roost/aiServer.env << EOF
VERBOSE_LEVEL=4
ENT_SERVER=${ENTERPRISE_DNS}
ROOST_VER="${ROOST_VER:-$DEFAULT_VER}"
EOF

    cat > ${ROOST_DIR}/.roost/launcher.env << EOF
VERBOSE_LEVEL=4
ENT_SERVER=${ENTERPRISE_DNS}
AUTH_KEY=$AUTH_KEY
ROOST_VER="${ROOST_VER:-$DEFAULT_VER}"
EOF

if [ ${install} != "console-proxy" ]; then
  SERVER_NAME='server_name ~^(.+)$;'
#  if [ ${IS_LOAD_BALANCER} != true ]; then
#    SERVER_NAME="server_name $ENTERPRISE_DNS;
#  server_name $PUBLIC_IP;"
#  fi

  # if [ ${IS_LOAD_BALANCER} != true ]; then
  cat  > sysmon.conf << EOF

server { 
    listen 80; 
    $SERVER_NAME
    return 301 https://$ENTERPRISE_DNS\$request_uri;
}

server {
    listen                  443 ssl;
    $SERVER_NAME
    server_tokens           off;
    proxy_hide_header       X-Powered-By;

    keepalive_timeout       70;
    ssl_certificate         $ENTERPRISE_CERTIFICATE_PATH;
    ssl_certificate_key     $ENTERPRISE_CERTIFICATE_KEY_PATH;
    ssl_protocols           TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers             HIGH:!aNULL:!MD5;
    client_max_body_size    200M;

    location ~ /meta-data {
        return 403;
    }

    location ~ /BitKeeper {
        return 403;
    }

    location ~ /\. {
        return 403;
    }

    location / {
        if (\$host = "169.254.169.254") {
            return 403;
        }

        proxy_hide_header   Access-Control-Allow-Origin;
        proxy_hide_header   X-Powered-By;
        add_header          X-Frame-Options "SAMEORIGIN" ;
        add_header          X-Content-Type-Options nosniff;
        add_header          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

        proxy_set_header    X-Forwarded-For \$remote_addr;
        expires             1h;
        add_header          Cache-Control "public, no-transform";
        proxy_set_header    Host \$http_host;
        proxy_pass          http://127.0.0.1:4200;
    }

    location /proxy {
        rewrite             ^/proxy/?(.*) /\$1 break;
        proxy_set_header    X-Forwarded-For \$remote_addr;
        proxy_set_header    Host \$http_host;
        proxy_pass          http://127.0.0.1:3001;
        proxy_http_version  1.1;
        proxy_set_header    Upgrade \$http_upgrade;
        proxy_set_header    Connection upgrade;
    }

    location /api {
        proxy_hide_header   Access-Control-Allow-Origin;

        proxy_set_header    X-Forwarded-For \$remote_addr;
        proxy_set_header    Host \$http_host;
        proxy_pass          http://127.0.0.1:$DEFAULT_PORT;
        rewrite             ^/api/?(.*) /\$1 break;
    }
}
EOF
else
  cat  > sysmon.conf << EOF
server {
  listen 443 ssl;
  server_name $REMOTE_CONSOLE_PROXY;
  server_name $PUBLIC_IP;

  ssl_certificate $ENTERPRISE_CERTIFICATE_PATH;
  ssl_certificate_key $ENTERPRISE_CERTIFICATE_KEY_PATH;
  ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
  ssl_ciphers HIGH:!aNULL:!MD5;
  client_max_body_size 200M;

  location / {
    proxy_set_header   X-Forwarded-For \$remote_addr;
    proxy_set_header   Host \$http_host;
    proxy_pass         http://127.0.0.1:3001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection upgrade;
  }
}
EOF
fi
}

write_docker_compose(){

if [ $IS_OWN_SQL == false ]; then
    if [ "$DB_HOST_TYPE" == "postgres" ]; then
      sql="roostai_postgres_db:
      image: postgres:15.2
      env_file:
        - $ROOST_DIR/.roost/db.env
      ports:
        - \"5432:5432\"
      volumes:
        - $ROOST_DIR/postgres_data:/var/lib/postgresql/data
      restart: unless-stopped
  "
    else
      sql="roostai_mysql_db:
      image: zbio/roostai_mysql_db:\${DB_VER}
      env_file:
        - $ROOST_DIR/.roost/db.env
      ports:
        - \"3306:3306\"
      volumes:
        - $ROOST_DIR/roostai_mysql_data:/var/lib/mysql
      command: --bind-address=* --default-authentication-plugin=mysql_native_password
      restart: unless-stopped
  "
    fi
else
    sql=''
fi

if [ ${ENABLE_JUMPHOST} == true ]; then
  jump="roost_jumphost:
    image: zbio/roost-jump:\${JUMP_VER}
    network_mode: \"host\"
    env_file:
      - $ROOST_DIR/.roost/jumphost.env
    # ports:
    #  - \"60001:60001\"
    depends_on:
      - roostai_nest_server
    restart: unless-stopped
    volumes:
      - $ROOST_DIR:$ROOST_DIR
  "
else
  jump=''
fi

if [ $ECS_MODE == true ]; then
  eaas="${jump}roostai_eaas_app:
    image: zbio/roost-eaas:\${EAAS_VER}
    network_mode: \"host\"
    env_file:
      - $ROOST_DIR/.roost/release.env
    # ports:
    #   - \"60003:60003\"
    depends_on:
      - roostai_nest_server
    restart: unless-stopped
    volumes:
      - $ROOST_DIR:$ROOST_DIR
      - /var/run/docker.sock:/var/run/docker.sock
  "
else 
    eaas=''
fi

if [ $ECS_MODE == true ]; then
  gpt="roostai_gpt:
    image: zbio/roostai-server:\${EAAS_VER}
    network_mode: \"host\"
    env_file:
      - $ROOST_DIR/.roost/aiServer.env
    # ports:
    #   - \"60007:60007\"
    depends_on:
      - roostai_nest_server
    restart: unless-stopped
    volumes:
      - $ROOST_DIR:$ROOST_DIR
      - /var/run/docker.sock:/var/run/docker.sock
  "
else
    gpt=''
fi

if [ ${install} == "roost" ] && [ $ECS_MODE == true ]; then
  ec2Launcher="roost_ec2launcher:
    image: zbio/roost-launcher:\${ROOST_VER}
    network_mode: \"host\"
    env_file:
      - $ROOST_DIR/.roost/launcher.env
    depends_on:
      - roostai_nest_server
    restart: unless-stopped
    volumes:
      - $ROOST_DIR:$ROOST_DIR
      - /var/run/docker.sock:/var/run/docker.sock
  "
else
    ec2Launcher=''
fi

if [ ${install} == "stun" ]; then
    stun="roost_stun_svr:
    image: zbio/roost-stun-svr:v2
    ports:
      - \"2502:2502\"
    environment:
      - ROOST_IO_SVR=${ENT_DNS}
    restart: unless-stopped
  "
else
    stun=''
fi

    cat  > $ROOST_DIR/docker-compose.yaml << EOF
version: "3"

services:
  ${sql}${stun}${eaas}${ec2Launcher}${gpt}roostai_nest_server:
    image: zbio/roost-app:\${ROOST_VER}
    env_file:
      - $ROOST_DIR/.roost/server.env
    # ports:
    #   - "$DEFAULT_PORT:$DEFAULT_PORT"
    network_mode: "host"
    restart: unless-stopped
    volumes:
      - $ROOST_DIR:$ROOST_DIR
    # links:
    #   - "roostai_mysql_db:roostai_mysql_db"
    # depends_on:
    #   - roostai_mysql_db
  roostai_react_app:
    image: zbio/roost-web:\${REACTUI_VER}
    env_file:
      - $ROOST_DIR/.roost/approostai.env
    ports:
      - "4200:4200"
    depends_on:
      - roostai_nest_server
    restart: unless-stopped
  roost_console_proxy:
    image: zbio/roost-proxy:\${PROXY_VER}
    ports:
      - "3001:3001"
    restart: unless-stopped
EOF
}

write_docker_compose_console_proxy(){
IMAGE_TAG=${PROXY_VERSION:-latest}
    cat  > $ROOST_DIR/docker-compose.yaml << EOF
version: "3"

services:
  roost_console_proxy:
    image: zbio/roost-proxy:\${PROXY_VER}
    ports:
      - "3001:3001"
    restart: unless-stopped
EOF
}

apply_docker_compose(){
  write_docker_compose
  cd $ROOST_DIR
  echo "EAAS_VER=${EAAS_VER:-$DEFAULT_VER}" > .env
  echo "JUMP_VER=${JUMP_VER:-$DEFAULT_VER}" >> .env
  echo "ROOST_VER=${ROOST_VER:-$DEFAULT_VER}" >> .env
  echo "REACTUI_VER=${REACTUI_VER:-$ROOST_VER}" >> .env
  echo "PROXY_VER=${PROXY_VER:-$ROOST_VER}" >> .env
  # echo "DB_VER=${ROOST_VER:-$DEFAULT_VER}" >> .env
  # Fix the DB version for container to allow nestJS to apply SQL changes
  echo "DB_VER=v1.1.0" >> .env
  sudo docker-compose -f $ROOST_DIR/docker-compose.yaml pull
  sudo docker-compose -f $ROOST_DIR/docker-compose.yaml up -d --build --remove-orphans --force-recreate
  echo "docker-compose up: $?"
  sudo cp sysmon.conf /etc/nginx/conf.d/
  sudo /etc/init.d/nginx reload
  sudo systemctl status nginx
  nginx_out=$?
  if [ $nginx_out -ne 0 ]; then
    sudo systemctl start nginx
  fi
  if [ ! -z "$DEV" -a "$DEV" == "1" ]; then
      touch "${ROOST_DIR}/.dev"
  elif [ -f "${ROOST_DIR}/.dev" ]; then
      rm -f "${ROOST_DIR}/.dev"
  fi
}

xxapply_docker_compose_console_proxy(){
  write_docker_compose_console_proxy
  cd $ROOST_DIR
  sudo docker-compose -f $ROOST_DIR/docker-compose.yaml up -d --build --remove-orphans
  sudo cp sysmon.conf /etc/nginx/conf.d/
  sudo /etc/init.d/nginx reload
}

restart_docker_compose(){
  # write_docker_compose
  cd $ROOST_DIR
  CURR_VER=$(grep ROOST_VER .env | cut -f2 -d=)
  cp .env .env.bkp
  ROOST_VER=${ROOST_VER:-$DEFAULT_VER}
  echo "ROOST_VER=${ROOST_VER:-$DEFAULT_VER}" > .env
  echo "EAAS_VER=${EAAS_VER:-$DEFAULT_VER}" >> .env
  echo "JUMP_VER=${JUMP_VER:-$DEFAULT_VER}" >> .env
  cv=$(echo ${CURR_VER#v} | sed -e 's/.//g')
  dv=$(echo ${ROOST_VER#v} | sed -e 's/.//g')
  # compare ROOST_VER and CURR_VER
  # If downgrade then DB version remains stuck at current version
  if [ ${cv} -lt ${dv} ]; then
    # echo "DB_VER=${ROOST_VER:-$DEFAULT_VER}" >> .env
    echo "$cv is less than $dv"
  else
    # echo "DB_VER=${CURR_VER:-$DEFAULT_VER}" >> .env
    echo "$cv is not less than $dv"
  fi
  cat "$ROOST_DIR/.env"
  sudo docker-compose -f $ROOST_DIR/docker-compose.yaml pull
  if [ $? -ne 0 ]; then
    mv .env.bkp .env
  else
  #  ${ROOST_BIN}/${INSTALLER} --command=write --name=${ENTERPRISE_NAME} --entServer=${ENTERPRISE_DNS} \
  #   --currentVersion=${CURR_VER} --desiredVersion=${ROOST_VER}
    echo "{
 \""valid"\": true,
 \""name"\": \""${ENTERPRISE_NAME}"\",
 \""entserver"\": \""${ENTERPRISE_DNS}"\",
 \""current_version"\": \""${CURR_VER}"\",
 \""desired_version"\": \""${ROOST_VER}"\"
}" > ${ROOST_DIR}/roost.json

  fi
  sudo docker-compose -f $ROOST_DIR/docker-compose.yaml up -d --build --remove-orphans
  echo "docker-compose up: $?"
  if [ ! -z "$DEV" -a "$DEV" == "1" ]; then
      touch "${ROOST_DIR}/.dev"
  elif [ -f "${ROOST_DIR}/.dev" ]; then
      rm -f "${ROOST_DIR}/.dev"
  fi
}

#check prereqs web and db variables
check_prereqs_var(){
    if [ -z "$configurationFilePath" ]; then
        echo "ConfigFile path not provided; Look at $BASEDIR/main-config.json for template"
        exit
    fi
}

while getopts "i:c:e:a:d::h" o; do
    case "${o}" in
        i)
            install=${OPTARG}
            echo "option $install"
            ;;
        c)
            configurationFilePath=${OPTARG}
            if [ ! -s "$configurationFilePath" ]; then
                echo "File does not exist"
                exit
            fi
            ;;
        e)
            RoostIOServer=${OPTARG}
            echo "RoostAI endpoint=$RoostIOServer"
            ;;
        a)
            AppName=${OPTARG}
            echo "App Name=$AppName"
            ;;
        d)
            DEV=${OPTARG}
            if [ "$DEV" == "1" ];then
                echo "pulling from dev bucket"
                S3_CONFIG_URL=https://remote-roostdev.s3-us-west-1.amazonaws.com
            fi
            ;;

        h|*)
            usage
            options
            exit 1
            ;;
    esac
done

shift $((OPTIND-1))

if [ -z "${install}" ]; then
    usage
    compulsory_options
    exit 1
fi

set_defaults() {
  if [ -z "$RoostIOServer" ]; then
    RoostIOServer="${ENTERPRISE_DNS}:443"
  fi
}

docker_prune() {
  sudo docker container prune -f
  sudo docker image prune -f
}

check_disk_space() {
   disksizehome=`df -h / | awk 'int($5)>50'`
    if [ ! -z "$disksizehome" ];then
      echo "Partition "$1" has only "$4" free"
      echo "Initiating automated docker cleanup"
      docker_prune
    fi

    # disksizebackup=`df -h $ROOST_DIR/backup | awk 'int($5)>60'`
    # if [ ! -z "$disksizebackup" ] && [ -d "$ROOST_DIR/backup" ];then
    #   echo "Partition "$1" has only "$4" free"
    #   echo "Initiating backup cleanup"
    #   docker_prune
    # fi
}

roost_gpt() {
  check_disk_space
  check_prereqs_bin
  apply_docker_compose
}

roost_controlplane() {
  check_disk_space
  check_prereqs_bin
  apply_docker_compose
}

APP_NAME=""
ENT_DNS=""
ENT_SERVER=""

BASEDIR=$(dirname $0)
LOGS_DIR="${ROOST_DIR}/logs"
if [ ! -d "${LOGS_DIR}" ]; then
  mkdir -p "${LOGS_DIR}"
fi
# sudo chown -R ubuntu "${LOGS_DIR}"
sudo chown -R $(whoami) "${LOGS_DIR}"
INSTALLER="RoostInstaller"

cd $ROOST_DIR
install_jq
read_and_check_env_file
init
set_defaults

case ${install} in
    "roost")
      echo "install roost web, db, eaas and controlplane server"
      roost_controlplane
      ;;
    "gpt")
      echo "install roost web, db, gpt and controlplane server"
      roost_gpt
      ;;
   "stun") 
      echo "install stun"
      check_prereqs_stun
      install_stun
      ;;
    "roostai")
      echo "install roostai"
      roost_controlplane
      ;;
    "upd-roostai")
      echo "update roostai"
      check_prereqs_var
      restart_docker_compose
      ;;
    "console-proxy")
      echo "install console proxy"
      check_prereqs_var
      check_prereqs_bin
      apply_docker_compose_console_proxy
      ;;
    *)
      echo "Wrong argument.Argument must be either 'roost','eaas', 'stun' or 'roostai'".
      exit 1 # Command to come out of the program with status 1
      ;; 
esac 
cd -
