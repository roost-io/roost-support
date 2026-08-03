#!/bin/bash -x
#set -e
LOGS_DIR=/var/tmp
exec 2>>"$LOGS_DIR/roostSetup.err"
exec 1>>"$LOGS_DIR/roostSetup.log"

if [ -f "/var/tmp/.RoostEnv" ]; then
    . /var/tmp/.RoostEnv
fi
ROOST_DIR=/var/tmp/Roost
ROOST_BIN="${ROOST_DIR}/bin"
ROOST_YAML="${ROOST_DIR}/yaml"
ROOST_LOGS="${ROOST_DIR}/logs"
ROOST_CERTS="${ROOST_DIR}/certs"
if [ -z "$DISK" ]; then
    AVLBL_DISK=$(lsblk | grep disk | awk '{print $1}' | xargs)
    for dsk in $VLBL_DISK; do
	blkid | grep $dsk
	if [ $? -ne 0 ]; then
	    DISK=$dsk
	    break
	fi
    done
fi
DISK="${DISK:-nvme1n1}"
EBS_VOLUME="${EBS_VOLUME:-/dev/$DISK}"

S3_BUCKET="roost-stable"
S3_CONFIG_URL="https://${S3_BUCKET}.s3-us-west-2.amazonaws.com/enterprise"
TAG=${TAG:-v1.1.0}
if [[ ! -z "$DEV" && "$DEV" = 1 ]];then
  set -x
  S3_CONFIG_URL="https://${S3_BUCKET}.s3-us-west-2.amazonaws.com"
  TAG=latest
fi
INSTALLER="RoostInstaller"
CUSTOMER_INSTALLER="${CUSTOMER:-Roost}Installer"

# Helper function
verify_mount() {
    df -h | grep "$ROOST_DIR"
    return $?
}

# Helper function
verify_volume() {
    which blkid
    if [ $? -eq 0 ]; then
      ebs_volume=$(blkid | grep "${EBS_VOLUME}:")
      if [ ! -z "$ebs_volume" ]; then
        return 0
      fi
    fi
    ebs=$(lsblk | grep -w "${DISK}")
    if [ ! -z "$ebs" ]; then
        return 0
    fi
    return 1
}

# Mount the EBS disk
# TODO: Needs to improve the process to identify available volume OR take user input
mount_ebs() {
  if verify_mount; then
    if [ ! -d "${ROOST_DIR}" ]; then
      sudo mkdir "${ROOST_DIR}"
    fi
    sudo chown `id -u`:`id -g` ${ROOST_DIR}
  elif verify_volume; then
    lsblk -f | grep -w "${DISK}" | grep "ext4"
    if [ $? -ne 0 ]; then
      sudo mkfs -t ext4 ${EBS_VOLUME}
    fi
    if [ ! -d "${ROOST_DIR}" ]; then
      sudo mkdir ${ROOST_DIR}
    fi
    sudo mount ${EBS_VOLUME} ${ROOST_DIR}
    mount | grep "$EBS_VOLUME"
    if [ $? -eq 0 ]; then
      sudo chown `id -u`:`id -g` ${ROOST_DIR}

      grep -v "${ROOST_DIR}" /etc/fstab  | sudo tee /etc/fstab.noroost
      # Plan for reboot
      epoch=$(date +%s)
      sudo cp /etc/fstab /etc/fstab.orig.${epoch}
      which blkid
      if [ $? -eq 0 ]; then
        uuid=$(blkid | grep "${EBS_VOLUME}:" | awk '{print $2}'|sed -e 's/"//g')
      fi
      if [ -z $uuid ]; then
        id=$(lsblk -f -o NAME,UUID | grep -w "${DISK}" | awk '{print $2}'|sed -e 's/"//g')
        uuid="UUID=${id}"
      fi
      if [ ! -z $uuid ]; then
        echo "${uuid}     ${ROOST_DIR}    ext4    defaults        0       2" | sudo tee -a /etc/fstab.noroost
        sudo cp /etc/fstab.noroost /etc/fstab
        sudo umount ${ROOST_DIR}
        sudo mount -a
        if [ $? -eq 0 ]; then
          mount | grep "$EBS_VOLUME"
          if [ $? -ne 0 ]; then
           sudo chown `id -u`:`id -g` ${ROOST_DIR}
          fi
        fi
      fi
    fi
  fi
}

