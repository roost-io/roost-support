#!/bin/bash -x

add_roost_user(){

  # Validates existing user UID 
  EXISTING_UID=$(id -u roost 2>/dev/null || echo "")
  if [ ! -z "$EXISTING_UID" ] && [ "$EXISTING_UID" != "$ROOST_UID" ]; then
    echo "ERROR: roost user exists with UID $EXISTING_UID, expected $ROOST_UID"
    exit 1
  fi

  # Ensure group exists with correct GID
  if ! getent group roost >/dev/null; then
    sudo groupadd -g ${ROOST_UID} roost
  fi

  # Ensure user exists with correct UID
  if ! id -u roost >/dev/null 2>&1; then
    sudo useradd -u ${ROOST_UID} -g ${ROOST_UID} -M -r -s /usr/sbin/nologin roost
  fi
}

ROOST_DIR=/var/tmp/Roost
ROOST_BIN="${ROOST_DIR}/bin"
ROOST_LOG="${ROOST_DIR}/logs"
ROOST_USER="roost"
ROOST_UID=10001

check_execution_context() {
  local current_uid=$(id -u)
    
  if [ "$current_uid" -eq 0 ]; then
      echo "Running as root - will delegate to roost user where appropriate"
      RUN_AS_ROOT=true
  elif [ "$current_uid" -eq "$ROOST_UID" ]; then
      echo "Running as roost user"
      RUN_AS_ROOT=false
  else
      echo "ERROR: This script must be run as root or roost user"
      echo "Current user: $(whoami) (UID: $current_uid)"
      exit 1
  fi
}

add_roost_user(){

  # Only root can add users
  if [ "$(id -u)" -ne 0 ]; then
      echo "Skipping user creation - not running as root"
      return 0
  fi
  
  # Validates existing user UID 
  local EXISTING_UID=$(id -u roost 2>/dev/null || echo "")
  if [ -n "$EXISTING_UID" ] && [ "$EXISTING_UID" != "$ROOST_UID" ]; then
      echo "ERROR: roost user exists with UID $EXISTING_UID, expected $ROOST_UID"
      exit 1
  fi
  # Ensure group exists with correct GID
  if ! getent group roost >/dev/null; then
      groupadd -g ${ROOST_UID} roost
  fi
  # Ensure user exists with correct UID
  if ! id -u roost >/dev/null 2>&1; then
      useradd -u ${ROOST_UID} -g ${ROOST_UID} -M -r -s /usr/sbin/nologin roost
  fi
  
  # Add roost to docker group
  if getent group docker >/dev/null 2>&1; then
      usermod -aG docker roost 2>/dev/null || true
  fi
}

# Run command as roost user if we're root
run_as_roost() {
    if [ "$RUN_AS_ROOT" = "true" ]; then
        sudo -u ${ROOST_USER} "$@"
    else
        "$@"
    fi
}
# Run command as root (or with sudo if not root)
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

setup_logging() {
  run_as_root mkdir -p "${ROOST_LOG}"
  run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_LOG}"
  run_as_root chmod 2770 "${ROOST_LOG}"
  
  local LOG_FILE="${ROOST_LOG}/roostEnterprise.log"
  run_as_root touch "${LOG_FILE}"
  run_as_root chown ${ROOST_UID}:${ROOST_UID} "${LOG_FILE}"
  run_as_root chmod 660 "${LOG_FILE}"
  
  exec &> >(tee -a "${LOG_FILE}")
}

check_execution_context
add_roost_user
setup_logging

DEFAULT_VER=${ROOST_VER:-v1.1.18}

add_roost_user

init() {
  set -x
}

usage() { echo "
Usage:
$0 [-i <install cmd>] [-c <config.json>]" 1>&2; 
}

compulsory_options() { echo "
compulsory options:
  Option            Description                                                 Usage
    -i              install cmd [roost,ec2,roostai,gpt]                          -i 'roost'
    -c              config file                                                 -c 'config.json'
" 1>&2; 
}

PUBLIC_IP=$(curl -s ifconfig.me)

options() {
    compulsory_options
}

