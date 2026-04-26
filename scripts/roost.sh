#!/bin/bash

ROOST_UID=10001
ROOST_USER="roost"
ROOST_DIR=/var/tmp/Roost
ROOST_BIN="${ROOST_DIR}/bin"
ROOST_LOGS="${ROOST_DIR}/logs"
ROOST_CERTS="${ROOST_DIR}/certs"

# Ensure script runs as root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root (use sudo)"
  exit 1
fi

add_roost_user(){
  # Validates existing user UID 
  EXISTING_UID=$(id -u roost 2>/dev/null || echo "")
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
  
  # Add roost to docker group if docker is installed
  if getent group docker >/dev/null 2>&1; then
    usermod -aG docker roost 2>/dev/null || true
  fi
}

# Initialize roost user before anything else
add_roost_user

LOGS_DIR=/var/tmp
mkdir -p "${LOGS_DIR}"
chown root:root "${LOGS_DIR}"
chmod 1777 "${LOGS_DIR}"  # Sticky bit like /tmp
SETUP_LOG="${LOGS_DIR}/roostSetup.log"
touch "${SETUP_LOG}"
chmod 664 "${SETUP_LOG}"
exec &> >(tee -a "${SETUP_LOG}")
echo
echo "===="
echo
date

if [ -f "/var/tmp/.RoostEnv" ]; then
    . /var/tmp/.RoostEnv
fi


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

TAG=${TAG:-v1.1.20}
if [ -n "$DEV" ] && [ "$DEV" = "1" ]; then
  set -x
  TAG=latest
fi

ROOST_VERSION=${ROOST_VERSION:-$TAG}
GIT_URL="https://github.com/roost-io/roost-support/releases/download/${ROOST_VERSION}"
if [ "$ROOST_VERSION" == "latest" ]; then
  GIT_URL="https://github.com/roost-io/roost-support/releases/latest/download"
fi
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

# Unified permission application function
apply_roost_perms() {
    local target_dir=$1
    local mode=${2:-2770}  # Default to 2770 for directories
    
    echo "Applying permissions to ${target_dir}"
    mkdir -p "${target_dir}"
    chown -R ${ROOST_UID}:${ROOST_UID} "${target_dir}"
    find "${target_dir}" -type d -exec chmod ${mode} {} +
    find "${target_dir}" -type f -exec chmod 660 {} +
}