# Helper function
create_folders() {
  if [ -z "$SETUP" -a -z "$EAAS" ];then
    ROOST_CERTS=""
  fi
  for folder in $ROOST_DIR $ROOST_BIN $ROOST_LOGS $ROOST_CERTS $ROOST_YAML $ROOST_DIR/db
  do
    if [ ! -d "${folder}" ]; then
      sudo mkdir -p "${folder}"
    fi
    sudo chown `id -u`:`id -g` "${folder}"
  done
}

# Only needed on Roost controlplane
# Get all binaries and scripts on ROOST_BIN and since this is volume mounted to controlplane nestJs container
# So the binaries, scripts can be pushed to jumpHost and releaseServer, ec2Launcher aiServer hosts
get_installer_binary() {
  if [ ! -x "${ROOST_BIN}/${INSTALLER}" ]; then
    curl -q -s ${S3_CONFIG_URL}/${CUSTOMER_INSTALLER} -o $ROOST_BIN/$INSTALLER
    chmod +x $ROOST_BIN/$INSTALLER
  fi
}

# expose_docker_on_port() {
#   if [ -f /etc/docker/daemon.json ]; then
#     cat /etc/docker/daemon.json
#     epoch=$(date +%s)
#     sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.${epoch}
#   fi

#   PUBLIC_IP=$(curl -s ifconfig.me)
#   sudo touch /etc/docker/daemon.json
#   cat <<EOF | sudo tee /etc/docker/daemon.json
# {
#   "exec-opts": ["native.cgroupdriver=systemd"],
#   "insecure-registries" : ["$PUBLIC_IP:5002", "local-registry:5002"],
#   "hosts": ["tcp://0.0.0.0:5000", "unix:///var/run/docker.sock"]
# }
# EOF
#   sudo mkdir -p /etc/systemd/system/docker.service.d
#   cat <<EOF | sudo tee /etc/systemd/system/docker.service.d/override.conf
# [Service]
# ExecStart=
# ExecStart=/usr/bin/dockerd
# EOF
#   sudo systemctl daemon-reload
#   echo "Daemon reloaded"
#   sleep 5
#   sudo systemctl restart docker
# }

# Docker for controlplane, jumpHost and releaseServer
install_docker() {
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
      grep "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable" /etc/apt/sources.list
      if [ $? -ne 0 ]; then
          sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
          sudo apt-get update -y
      fi
      if [ ! -d "/etc/docker" ]; then
          sudo mkdir "/etc/docker"
      fi
      if [ ! -f "/etc/docker/daemon.json" ]; then
          echo '{"exec-opts": ["native.cgroupdriver=systemd"]}' | sudo tee /etc/docker/daemon.json
      fi
      apt-cache policy docker-ce
      VERSION_STRING=5:20.10.23~3-0~ubuntu-bionic
      sudo apt-get install -y --allow-downgrades docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-compose-plugin
    fi
    sudo systemctl status docker
    docker_status=$?
    if [ $docker_status -ne 0 ]; then
      if [ -d "/var/run/docker.sock" ]; then
        sudo rm -rf "/var/run/docker.sock"
        sudo systemctl restart docker
      fi
    fi
    # sudo usermod -aG docker ubuntu
    sudo usermod -aG docker $(whoami)
    # expose_docker_on_port
}

# primarily needed for controlplane to host webserver for console proxy and controlplane access
install_nginx(){
    nginx_out=$(nginx -v >/dev/null 2>&1)
    nginx_status=$?
    if [ $nginx_status -ne 0 ]; then
        sudo apt-get update -y
        sudo apt-get install -y nginx
    fi
}

