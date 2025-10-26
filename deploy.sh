#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE=""
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXIT_CODE=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    case $level in
        ERROR) echo -e "${RED}ERROR: $message${NC}" >&2 ;;
        WARN)  echo -e "${YELLOW}WARN: $message${NC}" >&2 ;;
        INFO)  echo -e "${GREEN}INFO: $message${NC}" ;;
    esac
}

error_handler() {
    local exit_code=$?
    log ERROR "Script failed at line $1 with exit code $exit_code"
    cleanup_on_error
    exit $exit_code
}

cleanup_on_error() {
    log WARN "Performing cleanup on error..."
    exit 1
}

trap 'error_handler ${LINENO}' ERR

prompt_input() {
    local var_name=$1
    local prompt_msg=$2
    local default=${3:-}
    local regex=${4:-}
    local value

    if [[ -n "$default" ]]; then
        prompt_msg="$prompt_msg (default: $default): "
    else
        prompt_msg="$prompt_msg: "
    fi

    read -r -s -p "$prompt_msg" value
    echo
    value=${value:-$default}

    if [[ -n "$regex" && ! "$value" =~ $regex ]]; then
        log ERROR "Invalid input for $var_name. Must match pattern: $regex"
        exit 1
    fi

    printf -v "$var_name" %s "$value"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

ssh_exec() {
    local user=$1
    local host=$2
    local key=$3
    shift 3
    local cmd="$*"
    log INFO "Executing remotely: $cmd"
    if [[ -n "$key" && -f "$key" ]]; then
        ssh -i "$key" "$user@$host" "$cmd"
    else
        ssh "$user@$host" "$cmd"
    fi
    local ret=$?
    if [[ $ret -ne 0 ]]; then
        log ERROR "Remote command failed with exit code $ret"
        return $ret
    fi
    return 0
}

log_file="deploy_$TIMESTAMP.log"
LOG_FILE="$SCRIPT_DIR/$log_file"
log INFO "Starting remote deployment script. Log file: $LOG_FILE"

prompt_input GIT_REPO "Git Repository URL" "" "^https?://github\.com/.+\.git$"
prompt_input GIT_PAT "Personal Access Token (PAT)" ""
prompt_input GIT_BRANCH "Branch name" "main" "^[a-zA-Z0-9_-]+$"
prompt_input SSH_USER "SSH Username" ""
prompt_input SSH_HOST "Server IP Address" "" "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
prompt_input SSH_KEY "SSH Key Path" "/c/Users/HP/Downloads/hng13-stage2-devops_key.pem"
prompt_input APP_PORT "Application Port (external host port)" "8080" "^[0-9]{1,5}$"
prompt_input DOCKER_REGISTRY "Docker Registry URL" "https://index.docker.io/v1/" ""
prompt_input DOCKER_USERNAME "Docker Username" ""
prompt_input DOCKER_PASSWORD "Docker Password" ""

export GIT_PAT

log INFO "Cloning repository: $GIT_REPO (branch: $GIT_BRANCH)"

REPO_DIR=$(basename "$GIT_REPO" .git)

if [[ -d "$REPO_DIR" ]]; then
    log INFO "Repository exists, pulling latest changes..."
    cd "$REPO_DIR" || {
        log ERROR "Failed to cd into $REPO_DIR"
        exit 1
    }
    git pull origin "$GIT_BRANCH"
else
    git clone "https://x-access-token:$GIT_PAT@github.com/$(echo "$GIT_REPO" | sed 's|https\?://github\.com/||')" || {
        log ERROR "Failed to clone repository"
        exit 1
    }
    cd "$REPO_DIR" || {
        log ERROR "Failed to cd into $REPO_DIR"
        exit 1
    }
fi

git checkout "$GIT_BRANCH" || {
    log ERROR "Failed to checkout branch $GIT_BRANCH"
    exit 1
}

log INFO "Repository cloned/updated successfully."


log INFO "Verifying project structure..."
if [[ ! -f "docker-compose.yml" || ! -f ".env" ]]; then
    log ERROR "Required files (docker-compose.yml) not found in $PWD"
    exit 1
fi
log INFO "Project files verified."

ssh_check "$SSH_USER" "$SSH_HOST" "$SSH_KEY"

log INFO "Transferring project files to remote server..."

ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" "mkdir -p /tmp/deploy_app" && \
scp -C -v -i "$SSH_KEY" ~/IdeaProjects/hng13-stage0-devops/index.html "$SSH_USER@$SSH_HOST:/tmp/deploy_app/" || {
    log ERROR "Failed to transfer files"
    exit 1
}