ensure_permissions() {
    if [ "$(stat -c %u ${ROOST_DIR} 2>/dev/null)" != "${ROOST_UID}" ]; then
        echo "Fixing ownership of ${ROOST_DIR}"
        chown -R ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}"
        find "${ROOST_DIR}" -type d -exec chmod 2770 {} +
        find "${ROOST_DIR}" -type f -exec chmod 660 {} +
    fi
    # Allow traversal into ROOST_DIR and ROOST_BIN so non-roost users (e.g. ubuntu SSH) can execute scripts
    chmod 2771 "${ROOST_DIR}"
    [ -d "${ROOST_BIN}" ] && chmod 2771 "${ROOST_BIN}"
    # Executable permissions on bin files are set by finalize_permissions at end of main()
}
# Mount the EBS disk
mount_ebs() {
    local epoch=$(date +%s)
    
    if verify_mount; then
        mkdir -p "${ROOST_DIR}"
        ensure_permissions
    elif verify_volume; then
        # Check if filesystem exists
        if ! lsblk -f | grep -w "${DISK}" | grep -q "ext4"; then
            mkfs -t ext4 ${EBS_VOLUME}
        fi
        
        mkdir -p "${ROOST_DIR}"
        mount ${EBS_VOLUME} ${ROOST_DIR}
        
        if mount | grep -q "$EBS_VOLUME"; then
            apply_roost_perms "${ROOST_DIR}"
            
            # Update fstab for persistence
            grep -v "${ROOST_DIR}" /etc/fstab > /etc/fstab.noroost
            cp /etc/fstab /etc/fstab.orig.${epoch}
            
            local uuid=""
            if command -v blkid >/dev/null 2>&1; then
                uuid=$(blkid | grep "${EBS_VOLUME}:" | awk '{print $2}' | sed -e 's/"//g')
            fi
            if [ -z "$uuid" ]; then
                local id=$(lsblk -f -o NAME,UUID | grep -w "${DISK}" | awk '{print $2}' | sed -e 's/"//g')
                uuid="UUID=${id}"
            fi
            
            if [ -n "$uuid" ]; then
                echo "${uuid}     ${ROOST_DIR}    ext4    defaults        0       2" >> /etc/fstab.noroost
                cp /etc/fstab.noroost /etc/fstab
                umount ${ROOST_DIR}
                mount -a
            fi
        fi
    fi
}
create_folders() {
    local epoch=$(date +%s)
    
    # Create base directory structure
    mkdir -p "${ROOST_DIR}"
    mkdir -p "${ROOST_BIN}"
    mkdir -p "${ROOST_LOGS}"
    mkdir -p "${ROOST_DIR}/db"
    mkdir -p "${ROOST_DIR}/.roost"
    mkdir -p "${ROOST_DIR}/.ssh"
    
    if [ -n "$SETUP" ]; then
        mkdir -p "${ROOST_CERTS}"
    fi
    
    # Create nestjs data directories
    mkdir -p "${ROOST_DIR}/roostai_nestjs_data/jumphost_keys"
    mkdir -p "${ROOST_DIR}/roostai_nestjs_data/ec2Launcher_keys/trigger_script"
    
    # Only do a full recursive chown if the top-level ownership is wrong (first run / ownership drift).
    # On repeated runs (ownership already correct) just chown the specific dirs that were just created,
    # avoiding an expensive recursive traversal of the entire EBS volume.
    if [ "$(stat -c %u ${ROOST_DIR} 2>/dev/null)" != "${ROOST_UID}" ]; then
        chown -R ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}"
    else
        # Chown only directories up to depth 3 (deepest new dir is roostai_nestjs_data/ec2Launcher_keys/trigger_script).
        # -type d means files in bin/ are never touched, keeping this fast regardless of how many binaries exist.
        find "${ROOST_DIR}" -maxdepth 3 -type d -exec chown ${ROOST_UID}:${ROOST_UID} {} +
    fi

    # Restrict sensitive directories early so processes can't access them during setup
    chmod 700 "${ROOST_DIR}/roostai_nestjs_data"
    chmod 700 "${ROOST_DIR}/.ssh"
    chmod 700 "${ROOST_DIR}/.roost"
}
expose_docker_on_port() {
    local epoch=$(date +%s)
    
    if [ -f /etc/docker/daemon.json ]; then
        cp /etc/docker/daemon.json /etc/docker/daemon.json.${epoch}
    fi
    touch /etc/docker/daemon.json
    cat <<EOF > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "hosts": ["unix:///var/run/docker.sock"]
}
EOF
    mkdir -p /etc/systemd/system/docker.service.d
    cat <<EOF > /etc/systemd/system/docker.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