# docker compose used for controlplane and also for release server to deploy app
install_docker_compose(){
    # docker_compose_out=$(docker-compose -v >/dev/null 2>&1)
    which docker-compose
    docker_compose_status=$?
    if [ $docker_compose_status -ne 0 ]; then
        echo "install docker compose"
        sudo curl -sL "https://github.com/docker/compose/releases/download/v2.14.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        if [ ! -L /usr/bin/docker-compose ]; then
          sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
        fi
    fi
}

# jq can be used for json data parsing
install_jq(){
  which jq
  if [ $? -ne 0 ]; then
    sudo apt-get update -y
    sudo apt-get install -y jq
  fi
}

# Kubernetes client needed on JumpHost, ReleaseServer
install_kubectl() {
  # fixed 1.23.6 for EKS, AWS IAM Authenticator compatibility around k8s.client authorisation v1alpha1 and v1beta1
  KUBE_VERSION="1.23.6"
  which kubectl
  if [ $? -ne 0 ]; then
    sudo apt-get update -y
    sudo apt-get install -y apt-transport-https ca-certificates curl
    sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update -y
    curl -L "https://dl.k8s.io/release/v${KUBE_VERSION}/bin/linux/amd64/kubectl" -o /var/tmp/kubectl && chmod +x /var/tmp/kubectl && sudo mv /var/tmp/kubectl /usr/local/bin/kubectl
  fi

  kubectl version | grep "${KUBE_VERSION}"
  if [ $? -ne 0 ]; then
    # sudo apt-get install -qy --allow-downgrades --allow-change-held-packages kubectl:${KUBE_VERSION}-00
    curl -L "https://dl.k8s.io/release/v${KUBE_VERSION}/bin/linux/amd64/kubectl" -o /var/tmp/kubectl && chmod +x /var/tmp/kubectl && sudo mv /var/tmp/kubectl /usr/local/bin/kubectl
  fi

  if [ -L "${ROOST_BIN}/kubectl" ]; then
    ls -l "${ROOST_BIN}/kubectl"
  else
    if [ -e "${ROOST_BIN}/kubectl" ]; then
      sudo unlink "${ROOST_BIN}/kubectl"
    fi
    sudo ln -s $(which kubectl) "${ROOST_BIN}/kubectl"
  fi
  if [ ! -L "/usr/local/bin/k" ]; then
    sudo ln -s $(which kubectl) /usr/local/bin/k
  fi
}

# Helm from Google/Kubernetes for k8s app packaging/deployment
# Needed for release server and also for deployment of 3rd party charts on jumpHost, ReleaseServer
install_helm() {
  which helm
  if [ $? -ne 0 ]; then
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
  fi

  if [ -L "${ROOST_BIN}/helm" ]; then
    ls -l "${ROOST_BIN}/helm"
  else
    if [ -e "${ROOST_BIN}/helm" ]; then
      sudo unlink "${ROOST_BIN}/helm"
    fi
    sudo ln -s $(which helm) "${ROOST_BIN}/helm"
  fi
}

# GNU make is needed on Release server for code build
install_make() {
  which make
  if [ $? -ne 0 ]; then
      sudo apt-get update -y
      sudo apt-get -y install make
  fi
}

# AWS cli is used for AWS configure/access from terminal
install_awscli() {
  sudo apt-get install -y unzip
  #install aws cli
  which aws
  if [ $? -ne 0 ]; then
    curl -q -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o ${ROOST_DIR}/awscliv2.zip
    cd ${ROOST_DIR};
    unzip -q -o awscliv2.zip;
    if [ $? -eq 0 ]; then
      sudo aws/install -i /usr/local/aws-cli -b /usr/local/bin
    else
      echo "Failed to unzip awscliv2.zip"
    fi
    cd -
    echo $(which aws)
  fi
}