read_and_check_env_file(){
    # echo "$fileContent"
    validateFile=$(cat "$configurationFilePath" | jq . > /dev/null)
    validateFileOutput=$?
    if [ $validateFileOutput -ne 0 ]; then
      echo "ERROR: Invalid JSON in config file"
      exit 1;
    fi
    fileContent=$(cat "$configurationFilePath")
    isFileRight=true

    # Client Config
    ENTERPRISE_NAME=$(echo "$fileContent" | jq -r '.enterprise_name')
    EAAS_SERVER_IP=$(echo "$fileContent" | jq -r '.roostgpt_server_ip // .eaas_server_ip')
    EAAS_SERVER_KEY_PATH=$(echo "$fileContent" | jq -r '.roostgpt_server_pem_key // .eaas_server_pem_key')
    EAAS_SERVER_USERNAME=$(echo "$fileContent" | jq -r '.roostgpt_server_username // .eaas_server_username')
    JUMPHOST_IP=$(echo "$fileContent" | jq -r '.jumphost_ip')
    ENTERPRISE_LOGO=$(echo "$fileContent" | jq -r '.enterprise_logo')
    ENTERPRISE_EMAIL_DOMAIN=$(echo "$fileContent" | jq -r '.enterprise_email_domain')
    ENTERPRISE_DNS=$(echo "$fileContent" | jq -r '.enterprise_dns')

    pattern='^ec2-(\d+)-(\d+)-(\d+)-(\d+)\.[a-z0-9-]+\.compute\.amazonaws\.com$'
    
    if [ "${install}" == "ec2" ]; then
      if [[ $ENTERPRISE_DNS =~ $pattern ]]; then
        echo "Dynamically retrieve public DNS for the instance and use that instead"
        TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
        ENTERPRISE_DNS=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-hostname)
      fi
    fi

    ADMIN_EMAIL=$(echo "$fileContent" | jq -r '.admin_email')

    # Email Config
    EMAIL_SENDER=$(echo "$fileContent" | jq -r '.email_sender')
    EMAIL_SENDER_PASS=$(echo "$fileContent" | jq -r '.email_sender_pass')
    EMAIL_SMTP=$(echo "$fileContent" | jq -r '.email_smtp_host')
    EMAIL_SMTP_PORT=$(echo "$fileContent" | jq -r '.email_smtp_port')
    # EMAIL_SMTP_INSECURE=$(echo "$fileContent" | jq -r '.email_smtp_insecure')

    # Other Config
    LICENSE_KEY=$(echo "$fileContent" | jq -r '.license_key')
    JWT_SECRET=$(echo "$fileContent" | jq -r '.ENV_SERVER.JWT_SECRET')
    AUTH_KEY=$(echo "$fileContent" | jq -r '.ENV_SERVER.AUTH_KEY')
    DEFAULT_PORT=$(echo "$fileContent" | jq -r '.ENV_SERVER.DEFAULT_PORT // 3000')

    ENABLE_SALESFORCE=$(echo "$fileContent" | jq -r '.enable_salesforce')
    ECS_MODE=$(echo "$fileContent" | jq -r '.ecs_mode')
    ENABLE_JUMPHOST=$(echo "$fileContent" | jq -r '.enable_jumphost')
    ENABLE_EAAS=$(echo "$fileContent" | jq -r '.enable_eaas')
    USE_NO_AUTH_ENABLED=$(echo "$fileContent" | jq -r '.use_no_auth')
    USE_AS_ROOST_CLOUD_SERVER_ENABLED=$(echo "$fileContent" | jq -r '.use_as_roost_cloud_server')
    GPT_ONLY_ENABLED=$(echo "$fileContent" | jq -r '.gpt_only')
    
    if [ "${install}" == "gpt" ]; then
      GPT_ONLY_ENABLED=true
    fi
    # USE_IP_ADDRESS_ENABLED=$(echo "$fileContent" | jq -r '.use_ip_address')
    USE_ROOST_DEV_ENABLED=$(echo "$fileContent" | jq -r '.use_roost_dev')
    # IS_HTTPS_ENABLED=$(echo "$fileContent" | jq -r '.is_https_enabled')
    # IS_LOAD_BALANCER=$(echo "$fileContent" | jq -r '.load_balancer')

    IS_HTTPS_ENABLED=true
    ENTERPRISE_CERTIFICATE_PATH=$(echo "$fileContent" | jq -r '.enterprise_ssl_certificate_path')
    ENTERPRISE_CERTIFICATE_KEY_PATH=$(echo "$fileContent" | jq -r '.enterprise_ssl_certificate_key_path')
    
    if [ -z "$ENTERPRISE_CERTIFICATE_PATH" ] || [ "$ENTERPRISE_CERTIFICATE_PATH" = null ]; then
      ENTERPRISE_CERTIFICATE_PATH="$ROOST_DIR/certs/server.cer"
      RHEL_ENTERPRISE_CERTIFICATE_PATH="/etc/pki/nginx/server.crt"
    fi
    if [ -z "$ENTERPRISE_CERTIFICATE_KEY_PATH" ] || [ "$ENTERPRISE_CERTIFICATE_KEY_PATH" = null ]; then
      ENTERPRISE_CERTIFICATE_KEY_PATH="$ROOST_DIR/certs/server.key"
      RHEL_ENTERPRISE_CERTIFICATE_KEY_PATH="/etc/pki/nginx/private/server.key"
    fi

    # Auth Config
    GITHUB_CLIENT_ID=$(echo "$fileContent" | jq -r '.ENV_SERVER.GITHUB_CLIENT_ID')
    GITHUB_CLIENT_SECRET=$(echo "$fileContent" | jq -r '.ENV_SERVER.GITHUB_CLIENT_SECRET')
    GOOGLE_CLIENT_ID=$(echo "$fileContent" | jq -r '.ENV_SERVER.GOOGLE_CLIENT_ID')
    GOOGLE_CLIENT_SECRET=$(echo "$fileContent" | jq -r '.ENV_SERVER.GOOGLE_CLIENT_SECRET')
    LINKEDIN_CLIENT_ID=$(echo "$fileContent" | jq -r '.ENV_SERVER.LINKEDIN_CLIENT_ID')
    LINKEDIN_CLIENT_SECRET=$(echo "$fileContent" | jq -r '.ENV_SERVER.LINKEDIN_CLIENT_SECRET')
    AZURE_CLIENT_ID=$(echo "$fileContent" | jq -r '.ENV_SERVER.AZURE_CLIENT_ID')
    AZURE_TENANT_ID=$(echo "$fileContent" | jq -r '.ENV_SERVER.AZURE_TENANT_ID')
    AZURE_CLIENT_SECRET=$(echo "$fileContent" | jq -r '.ENV_SERVER.AZURE_CLIENT_SECRET')
    OKTA_CLIENT_ISSUER=$(echo "$fileContent" | jq -r '.ENV_SERVER.OKTA_CLIENT_ISSUER')
    OKTA_CLIENT_ID=$(echo "$fileContent" | jq -r '.ENV_SERVER.OKTA_CLIENT_ID')
    OKTA_CLIENT_SECRET=$(echo "$fileContent" | jq -r '.ENV_SERVER.OKTA_CLIENT_SECRET')
    AZURE_ADFS_CLIENT_ISSUER=$(echo "$fileContent" | jq -r '.ENV_SERVER.AZURE_ADFS_CLIENT_ISSUER')
    AZURE_ADFS_CLIENT_ID=$(echo "$fileContent" | jq -r '.ENV_SERVER.AZURE_ADFS_CLIENT_ID')
    AZURE_ADFS_CLIENT_SECRET=$(echo "$fileContent" | jq -r '.ENV_SERVER.AZURE_ADFS_CLIENT_SECRET')
    AUTH0_CLIENT_ISSUER=$(echo "$fileContent" | jq -r '.ENV_SERVER.AUTH0_CLIENT_ISSUER')
    AUTH0_CLIENT_ID=$(echo "$fileContent" | jq -r '.ENV_SERVER.AUTH0_CLIENT_ID')
    AUTH0_CLIENT_SECRET=$(echo "$fileContent" | jq -r '.ENV_SERVER.AUTH0_CLIENT_SECRET')
    PING_FEDERATE_CLIENT_ISSUER=$(echo "$fileContent" | jq -r '.ENV_SERVER.PING_FEDERATE_CLIENT_ISSUER')
    PING_FEDERATE_CLIENT_ID=$(echo "$fileContent" | jq -r '.ENV_SERVER.PING_FEDERATE_CLIENT_ID')
    PING_FEDERATE_CLIENT_SECRET=$(echo "$fileContent" | jq -r '.ENV_SERVER.PING_FEDERATE_CLIENT_SECRET')
    OTP_LOGIN_ENABLED=$(echo "$fileContent" | jq -r '.ENV_SERVER.OTP_LOGIN_ENABLED // false')

    # DB config
    IS_OWN_SQL=$(echo "$fileContent" | jq -r '.is_own_sql // false')
    DB_HOST=$(echo "$fileContent" | jq -r '.ENV_DATABASE.DB_HOST')
    DB_HOST_TYPE=$(echo "$fileContent" | jq -r 'if .ENV_DATABASE.DB_HOST_TYPE | IN("postgres","mysql") then .ENV_DATABASE.DB_HOST_TYPE else "mysql" end')
    DB_PORT=$(echo "$fileContent" | jq -r '.ENV_DATABASE.DB_PORT')
    DB_USERNAME=$(echo "$fileContent" | jq -r '.ENV_DATABASE.DB_USERNAME')
    DB_PASSWORD=$(echo "$fileContent" | jq -r '.ENV_DATABASE.DB_PASSWORD')
    DB_ROOT_PASSWORD=$(echo "$fileContent" | jq -r '.ENV_DATABASE.DB_ROOT_PASSWORD')
    # DB_PASSWORD_ARN=$(echo "$fileContent" | jq -r '.ENV_DATABASE.DB_PASSWORD_ARN')
    DB_SCHEMA_NAME=$(echo "$fileContent" | jq -r '.ENV_DATABASE.DB_SCHEMA_NAME')

    #########################################

    ([[ -z "$ENTERPRISE_NAME" ]] || [[ "$ENTERPRISE_NAME" = null ]]) && { echo "Add enterprise_name in env file"; isFileRight=false ;}
    ([[ -z "$ENTERPRISE_DNS" ]] || [[ "$ENTERPRISE_DNS" = null ]]) && { echo "Add enterprise_dns in env file"; isFileRight=false ;}
    ([[ -z "$ADMIN_EMAIL" ]] || [[ "$ADMIN_EMAIL" = null ]]) && { echo "Add admin_email in env file"; isFileRight=false ;}

    if [[ -z "$EAAS_SERVER_IP" ]] || [[ "$EAAS_SERVER_IP" = null ]]; then EAAS_SERVER_IP="127.0.0.1" ; fi
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
    if [[ "$IS_HTTPS_ENABLED" = true ]]; then
      if [ -s "$ENTERPRISE_CERTIFICATE_PATH" ]; then
        echo "File at enterprise_ssl_certificate_path"
      elif [ -L "$ENTERPRISE_CERTIFICATE_PATH" ]; then
        echo "Symbolic link at enterprise_ssl_certificate_path"
      else
        echo "File/Link at enterprise_ssl_certificate_path is missing"
        isFileRight=false
      fi
    fi
    ([[ -z "$ENTERPRISE_CERTIFICATE_KEY_PATH" ]] || [[ "$ENTERPRISE_CERTIFICATE_KEY_PATH" = null ]]) && ([[ "$IS_HTTPS_ENABLED" = true ]]) && { echo "Add enterprise_ssl_certificate_key_path in env file"; isFileRight=false ;}
    if [[ "$IS_HTTPS_ENABLED" = true ]]; then
      if [ -s "$ENTERPRISE_CERTIFICATE_KEY_PATH" ]; then
        echo "File at enterprise_ssl_certificate_key_path"
      elif [ -L "$ENTERPRISE_CERTIFICATE_KEY_PATH" ]; then
        echo "Symbolic link at enterprise_ssl_certificate_key_path"
      else
        echo "File/Link at enterprise_ssl_certificate_key_path is missing"
        isFileRight=false
      fi
    fi

    #########################################

    [[ -z "$IS_OWN_SQL" || "$IS_OWN_SQL" = "null" ]] && IS_OWN_SQL="false"
    ([[ -z "$DB_SCHEMA_NAME" ]] || [[ "$DB_SCHEMA_NAME" = "null" ]]) && DB_SCHEMA_NAME="roostio"

    if [[ "$IS_OWN_SQL" = false ]]; then
      [[ -z "$DB_PASSWORD" || "$DB_PASSWORD" = "null" ]] && DB_PASSWORD="Roost.io"
      [[ -z "$DB_ROOT_PASSWORD" || "$DB_ROOT_PASSWORD" = "null" ]] && DB_ROOT_PASSWORD=$DB_PASSWORD

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
      fi

    else
      ([[ -z "$DB_HOST" ]] || [[ "$DB_HOST" = null ]]) && { echo "Add DB_HOST in env file"; isFileRight=false ;}
      ([[ -z "$DB_PORT" ]] || [[ "$DB_PORT" = null ]]) && { echo "Add DB_PORT in env file"; isFileRight=false ;}
      ([[ -z "$DB_USERNAME" ]] || [[ "$DB_USERNAME" = null ]]) && { echo "Add DB_USERNAME in env file"; isFileRight=false ;}
      ([[ -z "$DB_PASSWORD" ]] || [[ "$DB_PASSWORD" = null ]]) && { echo "Add DB_PASSWORD in env file"; isFileRight=false ;}
    fi

    #########################################

    [[ -z "$EMAIL_SENDER" || "$EMAIL_SENDER" = "null" ]] && EMAIL_SENDER=""
    [[ -z "$EMAIL_SENDER_PASS" || "$EMAIL_SENDER_PASS" = "null" ]] && EMAIL_SENDER_PASS=""
    [[ -z "$EMAIL_SMTP" || "$EMAIL_SMTP" = "null" ]] && EMAIL_SMTP=""
    [[ -z "$EMAIL_SMTP_PORT" || "$EMAIL_SMTP_PORT" = "null" ]] && EMAIL_SMTP_PORT=""

    if [[ ! -z "$EMAIL_SENDER" ]] &&  [[ ! -z "$EMAIL_SENDER_PASS" ]] ; then
	    EMAIL_SENDER_PRESENT=true
    else
      EMAIL_SENDER_PRESENT=false
    fi
    ([[ "$OTP_LOGIN_ENABLED" == "true" ]] && [[ "$EMAIL_SENDER_PRESENT" == "false" ]]) && { 
        echo "Add EMAIL_SENDER and EMAIL_SENDER_PASS in env file to enable OTP based login"
        isFileRight=false
    }
    #########################################

    [[ -z "$LICENSE_KEY" || "$LICENSE_KEY" = "null" ]] && LICENSE_KEY=""
    [[ -z "$AUTH_KEY" || "$AUTH_KEY" = "null" ]] && AUTH_KEY="06b5e496f8f53139de7d2cc03b1e71ce"
    [[ -z "$DEFAULT_PORT" || "$DEFAULT_PORT" = "null" ]] && DEFAULT_PORT=3000
    
    ([[ "$DEFAULT_PORT" = "4200" ]]) && { echo "Use different DEFAULT_PORT than 4200 in env file"; isFileRight=false; }
    [[ -z "$JWT_SECRET" || "$JWT_SECRET" = "null" ]] && JWT_SECRET="32-character-secure-long-secret"
    
    #########################################
    githubLogin=true; googleLogin=true; linkedinLogin=true; azureLogin=true
    oktaLogin=true; azureAdfsLogin=true; auth0Login=true; pingFederateLogin=true

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

   if [[ $githubLogin = false ]] && [[ $azureLogin = false ]] && [[ $linkedinLogin = false ]] && \
       [[ $oktaLogin = false ]] && [[ $googleLogin = false ]] && [[ $azureAdfsLogin = false ]] && \
       [[ $auth0Login = false ]] && [[ $pingFederateLogin = false ]] && [[ $USE_NO_AUTH = false ]] && \
       [[ $OTP_LOGIN_ENABLED = false ]]; then
        echo "Add at least one third party client id"
        isFileRight=false
    fi
    #########################################

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
    if [[ ! -z "$IS_HTTPS_ENABLED" ]]; then
        CONTROLPLANE_URL="https://$ENTERPRISE_DNS"
        ENT_SERVER="$ENTERPRISE_DNS:443"
    else
        CONTROLPLANE_URL="http://$ENTERPRISE_DNS"
        ENT_SERVER="$ENTERPRISE_DNS:80"
    fi

    REMOTE_CONSOLE_PROXY="$ENTERPRISE_DNS"


    if [[ ! -z "$ENABLE_SALESFORCE" && $ENABLE_SALESFORCE = true ]]; then
      ENABLE_SALESFORCE=true
    else
      ENABLE_SALESFORCE=false
    fi

    DB_SCHEMA_NAME=${DB_SCHEMA_NAME:-"roostio"}

    run_as_root mkdir -p ${ROOST_DIR}/.roost
    run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/.roost"
    run_as_root chmod 700 "${ROOST_DIR}/.roost"

    write_env_files

    write_nginx_config
}