EOF
    systemctl daemon-reload
    echo "Daemon reloaded"
    sleep 5
    systemctl restart docker
}
install_docker() {
    if ! systemctl is-active --quiet docker; then
        if [ ! -f /etc/apt/trusted.gpg.d/docker.gpg ]; then
            apt-key export 0EBFCD88 2>/dev/null | gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg 2>/dev/null || true
        fi
    fi
    
    apt-get update -y
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Ensure Docker is enabled & started
    systemctl daemon-reexec
    systemctl enable docker
    systemctl start docker

    # Wait until docker is actually ready (important in cloud-init / Terraform)
    for i in {1..10}; do
        if systemctl is-active --quiet docker; then
            echo "Docker is active"
            break
        fi
        echo "Waiting for Docker to start..."
        sleep 2
    done

    # Final safety check
    if ! systemctl is-active --quiet docker; then
        echo "ERROR: Docker failed to start"
        return 1
    fi
    
    limit_docker_resource_usage
    expose_docker_on_port
    
    # Add roost user to docker group
    if getent group docker >/dev/null; then
        usermod -aG docker roost
    else
        echo "WARNING: docker group not found, skipping usermod"
    fi
}
install_nginx(){
    if ! command -v nginx >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y nginx
    fi
    apt-get install -y nginx-extras
}
install_docker_compose(){
    if ! docker compose version >/dev/null 2>&1; then
        echo "Installing docker compose"
        apt-get install -y docker-buildx-plugin docker-compose-plugin
    fi
}
install_jq(){
    if ! command -v jq >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y jq
    fi
}
install_kubectl() {
    local KUBE_VERSION="1.23.6"
    
    if ! command -v kubectl >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y apt-transport-https ca-certificates curl
        curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
        echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
        apt-get update -y
        curl -L "https://dl.k8s.io/release/v${KUBE_VERSION}/bin/linux/amd64/kubectl" -o /tmp/kubectl
        chmod +x /tmp/kubectl
        mv /tmp/kubectl /usr/local/bin/kubectl
    fi
    if ! kubectl version --client 2>/dev/null | grep -q "${KUBE_VERSION}"; then
        curl -L "https://dl.k8s.io/release/v${KUBE_VERSION}/bin/linux/amd64/kubectl" -o /tmp/kubectl
        chmod +x /tmp/kubectl
        mv /tmp/kubectl /usr/local/bin/kubectl
    fi
    # Create symlink in ROOST_BIN
    if [ -L "${ROOST_BIN}/kubectl" ]; then
        ls -l "${ROOST_BIN}/kubectl"
    else
        rm -f "${ROOST_BIN}/kubectl"
        ln -s "$(command -v kubectl)" "${ROOST_BIN}/kubectl"
        chown -h ${ROOST_UID}:${ROOST_UID} "${ROOST_BIN}/kubectl"
    fi
    
    if [ ! -L "/usr/local/bin/k" ]; then
        ln -s "$(command -v kubectl)" /usr/local/bin/k
    fi
}
install_helm() {
    if ! command -v helm >/dev/null 2>&1; then
        curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
    fi
    if [ -L "${ROOST_BIN}/helm" ]; then
        ls -l "${ROOST_BIN}/helm"
    else
        rm -f "${ROOST_BIN}/helm"
        ln -s "$(command -v helm)" "${ROOST_BIN}/helm"
        chown -h ${ROOST_UID}:${ROOST_UID} "${ROOST_BIN}/helm"
    fi
}
install_make() {
    if ! command -v make >/dev/null 2>&1; then
        apt-get update -y
        apt-get -y install make
    fi
}
install_awscli() {
    apt-get install -y unzip
    
    if ! command -v aws >/dev/null 2>&1; then
        curl -q -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "${ROOST_DIR}/awscliv2.zip"
        chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/awscliv2.zip"
        cd "${ROOST_DIR}"
        unzip -q -o awscliv2.zip
        if [ $? -eq 0 ]; then
            ./aws/install -i /usr/local/aws-cli -b /usr/local/bin
        else
            echo "Failed to unzip awscliv2.zip"
        fi
        cd - >/dev/null
        echo "$(command -v aws)"
    fi
}
install_aws_iam_authenticator(){
    local AWS_IAM_AUTHENTICATOR_VERSION="0.6.2"
    
    if ! aws-iam-authenticator version 2>/dev/null | grep -q "${AWS_IAM_AUTHENTICATOR_VERSION}"; then
        curl -L -q -s "https://github.com/kubernetes-sigs/aws-iam-authenticator/releases/download/v${AWS_IAM_AUTHENTICATOR_VERSION}/aws-iam-authenticator_${AWS_IAM_AUTHENTICATOR_VERSION}_linux_amd64" -o "${ROOST_DIR}/aws-iam-authenticator"
        chmod +x "${ROOST_DIR}/aws-iam-authenticator"
        cp "${ROOST_DIR}/aws-iam-authenticator" /usr/local/bin/
        echo "$(command -v aws-iam-authenticator)"
    fi
}
install_gke_auth_plugin(){
    if ! command -v gcloud >/dev/null 2>&1; then
        apt-get update -y
        echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
        curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
        apt-get update -y
        apt-get install -y google-cloud-sdk google-cloud-sdk-gke-gcloud-auth-plugin
    fi
}
install_eksctl() {
    if ! command -v eksctl >/dev/null 2>&1; then
        curl -L -s "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C "${ROOST_DIR}/"
        mv "${ROOST_DIR}/eksctl" /usr/local/bin/
        echo "$(command -v eksctl)"
    fi
}
install_aws_binaries() {
    install_awscli
    install_aws_iam_authenticator
    install_eksctl
}
install_terraform() {
    if ! command -v terraform >/dev/null 2>&1; then
        curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
        apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
        apt-get update -y
        apt-get install terraform -y
        mv /usr/bin/terraform /usr/local/bin/terraform
    fi
}
limit_docker_resource_usage() {
    echo "INFO: Calculating 75% of total system resources..."
    local total_mem_kib
    total_mem_kib=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if ! [[ "$total_mem_kib" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Could not determine total system memory from /proc/meminfo." >&2
        return 1
    fi
    local TOTAL_MEM_BYTES=$((total_mem_kib * 1024))
    local LIMIT_MEM_BYTES=$((TOTAL_MEM_BYTES * 75 / 100))
    local TOTAL_CPU_CORES
    TOTAL_CPU_CORES=$(nproc)
    if ! [[ "$TOTAL_CPU_CORES" =~ ^[0-9]+$ ]] || [ "$TOTAL_CPU_CORES" -lt 1 ]; then
        echo "ERROR: Could not determine the number of CPU cores using nproc." >&2
        return 1
    fi
    local LIMIT_CPU=$((TOTAL_CPU_CORES * 75))
    echo "INFO: Target CPUQuota: ${LIMIT_CPU}%"
    local LIMIT_MEM_HUMAN
    if [ "$LIMIT_MEM_BYTES" -ge $((1024 * 1024 * 1024)) ]; then
        LIMIT_MEM_HUMAN="$((LIMIT_MEM_BYTES / 1024 / 1024 / 1024))G"
    else
        LIMIT_MEM_HUMAN="$((LIMIT_MEM_BYTES / 1024 / 1024))M"
    fi
    echo "INFO: Target MemoryMax: ${LIMIT_MEM_BYTES} bytes (approx. ${LIMIT_MEM_HUMAN})"
    local SLICE_NAME="docker_limit.slice"
    local SLICE_FILE="/etc/systemd/system/${SLICE_NAME}"
    local DOCKER_CONFIG="/etc/docker/daemon.json"
    local DOCKER_CONFIG_TMP="${DOCKER_CONFIG}.tmp"
    echo "INFO: Creating systemd slice file: ${SLICE_FILE}"
    cat <<EOF > "${SLICE_FILE}"
[Unit]
Description=Slice that limits overall Docker resources to 75% capacity
Before=slices.target
[Slice]
CPUAccounting=true
CPUQuota=${LIMIT_CPU}%
MemoryAccounting=true
MemoryMax=${LIMIT_MEM_BYTES}
[Install]
WantedBy=multi-user.target
EOF
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create systemd slice file at ${SLICE_FILE}." >&2
        return 1
    fi
    echo "INFO: Systemd slice file created successfully."
    echo "INFO: Reloading systemd daemon, then enabling and starting ${SLICE_NAME}..."
    systemctl daemon-reload || { echo "ERROR: systemctl daemon-reload failed." >&2; return 1; }
    echo "INFO: Enabling ${SLICE_NAME} to start on boot..."
    systemctl enable "${SLICE_NAME}" || { echo "ERROR: systemctl enable ${SLICE_NAME} failed." >&2; return 1; }
    echo "INFO: Starting ${SLICE_NAME}..."
    systemctl start "${SLICE_NAME}" || {
        if systemctl is-active --quiet "${SLICE_NAME}"; then
            echo "INFO: ${SLICE_NAME} is already active."
        else
            echo "ERROR: systemctl start ${SLICE_NAME} failed." >&2
            return 1
        fi
    }
    echo "INFO: Systemd slice ${SLICE_NAME} is active."
    echo "INFO: Updating Docker daemon.json (${DOCKER_CONFIG}) for cgroup-parent and cgroupdriver..."
    mkdir -p "$(dirname "$DOCKER_CONFIG")" || { echo "ERROR: Failed to create directory $(dirname "$DOCKER_CONFIG")." >&2; return 1; }
    if [ ! -f "$DOCKER_CONFIG" ]; then
        echo "{}" > "$DOCKER_CONFIG"
        echo "INFO: Created empty ${DOCKER_CONFIG}."
    fi
    jq \
        --arg slice_name_arg "${SLICE_NAME}" \
        '.["cgroup-parent"] = $slice_name_arg |
         .["exec-opts"] = ( .["exec-opts"] // [] | map(select(. != "native.cgroupdriver=cgroupfs")) | . + ["native.cgroupdriver=systemd"] | unique )' \
        "${DOCKER_CONFIG}" > "${DOCKER_CONFIG_TMP}"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to update ${DOCKER_CONFIG} using jq." >&2
        rm -f "${DOCKER_CONFIG_TMP}"
        return 1
    fi
    mv "${DOCKER_CONFIG_TMP}" "${DOCKER_CONFIG}" || {
        echo "ERROR: Failed to move ${DOCKER_CONFIG_TMP} to ${DOCKER_CONFIG}." >&2
        return 1
    }
    echo "INFO: ${DOCKER_CONFIG} updated successfully."
    echo "INFO: Restarting Docker service to apply changes..."
    systemctl restart docker || {
        echo "ERROR: Failed to restart Docker service." >&2
        return 1
    }
    echo "INFO: Docker service restarted."
    echo "SUCCESS: Docker resource limits should now be configured via ${SLICE_NAME}."
    return 0
}
install_buildpacks() {
    if ! command -v pack >/dev/null 2>&1; then
        add-apt-repository ppa:cncf-buildpacks/pack-cli -y
        apt-get update -y
        apt-get install pack-cli -y
        mv /usr/bin/pack /usr/local/bin/pack
    fi
}
install_cdk() {
    if ! command -v npm >/dev/null 2>&1; then
        apt-get install npm -y
    fi
    if ! command -v cdk >/dev/null 2>&1; then
        npm install -g aws-cdk
    fi
    cdk --version
}
install_flux() {
    curl -s https://fluxcd.io/install.sh | bash
    flux --version
}
install_pulumi() {
    if ! command -v pulumi >/dev/null 2>&1; then
        curl -fsSL https://get.pulumi.com | sh
        mv "$HOME/.pulumi/bin/pulumi" /usr/local/bin/pulumi
    fi
}
install_prereqs() {
    install_jq
    install_docker
    if [ -n "$SETUP" ]; then
        install_prereqs_controlplane
    fi
}
rhel_install_prereqs() {
    dnf check-update -y || true
    dnf install -y curl
    
    subscription-manager repos --enable "codeready-builder-for-rhel-9-$(arch)-rpms" || true
    dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm || true
    dnf install -y epel-release || true
    dnf install -y jq procps-ng gzip perl-Digest-SHA
    
    usermod -aG docker roost 2>/dev/null || true
    if [ -n "$SETUP" ]; then
        dnf install -y nginx
        systemctl status nginx || true
        setsebool -P httpd_can_network_connect 1
        setsebool -P httpd_can_network_relay 1
    fi
}
install_prereqs_controlplane() {
    install_nginx
    install_docker_compose
}
controlplane_config() {
    local epoch=$(date +%s)
    
    # Backup config.json
    if [ -s "${ROOST_DIR}/config.json" ]; then
        cp -p "${ROOST_DIR}/config.json" "${ROOST_DIR}/config.json.${epoch}"
    fi
    rm -f "$ROOST_BIN/roost-enterprise.sh"
    if [ -f "$ROOST_DIR/roost.json" ]; then
        mv "${ROOST_DIR}/roost.json" "${ROOST_DIR}/roost.json.${epoch}"
    fi
    ROOST_VERSION=${ROOST_VERSION:-latest}
    GIT_URL="https://github.com/roost-io/roost-support/releases/download/${ROOST_VERSION}"
    if [ "$ROOST_VERSION" == "latest" ]; then
        GIT_URL="https://github.com/roost-io/roost-support/releases/latest/download"
    fi
    # Download and set permissions atomically
    curl -sL "${GIT_URL}/roost-enterprise.sh" -o "${ROOST_BIN}/roost-enterprise.sh"
    chown ${ROOST_UID}:${ROOST_UID} "${ROOST_BIN}/roost-enterprise.sh"
    chmod 755 "${ROOST_BIN}/roost-enterprise.sh"
    if [ ! -s "$ROOST_DIR/config.json" ]; then
        curl -sL "${GIT_URL}/main-config.json" -o "$ROOST_DIR/config.json"
        chown ${ROOST_UID}:${ROOST_UID} "$ROOST_DIR/config.json"
        chmod 660 "$ROOST_DIR/config.json"
    fi
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
        chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/config.json"
        chmod 660 "${ROOST_DIR}/config.json"
    fi
    curl -sL "${GIT_URL}/roost.sql" -o "$ROOST_DIR/db/roost.sql"
    chown ${ROOST_UID}:${ROOST_UID} "$ROOST_DIR/db/roost.sql"
    chmod 660 "$ROOST_DIR/db/roost.sql"
    
    generate_cert
}
generate_cert() {
    ROOST_VERSION=${ROOST_VERSION:-latest}
    GIT_URL="https://github.com/roost-io/roost-support/releases/download/${ROOST_VERSION}"
    if [ "$ROOST_VERSION" == "latest" ]; then
        GIT_URL="https://github.com/roost-io/roost-support/releases/latest/download"
    fi
    
    curl -sL "${GIT_URL}/roostcertgen.gz" -o "${ROOST_BIN}/roostcertgen.gz"
    chown ${ROOST_UID}:${ROOST_UID} "${ROOST_BIN}/roostcertgen.gz"
    
    if [ -f "${ROOST_BIN}/roostcertgen.gz" ]; then
        gunzip -f "${ROOST_BIN}/roostcertgen.gz"
        chown ${ROOST_UID}:${ROOST_UID} "${ROOST_BIN}/roostcertgen"
        chmod 755 "${ROOST_BIN}/roostcertgen"
        "${ROOST_BIN}/roostcertgen" --org "$CUSTOMER"
    fi
}
# Finalize permissions after all operations
finalize_permissions() {
    echo "Finalizing permissions for ${ROOST_DIR}..."

    # Only do full recursive chown if ownership has drifted; avoids expensive traversal on repeated runs
    if [ "$(stat -c %u ${ROOST_DIR} 2>/dev/null)" != "${ROOST_UID}" ]; then
        chown -R ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}"
    fi

    # Directories with setgid (private by default)
    find "${ROOST_DIR}" -type d -exec chmod 2770 {} +

    # Allow traversal into ROOST_DIR and ROOST_BIN so non-roost users (e.g. ubuntu SSH) can execute scripts
    chmod 2771 "${ROOST_DIR}"
    [ -d "${ROOST_BIN}" ] && chmod 2771 "${ROOST_BIN}"

    # Regular files
    find "${ROOST_DIR}" -type f -exec chmod 660 {} +

    # Executables in bin must be world-executable so ubuntu can run them via SSH
    if [ -d "${ROOST_BIN}" ]; then
        find "${ROOST_BIN}" -type f -exec chmod 755 {} +
    fi

    # Sensitive directories
    [ -d "${ROOST_DIR}/.ssh" ] && chmod 700 "${ROOST_DIR}/.ssh"
    [ -d "${ROOST_DIR}/.roost" ] && chmod 700 "${ROOST_DIR}/.roost"
    [ -d "${ROOST_DIR}/roostai_nestjs_data" ] && chmod 700 "${ROOST_DIR}/roostai_nestjs_data"

    # SSH keys
    find "${ROOST_DIR}/.ssh" -type f -name "*.pem" -exec chmod 600 {} + 2>/dev/null || true
    find "${ROOST_DIR}/.ssh" -type f ! -name "*.pub" -exec chmod 600 {} + 2>/dev/null || true

    echo "Permissions finalized."
}
main() {
    local epoch=$(date +%s)
    if [ -n "$DEV" ] && [ "$DEV" = "1" ]; then
        touch "${ROOST_DIR}/.dev"
    else
        rm -f "${ROOST_DIR}/.dev"
    fi
    
    local ec2_type
    ec2_type=$(grep '^ID=' /etc/os-release | cut -f2 -d'=' | sed -e 's/"//g')
    
    case $ec2_type in
        "rhel")
            echo "RHEL"
            DISK="${DISK:-nvme0n1}"
            mount_ebs
            create_folders
            rhel_install_prereqs
            ;;
        "ubuntu")
            echo "Ubuntu"
            DISK="${DISK:-nvme1n1}"
            mount_ebs
            create_folders
            install_prereqs
            ;;
        *)
            echo "No match for $ec2_type"
            exit 1
            ;;
    esac
    case $SETUP in
        1)
            echo "Setup Controlplane"
            controlplane_config
            ;;
        *)
            echo "No setup"
            ;;
    esac
    if [ -n "$DEV" ] && [ "$DEV" = "1" ]; then
        touch "${ROOST_DIR}/.dev"
        chown ${ROOST_UID}:${ROOST_UID} "${ROOST_DIR}/.dev"
    fi
    case $SCRIPT in
        "singleHost.sh") setup_singleInstance;;
        "ec2Launcher.sh") setup_ec2launcher;;
        *) echo "$SCRIPT has nothing to do";;
    esac
    
    # Always finalize permissions at the end
    finalize_permissions
    
    next_steps
}
next_steps() {
    if [ -s "$ROOST_DIR/${CUSTOMER}-config.json" ]; then
        DOMAIN=$(jq -r .domain "$ROOST_DIR/${CUSTOMER}-config.json")
    fi
    set +x
    echo "================================================================="
    echo "   Next Steps   "
    echo "================================================================="
    if [ -n "$SETUP" ]; then
        echo "1. Modify ${ROOST_DIR}/config.json"
        local dev=""
        if [ -n "$DEV" ] && [ "$DEV" = "1" ]; then
            dev="-d 1"
        fi
        local admin
        admin=$(jq -r .admin_email "${ROOST_DIR}/config.json")
        echo "2. Run: sudo -u roost ${ROOST_BIN}/roost-enterprise.sh ${dev} -c ${ROOST_DIR}/config.json -i roost"
        echo "3. Access Roost controlplane at ${DOMAIN} using admin email: ${admin}"
    fi
    echo "================================================================="
}
docker_clean() {
    if [ -s "${ROOST_DIR}/docker-compose.yaml" ]; then
        docker compose -f "${ROOST_DIR}/docker-compose.yaml" down --remove-orphans --rmi all
    fi
    docker ps -q | xargs -r docker stop
    docker images -q | xargs -r docker rmi -f
    systemctl stop docker
}
podman_clean() {
    if [ -s "${ROOST_DIR}/podman-compose.yaml" ]; then
        podman-compose -f "${ROOST_DIR}/podman-compose.yaml" down --remove-orphans
    elif [ -s "${ROOST_DIR}/docker-compose.yaml" ]; then
        podman-compose -f "${ROOST_DIR}/docker-compose.yaml" down --remove-orphans
    fi
    podman ps -q | xargs -r podman stop
    podman images -q | xargs -r podman rmi -f
}
clean() {
    set -x
    echo "Inside clean function"
    local epoch=$(date +%s)
    # Remove Crontab entries
    local CRON_PATTERN="cloudCleanUp|restartScript"
    crontab -l 2>/dev/null | grep -Ev "${CRON_PATTERN}" | crontab - 2>/dev/null || true
    # Kill Roost processes
    local ROOST_PROC_PATTERN="ec2launcher|releaseServer|RoostApi|RoostK8s|RoostMetrics"
    pkill -f "${ROOST_PROC_PATTERN}" || true
    systemctl stop nginx || true
    
    local ec2_type
    ec2_type=$(grep '^ID=' /etc/os-release | cut -f2 -d'=' | sed -e 's/"//g')
    case $ec2_type in
        "ubuntu") docker_clean;;
        "rhel") podman_clean;;
        *) echo "container clean up is not configured";;
    esac
    # Backup current config
    cp "${ROOST_DIR}/config.json" "/var/tmp/config.json.${epoch}" 2>/dev/null || true
    umount -f "${ROOST_DIR}" 2>/dev/null || true
    mv "${ROOST_DIR}" "${ROOST_DIR}.${epoch}" 2>/dev/null || true
    grep -v "${ROOST_DIR}" /etc/fstab > /tmp/fstab.noroost
    cp /tmp/fstab.noroost /etc/fstab
    for roostLink in /etc/rc4.d/S01roost*; do
        [ -e "$roostLink" ] && unlink "$roostLink"
    done
}
copy_archive() {
    local _default_store="${ARTIFACT_STORE:-/home/ubuntu}"
    for binary in "$@"; do
        local binHash=""
        local fileHash=""
        local ARTIFACT_STORE="$_default_store"
        if [ ! -f "${ARTIFACT_STORE}/${binary}" ] && [ ! -f "${ARTIFACT_STORE}/${binary}.gz" ]; then
            ARTIFACT_STORE="/root"
        fi
        
        if [ -s "${ROOST_BIN}/${binary}" ]; then
            binHash=$(shasum "${ROOST_BIN}/${binary}" | cut -f1 -d' ')
            if [ -s "${ARTIFACT_STORE}/${binary}.gz" ]; then
                gunzip -f "${ARTIFACT_STORE}/${binary}.gz"
            fi
            if [ -s "${ARTIFACT_STORE}/${binary}" ]; then
                fileHash=$(shasum "${ARTIFACT_STORE}/${binary}" | cut -f1 -d' ')
            fi
            if [ "${fileHash}" == "${binHash}" ]; then
                continue
            fi
        fi
        
        if [ -s "${ARTIFACT_STORE}/${binary}.gz" ]; then
            cp -f "${ARTIFACT_STORE}/${binary}.gz" "${ROOST_BIN}/${binary}.gz"
            gunzip -f "${ROOST_BIN}/${binary}.gz"
        elif [ -s "${ARTIFACT_STORE}/${binary}" ]; then
            cp -f "${ARTIFACT_STORE}/${binary}" "${ROOST_BIN}/${binary}"
        fi
        
        if [ -s "${ROOST_BIN}/${binary}" ]; then
            chown ${ROOST_UID}:${ROOST_UID} "${ROOST_BIN}/${binary}"
            chmod 755 "${ROOST_BIN}/${binary}"
        fi
    done
}
copy_scripts() {
    local _default_store="${ARTIFACT_STORE:-/home/ubuntu}"
    for binary in "$@"; do
        local binHash=""
        local fileHash=""
        local ARTIFACT_STORE="$_default_store"
        if [ ! -f "${ARTIFACT_STORE}/${binary}" ]; then
            ARTIFACT_STORE="/root"
        fi
        if [ -s "${ROOST_BIN}/${binary}" ]; then
            binHash=$(shasum "${ROOST_BIN}/${binary}" | cut -f1 -d' ')
            if [ -s "${ARTIFACT_STORE}/${binary}" ]; then
                fileHash=$(shasum "${ARTIFACT_STORE}/${binary}" | cut -f1 -d' ')
            fi
            if [ "${fileHash}" == "${binHash}" ]; then
                continue
            fi
        fi

        if [ -s "${ARTIFACT_STORE}/${binary}" ]; then
            cp -f "${ARTIFACT_STORE}/${binary}" "${ROOST_BIN}/${binary}"
            chown ${ROOST_UID}:${ROOST_UID} "${ROOST_BIN}/${binary}"
            chmod 755 "${ROOST_BIN}/${binary}"
        fi
    done
}
check_releaseServer() {
    local grep_status=1
    local commitid
    commitid=$(curl -s http://127.0.0.1:60003/api/status | jq -r .gitCommit 2>/dev/null)
    if [ -n "$commitid" ] && [ "$commitid" != "null" ]; then
        grep -q "$commitid" "$ROOST_BIN/releaseServer.commitid" 2>/dev/null
        grep_status=$?
    fi
    if [ $grep_status -ne 0 ]; then
        pkill -f "releaseServer|ec2Launcher|ec2launcher" || true
    fi
}
check_aiServer() {
    local grep_status=1
    local commitid
    commitid=$(curl -s http://127.0.0.1:60007/api/status | jq -r .gitCommit 2>/dev/null)
    if [ -n "$commitid" ] && [ "$commitid" != "null" ]; then
        grep -q "$commitid" "$ROOST_BIN/aiServer.commitid" 2>/dev/null
        grep_status=$?
    fi
    if [ $grep_status -ne 0 ]; then
        pkill -f "aiServer" || true
    fi
}
setup_singleInstance() {
    GIT_URL="https://github.com/roost-io/roost-support/releases/download/${ROOST_VERSION}"
    if [ "$ROOST_VERSION" == "latest" ]; then
        GIT_URL="https://github.com/roost-io/roost-support/releases/latest/download"
    fi
    
    # Download scripts
    for script in ec2Launcher.sh aiServer.sh releaseServer.sh roostgpt-linux; do
        curl -sL "${GIT_URL}/${script}" -o "${ROOST_BIN}/${script}"
        chown ${ROOST_UID}:${ROOST_UID} "${ROOST_BIN}/${script}"
        chmod 755 "${ROOST_BIN}/${script}"
    done
    # Download and extract binary archives
    for roostFile in gotty aiServer releaseServer ec2launcher; do
        curl -sL "${GIT_URL}/${roostFile}.gz" -o "${ROOST_BIN}/${roostFile}.gz"
        gunzip -f "${ROOST_BIN}/${roostFile}.gz"
        chown ${ROOST_UID}:${ROOST_UID} "${ROOST_BIN}/${roostFile}"
        chmod 755 "${ROOST_BIN}/${roostFile}"
    done
    
    # check_releaseServer
    check_aiServer
    
    # Run ec2Launcher as roost user
    sudo -u roost DEV=$DEV APPNAME=${CUSTOMER} ENTSERVER="http://127.0.0.1:3000" ROOST_VER=${ROOST_VERSION} "${ROOST_BIN}/ec2Launcher.sh" &
}
setup_ec2launcher() {
    # check_releaseServer
    check_aiServer
    pkill -f "${SCRIPT}" || true
    local archive="ec2launcher releaseServer aiServer gotty"
    copy_archive $archive
    local scripts="releaseServer.sh aiServer.sh ec2Launcher.sh master.tar.gz roost.sh releaseServer.commitid ec2launcher.commitid aiServer.commitid userOrganisationCluster.sh"
    copy_scripts $scripts
}
# Echo environment variables
env | grep -E 'CLEAN|DEV|SETUP|SCRIPT' || true
if [ -n "$CLEAN" ]; then
    echo "Cleanup Roost setup"
    clean
    echo "rm -f $0"
    exit
else
    echo "Setup Roost"
    # add_roost_user is already called at the top
    main
fi
echo "Done: $(date)"