# aws-iam-authenticator is used by EKS kubeconfig for auth
install_aws_iam_authenticator(){
  # which aws-iam-authenticator
  # if [ $? -ne 0 ]; then
  #   curl -L -q -s https://github.com/kubernetes-sigs/aws-iam-authenticator/releases/download/v0.6.2/aws-iam-authenticator_0.6.2_linux_amd64 -o $ROOST_DIR/aws-iam-authenticator
  #   chmod +x $ROOST_DIR/aws-iam-authenticator
  #   sudo cp $ROOST_DIR/aws-iam-authenticator /usr/local/bin/
  #   echo $(which aws-iam-authenticator)
  # else
  AWS_IAM_AUTHENTICATOR_VERSION="0.6.2"
  aws-iam-authenticator version | grep "${AWS_IAM_AUTHENTICATOR_VERSION}"
  if [ $? -ne 0 ]; then
    # sudo apt-get install -qy --allow-downgrades --allow-change-held-packages kubectl:${KUBE_VERSION}-00
    curl -L -q -s https://github.com/kubernetes-sigs/aws-iam-authenticator/releases/download/v0.6.2/aws-iam-authenticator_0.6.2_linux_amd64 -o $ROOST_DIR/aws-iam-authenticator
    chmod +x $ROOST_DIR/aws-iam-authenticator
    sudo cp $ROOST_DIR/aws-iam-authenticator /usr/local/bin/
    echo $(which aws-iam-authenticator)
    # fi
  fi
}

install_gke_auth_plugin(){
  which gcloud
  if [ $? -ne 0 ]; then
    sudo apt-get update -y
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
    sudo apt-get update -y
    sudo apt-get install -y google-cloud-sdk google-cloud-sdk-gke-gcloud-auth-plugin
  fi
}

# eksctl is the client for EKS
install_eksctl() {
  #install eksctl
  which eksctl
  if [ $? -ne 0 ]; then
    curl -L -s https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz | tar xz -C $ROOST_DIR/
    sudo mv $ROOST_DIR/eksctl /usr/local/bin/
    echo $(which eksctl)
  fi
}

install_aws_binaries() {
  install_awscli
  install_aws_iam_authenticator
  install_eksctl
}

install_terraform() {
  which terraform
  if [ $? -ne 0 ]; then
    sudo curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
    sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
    sudo apt-get update -y
    sudo apt-get install terraform -y
    sudo mv /usr/bin/terraform /usr/local/bin/terraform
  fi
}

install_buildpacks() {
  which pack
  if [ $? -ne 0 ]; then
    sudo add-apt-repository ppa:cncf-buildpacks/pack-cli -y
    sudo apt-get update -y
    sudo apt-get install pack-cli -y
    sudo mv /usr/bin/pack /usr/local/bin/pack
  fi
}

install_cdk() {
  which npm
  if [ $? -ne 0 ]; then
    sudo apt-get install npm -y
  fi
  which cdk
  if [ $? -ne 0 ]; then
    npm install -g aws-cdk
  fi
  cdk --version
}

install_flux() {
  curl -s https://fluxcd.io/install.sh | sudo bash
  flux --version
}

install_pulumi() {
  which pulumi
  if [ $? -ne 0 ]; then
    curl -fsSL https://get.pulumi.com | sh
    sudo mv $HOME/.pulumi/bin/pulumi /usr/local/bin/pulumi
  fi
}

install_prereqs() {
  install_jq
  install_docker
}

install_prereqs_controlplane() {
  if [ ! -z "$EAAS" ];then
    rm -f $ROOST_BIN/$INSTALLER # better to remove and install fresh always
    get_installer_binary
  fi
  install_nginx
  install_docker_compose
}

install_prereqs_ec2launcher() {
  install_jq

  install_make
  install_buildpacks

  install_docker
  install_docker_compose

  install_kubectl
  install_helm

  install_awscli
  install_aws_iam_authenticator
  install_terraform

  install_gke_auth_plugin

  install_cdk
  install_flux
  install_pulumi
}