write_env_files() {
    # approostai.env
    cat > /tmp/approostai.env << EOF
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
REACT_APP_OTP_LOGIN_ENABLED=$OTP_LOGIN_ENABLED
REACT_APP_COOKIE_SECURE=$IS_HTTPS_ENABLED
REACT_APP_COOKIE_DOMAIN="$ENTERPRISE_DNS"
REACT_APP_ROOST_VER="${ROOST_VER:-$DEFAULT_VER}"
REACT_APP_DB_VER="${ROOST_VER:-$DEFAULT_VER}"
REACT_APP_EMAIL_SENDER_PRESENT=$EMAIL_SENDER_PRESENT
REACT_APP_IS_DEPLOYED_IN_ECS=$ECS_MODE
REACT_APP_ONLY_ROOSTGPT=$GPT_ONLY
REACT_APP_NO_AUTH=$USE_NO_AUTH
REACT_APP_USE_AS_ROOST_CLOUD_SERVER=$USE_AS_ROOST_CLOUD_SERVER
EOF
    run_as_root mv /tmp/approostai.env "${ROOST_DIR}/.roost/approostai.env"
    run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/.roost/approostai.env"
    run_as_root chmod 660 "${ROOST_DIR}/.roost/approostai.env"
    # db.env (if using embedded database)
    if [ "$IS_OWN_SQL" == "false" ]; then
        if [ "$DB_HOST_TYPE" == "postgres" ]; then
            cat > /tmp/db.env << EOF
POSTGRES_PASSWORD=$DB_PASSWORD
POSTGRES_USER=$DB_USERNAME
POSTGRES_DB=$DB_SCHEMA_NAME
EOF
        else
            cat > /tmp/db.env << EOF
MYSQL_ROOT_PASSWORD=$DB_PASSWORD
MYSQL_DATABASE=$DB_SCHEMA_NAME
EOF
        fi
        run_as_root mv /tmp/db.env "${ROOST_DIR}/.roost/db.env"
        run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/.roost/db.env"
        run_as_root chmod 660 "${ROOST_DIR}/.roost/db.env"
    fi
    # server.env
    cat > /tmp/server.env << EOF
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
USE_ROOST_DEV=$USE_ROOST_DEV
ECS_MODE=$ECS_MODE
USE_NO_AUTH=$USE_NO_AUTH
USE_AS_ROOST_CLOUD_SERVER=$USE_AS_ROOST_CLOUD_SERVER
EOF
    if [ "$ECS_MODE" == "true" ]; then
        cat >> /tmp/server.env << EOF
LOCAL_AUTH_KEY="LocalKey/$AUTH_KEY"
JUMPHOST_SVC=127.0.0.1
EAAS_SVC=127.0.0.1
EOF
    fi
    run_as_root mv /tmp/server.env "${ROOST_DIR}/.roost/server.env"
    run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/.roost/server.env"
    run_as_root chmod 660 "${ROOST_DIR}/.roost/server.env"
    # release.env
    cat > /tmp/release.env << EOF
VERBOSE_LEVEL=4
ENT_SERVER=${ENTERPRISE_DNS}
AUTH_KEY=$AUTH_KEY
ROOST_VER="${ROOST_VER:-$DEFAULT_VER}"
EOF
    run_as_root mv /tmp/release.env "${ROOST_DIR}/.roost/release.env"
    run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/.roost/release.env"
    run_as_root chmod 660 "${ROOST_DIR}/.roost/release.env"
    # aiServer.env
    cat > /tmp/aiServer.env << EOF
VERBOSE_LEVEL=4
ENT_SERVER=${ENTERPRISE_DNS}
ROOST_VER="${ROOST_VER:-$DEFAULT_VER}"
EOF
    run_as_root mv /tmp/aiServer.env "${ROOST_DIR}/.roost/aiServer.env"
    run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/.roost/aiServer.env"
    run_as_root chmod 660 "${ROOST_DIR}/.roost/aiServer.env"
    # launcher.env
    cat > /tmp/launcher.env << EOF
VERBOSE_LEVEL=4
ENT_SERVER=${ENTERPRISE_DNS}
AUTH_KEY=$AUTH_KEY
ROOST_VER="${ROOST_VER:-$DEFAULT_VER}"
EOF
    run_as_root mv /tmp/launcher.env "${ROOST_DIR}/.roost/launcher.env"
    run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/.roost/launcher.env"
    run_as_root chmod 660 "${ROOST_DIR}/.roost/launcher.env"
}