REMOTE_DIR="/tmp/deploy_app"


PREP_CMD="
    sudo apt update && sudo apt upgrade -y

    if ! command -v docker >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo rm get-docker.sh
        echo 'Docker installed.'
    else
        echo 'Docker already installed.'
    fi

    if ! command -v docker-compose >/dev/null 2>&1; then
        sudo curl -L 'https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)' -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo 'Docker Compose installed.'
    else
        echo 'Docker Compose already installed.'
    fi

    if ! groups \$USER | grep -q docker; then
        sudo usermod -aG docker \$USER
        newgrp docker
        echo 'User added to docker group.'
    fi

    sudo systemctl enable docker
    sudo systemctl start docker

    docker --version
    docker-compose --version

    if [[ -n \"$DOCKER_USERNAME\" && -n \"$DOCKER_PASSWORD\" ]]; then
        echo '$DOCKER_PASSWORD' | docker login $DOCKER_REGISTRY -u $DOCKER_USERNAME --password-stdin || { echo 'Docker login failed.'; exit 1; }
        echo 'Docker login successful.'
    else
        echo 'No Docker credentials provided, skipping login.'
    fi
"

ssh_exec "$SSH_USER" "$SSH_HOST" "$SSH_KEY" "$PREP_CMD"

log INFO "Deploying application on remote..."

ssh_exec "$SSH_USER" "$SSH_HOST" "$SSH_KEY" "
    cd $REMOTE_DIR

    docker-compose down || true
    docker system prune -f || true

    docker-compose up -d

    sleep 10
    if docker ps | grep -q app_blue || docker ps | grep -q app_green; then
        echo 'Containers are running.'
        docker-compose logs
    else
        echo 'Containers failed to start.'
        exit 1
    fi
"

# Wait for health checks remotely
log INFO "Waiting for health checks..."
ssh_exec "$SSH_USER" "$SSH_HOST" "$SSH_KEY" "
    cd $REMOTE_DIR
    for i in {1..30}; do
        if docker-compose ps | grep -q 'healthy'; then
            echo 'Health checks passed.'
            break
        fi
        sleep 2
    done
"

if ! ssh_exec "$SSH_USER" "$SSH_HOST" "$SSH_KEY" "curl -f http://localhost:$APP_PORT/healthz"; then
    log ERROR "Health check failed on port $APP_PORT."
    exit 1
fi
log INFO "App accessible on port $APP_PORT."

log INFO "Validating deployment..."

ssh_exec "$SSH_USER" "$SSH_HOST" "$SSH_KEY" "
    docker-compose ps

    curl -f http://localhost:$APP_PORT || exit 1
    echo 'Deployment validated locally.'
"

CLEANUP_FLAG=${1:-}
if [[ "$CLEANUP_FLAG" == "--cleanup" ]]; then
    log INFO "Cleanup mode: Removing all deployed resources..."
    ssh_exec "$SSH_USER" "$SSH_HOST" "$SSH_KEY" "
        cd $REMOTE_DIR
        docker-compose down -v
        docker system prune -a -f
        sudo rm -rf $REMOTE_DIR
        docker logout $DOCKER_REGISTRY || true
    "
fi

log INFO "Deployment completed successfully. Exit code: $EXIT_CODE"
exit $EXIT_CODE