install_prereqs_jumphost() {
  install_jq

  install_kubectl
  install_helm
  install_aws_binaries
  install_gke_auth_plugin
  install_docker

  archive="gotty"
  copy_archive $archive

  scripts="regexrolecontroller-v1.yaml rbac.yaml rbac_new_namespace.yaml"
  copy_scripts $scripts
}

generate_cert() {
  ROOST_VERSION=${ROOST_VERSION:-dev}
  GIT_URL="https://raw.githubusercontent.com/roost-io/roost-support/${ROOST_VERSION}"
  curl -s ${GIT_URL}/bin/roostcertgen.gz > "$ROOST_BIN/roostcertgen.gz"
  if [ -f "$ROOST_BIN/roostcertgen.gz" ]; then
    gunzip -f ${ROOST_BIN}/roostcertgen.gz
    chmod +x "$ROOST_BIN/roostcertgen"
    $ROOST_BIN/roostcertgen --org $CUSTOMER
  fi
}

main() {
  epoch=$(date +%s)

  mount_ebs
  create_folders

  if [[ ! -z "$DEV" && "$DEV" = 1 ]];then
      touch "${ROOST_DIR}/.dev"
  else
      rm -f "${ROOST_DIR}/.dev"
  fi
  install_prereqs

  if [ ! -z "$SETUP" ]; then
    # Backup config.json
    if [ -s "${ROOST_DIR}/config.json" ]; then
      cp -p "${ROOST_DIR}/config.json" "${ROOST_DIR}/config.json.${epoch}"
    fi
    install_prereqs_controlplane
    if [ -f "$ROOST_BIN/roost-enterprise.sh" ]; then
      rm -f "$ROOST_BIN/roost-enterprise.sh"
    fi

    # This is to allow new desired version to come from S3 bucket
    # Better approach would be for the installer to take an argument and overwrite the default config
    if [ -f "$ROOST_DIR/roost.json" ]; then
      mv "${ROOST_DIR}/roost.json" "${ROOST_DIR}/roost.json.${epoch}"
    fi
    
    # ${ROOST_BIN}/$INSTALLER --command setup

    ROOST_VERSION=${ROOST_VERSION:-dev}
    GIT_URL="https://raw.githubusercontent.com/roost-io/roost-support/${ROOST_VERSION}"
    
    curl -s ${GIT_URL}/scripts/roost-enterprise.sh > "$ROOST_BIN/roost-enterprise.sh"
    curl -s ${GIT_URL}/scripts/main-config.json > "$ROOST_DIR/config.json"
    curl -s ${GIT_URL}/scripts/roost.sql > "$ROOST_DIR/db/roost.sql"
    if [ -f "$ROOST_BIN/roost-enterprise.sh" ]; then
      chmod +x "$ROOST_BIN/roost-enterprise.sh"
    fi

    generate_cert

    if [ -s "${ROOST_DIR}/config.json.${epoch}" ]; then
      cp -p "${ROOST_DIR}/config.json" "${ROOST_DIR}/config.json.new"

      jq -s 'def deepmerge(a;b):
    reduce b[] as $item (a;
      reduce ($item | keys_unsorted[]) as $key (.;
        $item[$key] as $val | ($val | type) as $type | .[$key] = if ($type == "object") then
          deepmerge({}; [if .[$key] == null then {} else .[$key] end, $val])
        elif ($type == "array") then
          (.[$key] + $val | unique)
        else
          $val
        end)
      );
    deepmerge({}; .)' "${ROOST_DIR}/config.json.new" "${ROOST_DIR}/config.json.${epoch}" > "${ROOST_DIR}/config.json"
      # cp -p "${ROOST_DIR}/config.json.${epoch}" "${ROOST_DIR}/config.json"
    fi
  fi

  if [ ! -z "$EAAS" ]; then
    ${ROOST_BIN}/$INSTALLER --command eaas
  fi


  if [ -f "$ROOST_DIR/.dev" ]; then
    touch "$ROOST_DIR/.dev"
  fi

  if [ ! -z "${SCRIPT}" ]; then
    if [ "${SCRIPT}" == "jumpHost.sh" ]; then
      setup_jump
    elif [ "${SCRIPT}" == "ec2Launcher.sh" ]; then
      setup_ec2launcher
    elif [ "${SCRIPT}" == "remote-roost.sh" ]; then
      setup_remote_roost
    fi
  else
    next_steps
  fi
}