write_nginx_config() {
    local SERVER_NAME='server_name ~^(.+)$;'
    local MORE_CLEAR_HEADERS=""
    local CERT_PATH="$ENTERPRISE_CERTIFICATE_PATH"
    local KEY_PATH="$ENTERPRISE_CERTIFICATE_KEY_PATH"
    
    local ec2_type
    ec2_type=$(grep '^ID=' /etc/os-release | cut -f2 -d'=' | sed -e 's/"//g')
    
    case $ec2_type in
        "ubuntu")
            MORE_CLEAR_HEADERS="more_clear_headers Server;"
            ;;
        "rhel")
            MORE_CLEAR_HEADERS=""
            run_as_root mkdir -p /etc/pki/nginx/private
            run_as_root cp "$ENTERPRISE_CERTIFICATE_KEY_PATH" /etc/pki/nginx/private/server.key
            run_as_root cp "$ENTERPRISE_CERTIFICATE_PATH" /etc/pki/nginx/server.crt
            CERT_PATH="/etc/pki/nginx/server.crt"
            KEY_PATH="/etc/pki/nginx/private/server.key"
            ;;
    esac
    cat > /tmp/sysmon.conf << EOF
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
    $MORE_CLEAR_HEADERS
    keepalive_timeout       70;
    ssl_certificate         $CERT_PATH;
    ssl_certificate_key     $KEY_PATH;
    ssl_protocols           TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers             HIGH:!aNULL:!MD5;
    client_max_body_size    200M;
    error_page 413 =413 @payload_too_large;
    location @payload_too_large {
        default_type application/json;
        return 413 '{"status": 413, "message": "Payload Too Large", "max_size": "200M"}';
    }
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
        add_header          Cache-Control "public, max-age=86400, no-transform";
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
        add_header          Content-Security-Policy "default-src 'self';" always;
        add_header          X-Frame-Options "SAMEORIGIN" ;
        add_header          X-Content-Type-Options nosniff;
        add_header          Strict-Transport-Security "max-age=31536000; includeSubdomains; preload";
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
    
    # Move to ROOST_DIR first (for docker compose context)
    run_as_root mv /tmp/sysmon.conf "${ROOST_DIR}/sysmon.conf"
    run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/sysmon.conf"
    run_as_root chmod 644 "${ROOST_DIR}/sysmon.conf"
}
write_docker_compose(){
    local sql=""
    local gpt=""
    
    if [ "$IS_OWN_SQL" == "false" ]; then
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
    fi
    if [ "$ECS_MODE" == "true" ]; then
        gpt="roostai_gpt:
    image: zbio/roostai-server:\${EAAS_VER}
    network_mode: \"host\"
    env_file:
      - $ROOST_DIR/.roost/aiServer.env
    depends_on:
      - roostai_nest_server
    restart: unless-stopped
    volumes:
      - $ROOST_DIR:$ROOST_DIR
      - /var/run/docker.sock:/var/run/docker.sock
  "
    fi
    cat > /tmp/docker-compose.yaml << EOF
services:
  ${sql}${gpt}roostai_nest_server:
    image: zbio/roost-app:\${ROOST_VER}
    user: "10001:10001"
    group_add:
      - "10001"
    environment:
    - HOME=/home/roost
    env_file:
      - $ROOST_DIR/.roost/server.env
    network_mode: "host"
    restart: unless-stopped
    volumes:
      - $ROOST_DIR:$ROOST_DIR
  roostai_react_app:
    image: zbio/roost-web:\${REACTUI_VER}
    user: "10001:10001"
    environment:
    - HOME=/home/roost
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
    
    run_as_root mv /tmp/docker-compose.yaml "${ROOST_DIR}/docker-compose.yaml"
    run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/docker-compose.yaml"
    run_as_root chmod 660 "${ROOST_DIR}/docker-compose.yaml"
}