next_steps() {
  if [ -s "$ROOST_DIR/${CUSTOMER}-config.json" ]; then
      DOMAIN=$(cat "$ROOST_DIR/${CUSTOMER}-config.json" | jq .domain)
  fi

  set +x
  # Check if the config file can be partly customized based on the Customer Name (as part of the installer)
  echo "================================================================="
  echo "   Next Steps   "
  echo "================================================================="
  if [ ! -z "$SETUP" ]; then
    echo "1. Modify ${ROOST_DIR}/config.json"
    if [[ ! -z "$DEV" && "$DEV" = 1 ]];then
      dev="-d 1"
    fi
    admin=$(cat ${ROOST_DIR}/config.json | jq .admin_email)
    echo "2. Run ${ROOST_DIR}/bin/roost-enterprise.sh ${dev} -c ${ROOST_DIR}/config.json -i roost"
    echo "3. Access Roost controlplane at ${DOMAIN} using admin email: ${admin}"
  elif [ ! -z "$EAAS" ]; then
    echo "1. Login to Roost controlplane as admin: ${DOMAIN}"
    echo "2. Go to Admin view, configure Eaas Server by providing public-ip and pem key"
    echo "3. Enable Jump Host choice and reload the page"
    echo "3. Go to Jump hosts tab and Add Jump Host with alias=default, public-ip and pem key"
  fi
  echo "================================================================="
}

clean() {
    set -x
    echo "Inside clean function"
    epoch=$(date +%s)

    # Remove Crontab entries
    CRON_PATTERN="cloudCleanUp|restartScript" # |gcpBiller|awsBiller
    crontab -l | egrep -v ${CRON_PATTERN} | crontab -

    # Kill Roost processes
    ROOST_PROC_PATTERN="ec2launcher|releaseServer|RoostApi|RoostK8s|RoostMetrics"
    sudo pkill ${ROOST_PROC_PATTERN}
    # ps -aef | egrep "${ROOST_PROC_PATTERN}" | awk '{print $2}' | xargs -r sudo kill -9

    # Stop NGINX
    sudo systemctl stop nginx

    # Stop docker process if present
    if [ -s "${ROOST_DIR}/docker-compose.yaml" ]; then
      sudo docker-compose -f ${ROOST_DIR}/docker-compose.yaml down --remove-orphans --rmi all
    fi

    # Stop any docker process
    sudo docker ps -q | xargs -r docker stop

    # Remove Docker images
    sudo docker images -q | xargs -r docker rmi -f

    # Stop Docker Daemon
    sudo systemctl stop docker

    # Backup current config
    sudo cp ${ROOST_DIR}/config.json "/var/tmp/config.json.${epoch}"

    # Unmount EBS volume
    sudo umount -f ${ROOST_DIR}

    # Rename - no value but might come handy if the mount failed or was not mount point
    sudo mv ${ROOST_DIR} "${ROOST_DIR}.${epoch}"

    # Restore mount fstab
    grep -v "${ROOST_DIR}" /etc/fstab > /tmp/fstab.noroost
    sudo cp /tmp/fstab.noroost /etc/fstab

    # Remove init.d scripts
    for roostLink in `ls -1 /etc/rc4.d/S01roost*`
    do
      sudo unlink ${roostLink}
    done
}

copy_archive() {
  for binary in $@;
  do
    if [ -f "${ROOST_BIN}/${binary}" ]; then
      binHash=$(shasum ${ROOST_BIN}/${binary}|cut -f1 -d' ')
      if [ -f "$HOME/${binary}.gz" ]; then
        gunzip -f "$HOME/${binary}.gz"
      fi
      if [ -f $HOME/${binary} ]; then
        fileHash=$(shasum $HOME/${binary}|cut -f1 -d' ')
      else
        fileHash=''
      fi
      if [ "${fileHash}" == "${binHash}" ]; then
        continue
      fi
    fi
    if [ -f "$HOME/${binary}.gz" ]; then
      sudo cp -f $HOME/${binary}.gz ${ROOST_BIN}/${binary}.gz
      gunzip -f ${ROOST_BIN}/${binary}.gz
    elif [ -f $HOME/${binary} ]; then
      sudo cp -f $HOME/${binary} ${ROOST_BIN}/${binary}
    fi
    if [ -f ${ROOST_BIN}/${binary} ]; then
      sudo chown -R `id -u`:`id -g` ${ROOST_BIN}/${binary}
      chmod +x ${ROOST_BIN}/${binary}
    fi
  done
}

copy_yaml() {
  for yaml in $@;
  do
    if [ -f "${ROOST_YAML}/${yaml}" ]; then
      yamlHash=$(shasum ${ROOST_YAML}/${yaml}|cut -f1 -d' ')
      if [ -f $HOME/${yaml} ]; then
        fileHash=$(shasum $HOME/${yaml}|cut -f1 -d' ')
      else
        fileHash=''
      fi
      if [ "${fileHash}" == "${yamlHash}" ]; then
        continue
      fi
    fi
    sudo cp -f $HOME/${yaml} ${ROOST_YAML}/${yaml}
    sudo chown `id -u`:`id -g` ${ROOST_YAML}/${yaml}
  done
}

copy_scripts() {
  for binary in $@;
  do
    if [ -f "${ROOST_BIN}/${binary}" ]; then
      binHash=$(shasum ${ROOST_BIN}/${binary}|cut -f1 -d' ')
      if [ -f $HOME/${binary} ]; then
        fileHash=$(shasum $HOME/${binary}|cut -f1 -d' ')
      else
        fileHash=''
      fi
      if [ "${fileHash}" == "${binHash}" ]; then
        continue
      fi
    fi
    if [ -f $HOME/${binary} ]; then
      sudo cp -f $HOME/${binary} ${ROOST_BIN}/${binary}
      sudo chown -R `id -u`:`id -g` ${ROOST_BIN}/${binary}
      chmod +x ${ROOST_BIN}/${binary}
    fi
  done
}