fix_permissions_for_roost_user(){
    echo "Fixing permissions for roost user on ${ROOST_DIR}"
    run_as_root chown -R ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}"
    run_as_root find "${ROOST_DIR}" -type d -exec chmod 2770 {} \;
    run_as_root find "${ROOST_DIR}" -type f -exec chmod 660 {} \;

    # Executables in bin must be world-executable so ubuntu can run them via SSH
    if [ -d "${ROOST_BIN}" ]; then
        run_as_root find "${ROOST_BIN}" -type f -exec chmod 755 {} \;
    fi

    # Allow traversal into ROOST_DIR and ROOST_BIN so non-roost users (e.g. ubuntu SSH) can execute scripts
    run_as_root chmod 2771 "${ROOST_DIR}"
    [ -d "${ROOST_BIN}" ] && run_as_root chmod 2771 "${ROOST_BIN}"

    # Sensitive directories
    [ -d "${ROOST_DIR}/.ssh" ] && run_as_root chmod 700 "${ROOST_DIR}/.ssh"
    [ -d "${ROOST_DIR}/.roost" ] && run_as_root chmod 700 "${ROOST_DIR}/.roost"
}

apply_docker_compose(){
    write_docker_compose
    
    cd "$ROOST_DIR"
    
    # Create .env file
    cat > /tmp/.env << EOF
EAAS_VER=${EAAS_VER:-$DEFAULT_VER}
JUMP_VER=${JUMP_VER:-$DEFAULT_VER}
ROOST_VER=${ROOST_VER:-$DEFAULT_VER}
REACTUI_VER=${REACTUI_VER:-$ROOST_VER}
PROXY_VER=${PROXY_VER:-$ROOST_VER}
DB_VER=v1.1.0
EOF
    run_as_root mv /tmp/.env "${ROOST_DIR}/.env"
    run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/.env"
    run_as_root chmod 660 "${ROOST_DIR}/.env"
    local ec2_type
    ec2_type=$(grep '^ID=' /etc/os-release | cut -f2 -d'=' | sed -e 's/"//g')
    local rhel_container_exe="docker"
    
    case $ec2_type in
        "ubuntu")
            # Pull and start as roost user
            run_as_roost docker compose -f "${ROOST_DIR}/docker-compose.yaml" pull
            run_as_roost docker compose -f "${ROOST_DIR}/docker-compose.yaml" up -d --build --remove-orphans --force-recreate
            echo "docker compose up: $?"
            ;;
        "rhel")
            run_as_root ${rhel_container_exe} compose -f "${ROOST_DIR}/docker-compose.yaml" pull
            run_as_root ${rhel_container_exe} compose -f "${ROOST_DIR}/docker-compose.yaml" up -d --build --remove-orphans --force-recreate
            echo "${rhel_container_exe} compose up: $?"
            ;;
        *)
            echo "container start up is not configured for $ec2_type"
            ;;
    esac
    fix_permissions_for_roost_user
    
    # Install nginx config
    run_as_root cp "${ROOST_DIR}/sysmon.conf" /etc/nginx/conf.d/
    run_as_root /etc/init.d/nginx reload || true
    
    if ! run_as_root systemctl is-active --quiet nginx; then
        run_as_root systemctl start nginx
    fi
    
    if [ "$ec2_type" == "rhel" ]; then
        run_as_root setsebool -P httpd_can_network_connect 1
        run_as_root setsebool -P httpd_can_network_relay 1
    fi
    
    # Handle dev flag
    if [ -n "$DEV" ] && [ "$DEV" == "1" ]; then
        run_as_root touch "${ROOST_DIR}/.dev"
        run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/.dev"
    elif [ -f "${ROOST_DIR}/.dev" ]; then
        run_as_root rm -f "${ROOST_DIR}/.dev"
    fi
}

restart_docker_compose(){
    cd "$ROOST_DIR"
    
    local CURR_VER=$(grep ROOST_VER .env 2>/dev/null | cut -f2 -d= || echo "")
    cp .env .env.bkp 2>/dev/null || true
    
    ROOST_VER=${ROOST_VER:-$DEFAULT_VER}
    
    cat > /tmp/.env << EOF
ROOST_VER=${ROOST_VER:-$DEFAULT_VER}
EAAS_VER=${EAAS_VER:-$DEFAULT_VER}
JUMP_VER=${JUMP_VER:-$DEFAULT_VER}
REACTUI_VER=${REACTUI_VER:-$ROOST_VER}
PROXY_VER=${PROXY_VER:-$ROOST_VER}
DB_VER=v1.1.0
EOF
    run_as_root mv /tmp/.env "${ROOST_DIR}/.env"
    run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/.env"
    run_as_root chmod 660 "${ROOST_DIR}/.env"
    
    cat "$ROOST_DIR/.env"
    
    if ! run_as_roost docker compose -f "${ROOST_DIR}/docker-compose.yaml" pull; then
        mv .env.bkp .env 2>/dev/null || true
    fi
    
    local ec2_type
    ec2_type=$(grep '^ID=' /etc/os-release | cut -f2 -d'=' | sed -e 's/"//g')
    local rhel_container_exe="docker"
    
    case $ec2_type in
        "ubuntu")
            run_as_roost docker compose -f "${ROOST_DIR}/docker-compose.yaml" pull
            run_as_roost docker compose -f "${ROOST_DIR}/docker-compose.yaml" up -d --build --remove-orphans --force-recreate
            echo "docker compose up: $?"
            ;;
        "rhel")
            run_as_root ${rhel_container_exe} compose -f "${ROOST_DIR}/docker-compose.yaml" pull
            run_as_root ${rhel_container_exe} compose -f "${ROOST_DIR}/docker-compose.yaml" up -d --build --remove-orphans --force-recreate
            echo "${rhel_container_exe} compose up: $?"
            ;;
        *)
            echo "container restart is not configured for $ec2_type"
            ;;
    esac
    
    if [ -n "$DEV" ] && [ "$DEV" == "1" ]; then
        run_as_root touch "${ROOST_DIR}/.dev"
        run_as_root chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/.dev"
    elif [ -f "${ROOST_DIR}/.dev" ]; then
        run_as_root rm -f "${ROOST_DIR}/.dev"
    fi
    
    fix_permissions_for_roost_user
}
check_prereqs_var(){
    if [ -z "$configurationFilePath" ]; then
        echo "ConfigFile path not provided; Look at $BASEDIR/main-config.json for template"
        exit 1
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
                exit 1
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
docker_prune() {
    local ec2_type
    ec2_type=$(grep '^ID=' /etc/os-release | cut -f2 -d'=' | sed -e 's/"//g')
    
    case $ec2_type in
        "ubuntu")
            run_as_roost docker container prune -f
            run_as_roost docker image prune -f
            ;;
        "rhel")
            local rhel_container_exe="docker"
            run_as_root ${rhel_container_exe} image prune --all
            ;;
        *)
            echo "container cleanup is not configured for $ec2_type"
            ;;
    esac
}
check_disk_space() {
    local disksizehome
    disksizehome=$(df -h / | awk 'int($5)>50')
    if [ -n "$disksizehome" ]; then
        echo "Partition has limited free space"
        echo "Initiating automated docker cleanup"
        docker_prune
    fi
}
roost_controlplane() {
    check_disk_space
    apply_docker_compose
}

APP_NAME=""
ENT_DNS=""
ENT_SERVER=""
BASEDIR=$(dirname "$0")
LOGS_DIR="${ROOST_DIR}/logs"
run_as_root mkdir -p "${LOGS_DIR}"
run_as_root chown ${ROOST_UID}:${ROOST_UID} "${LOGS_DIR}"
run_as_root chmod 2770 "${LOGS_DIR}"
cd "$ROOST_DIR"
read_and_check_env_file
init
case ${install} in
    "roost")
        echo "install roost web, db, eaas and controlplane server"
        roost_controlplane
        ;;
    "gpt")
        echo "install roost web, db, gpt and controlplane server"
        roost_controlplane
        ;;
    "ec2")
        echo "install roost web, db, gpt and controlplane server on a single ec2"
        roost_controlplane
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
    *)
        echo "Wrong argument. Argument must be either 'roost','gpt', 'ec2' or 'roostai'."
        exit 1
        ;;
esac
cd - >/dev/null