check_releaseServer() {
  grep_status=1
  commitid=$(curl http://127.0.0.1:60003/api/status | jq -r .gitCommit)
  if [ ! -z "$commitid" ]; then
    grep $commitid $ROOST_BIN/releaseServer.commitid
    grep_status=$?
  fi
  if [ $grep_status -ne 0 ]; then
    sudo pkill "releaseServer|ec2Launcher|ec2launcher"
  fi
}

check_aiServer() {
  grep_status=1
  commitid=$(curl http://127.0.0.1:60007/api/status | jq -r .gitCommit)
  if [ ! -z "$commitid" ]; then
    grep $commitid $ROOST_BIN/aiServer.commitid
    grep_status=$?
  fi
  if [ $grep_status -ne 0 ]; then
    sudo pkill "aiServer"
  fi
}

setup_ec2launcher() {
  # . ./jumphost_state.sh
  # record_current_ec2launcher_state
  install_prereqs_ec2launcher
  check_releaseServer
  check_aiServer
  sudo pkill "RoostMetricsDb|cloudCleanUp|${SCRIPT}"

  archive="ec2launcher awsController gcpController azureController cloudCleanUp releaseServer aiServer buildApp deployApp instanceCreation RoostCF uninstallApp RoostApi RoostK8s gotty"
  copy_archive $archive

  scripts="releaseServer.sh aiServer.sh setupTeamMember.sh userOrganisationCluster.sh ec2Launcher.sh remote-roost.sh master.tar.gz roost.sh releaseServer.commitid ec2launcher.commitid aiServer.commitid gcpController.commitid awsController.commitid"
  copy_scripts $scripts

  yaml="argocd-install.yaml argocd-core-install.yaml"
  copy_yaml $yaml
}

setup_remote_roost() {
  install_jq
  install_docker

  # only on controlplane/ec2, these would be needed
  if [ ! -z "$ROLE" -a "$ROLE" != "worker" ]; then
    install_docker_compose
    if [ -z "$ONLY_DOCKER" -o "$ONLY_DOCKER" != "1" ]; then
      install_awscli
      install_helm
      install_terraform
      install_buildpacks
    fi
  fi

  # Confirm if needed for k8s environment
  if [ -z "$ROLE" ]; then
    # Needed for docker-compose/EC2 environment
    docker pull cypress/included:9.1.1
    docker pull zbio/artillery-custom
    docker pull roostio/grafana:latest
  fi

  # docker pull zbio/falcolog:v1
  # docker pull zbio/roost-roostapi-proxy
  # docker pull zbio/fitness-ui

  # untar the master bundle
  if [ ! -d /var/tmp/Roost ]; then mkdir -p /var/tmp/Roost; fi
  cd /var/tmp/Roost;
  if [ -f "$HOME/master.tar.gz" ]; then
    mv $HOME/master.tar.gz /var/tmp/Roost
    tar -xvzf master.tar.gz;
  elif [ -f "/var/tmp/Roost/master.tar.gz" ]; then
    tar -xvzf master.tar.gz;
  else
    echo "master.tar.gz is missing"
  fi
  if [ -f bin/istio.tar.gz ]; then
    tar -xvzf bin/istio.tar.gz -C bin && ln -s istio-1.9.2 bin/istio
  fi

  # sudo tar -xzf \${SERVICE_MESH_SCRIPT_DIR}/\$ISTIO -C \${SERVICE_MESH_SCRIPT_DIR} && sudo mv \$SERVICE_MESH_SCRIPT_DIR/istio-* \$SERVICE_MESH_SCRIPT_DIR/istio
  # gunzip -f bin/*.gz

  find bin/ -type 'f' -name '*.gz' -exec sudo gunzip -f {} \;
  find bin/ -type 'f' -exec sudo chmod +x {} \;
  find yaml/ -type 'f' -exec sed -i -e "s/TAG/${TAG}/g" {} \;
  cd -
  if [ -f $HOME/remote-roost.sh ]; then
    chmod +x $HOME/remote-roost.sh;
    $HOME/remote-roost.sh
  fi
}

setup_jump() {
  # . ./jumphost_state.sh
  # record_current_jumphost_state
  if [ -z "$ONLY_DOCKER" -o "$ONLY_DOCKER" == "0" ];then
    install_prereqs_jumphost
  fi
  sudo pkill "RoostApi|RoostMetricsDb|RoostK8s|${SCRIPT}"

  archive="RoostApi RoostK8s gotty"
  copy_archive $archive

  scripts="RoostApi.commitid RoostMetricsDb deleteJumphost.sh roost-docker.sh jumpHost.sh setupTeamMember.sh userOrganisationCluster.sh regexrolecontroller-v1.yaml rbac.yaml rbac_new_namespace.yaml kubernetes-dashboard.yaml"
  copy_scripts $scripts
  find $ROOST_BIN -name '*.yaml' -type 'f' -exec sed -i -e "s/TAG/${TAG}/g" {} \;
  find $ROOST_BIN -name '*.yml' -type 'f' -exec sed -i -e "s/TAG/${TAG}/g" {} \;
}

# Echo these environment variables
env | egrep 'CLEAN|DEV|SETUP|EAAS|SCRIPT'

if [ ! -z "$CLEAN" ]; then
 echo "Cleanup Roost setup"
 clean
 echo "rm -f $0"
 exit
else
  echo "Setup Roost"
  main
fi
