#!/bin/bash

# Claude Code Docker Runner Script
# Usage: ./run-claude.sh [options] [command]

set -e

# Default values
IMAGE_NAME="claude-code:latest"
WORKSPACE_PATH="$(pwd)"

# Generate container name based on workspace path
# Take last two path components and create hash
WORKSPACE_TWO_PARTS=$(echo "$WORKSPACE_PATH" | awk -F'/' '{if(NF>=2) print $(NF-1)"/"$NF; else print $NF}')
WORKSPACE_SANITIZED=$(echo "$WORKSPACE_TWO_PARTS" | sed 's/[^a-zA-Z0-9_-]/-/g')
WORKSPACE_HASH=$(echo "$WORKSPACE_PATH" | sha256sum | cut -c1-12)
CONTAINER_NAME="claude-code-$WORKSPACE_SANITIZED-$WORKSPACE_HASH"
CLAUDE_CONFIG_PATH="$HOME/.claude"
INTERACTIVE=true
REMOVE_CONTAINER=false
PRIVILEGED=true
DANGEROUS_MODE=true
BUILD_ONLY=false
FORCE_REBUILD=false
RECREATE_CONTAINER=false
VERBOSE=false
REMOVE_CONTAINERS=false
FORCE_REMOVE_ALL_CONTAINERS=false
EXPORT_DOCKERFILE=""
PUSH_TO_REPO=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BRIGHT_CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Generate shell completions
generate_completions() {
  local shell="$1"

  if [[ -z "$shell" ]]; then
    echo -e "${RED}Error: Shell type required. Use 'bash' or 'zsh'${NC}" >&2
    exit 1
  fi

  case "$shell" in
  bash)
    cat <<'EOF'
_run_claude_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    opts="-w --workspace -c --claude-config -n --name -i --image --rm --no-interactive --no-privileged --safe --build --rebuild --recreate --verbose --remove-containers --force-remove-all-containers --export-dockerfile --push-to --generate-completions -h --help"
    
    case "${prev}" in
        -w|--workspace)
            COMPREPLY=( $(compgen -d -- ${cur}) )
            return 0
            ;;
        -c|--claude-config)
            COMPREPLY=( $(compgen -d -- ${cur}) )
            return 0
            ;;
        -n|--name)
            COMPREPLY=( $(compgen -W "claude-code" -- ${cur}) )
            return 0
            ;;
        -i|--image)
            COMPREPLY=( $(compgen -W "claude-code:latest" -- ${cur}) )
            return 0
            ;;
        --export-dockerfile)
            COMPREPLY=( $(compgen -f -- ${cur}) )
            return 0
            ;;
        --push-to)
            COMPREPLY=( $(compgen -W "docker.io/username/repo:tag" -- ${cur}) )
            return 0
            ;;
        --generate-completions)
            COMPREPLY=( $(compgen -W "bash zsh" -- ${cur}) )
            return 0
            ;;
        *)
            ;;
    esac
    
    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
    return 0
}
complete -F _run_claude_completion run-claude.sh
EOF
    ;;
  zsh)
    cat <<'EOF'
_run_claude_zsh_completion() {
    local -a options
    options=(
        '-w[Set workspace path]:workspace:_files -/'
        '--workspace[Set workspace path]:workspace:_files -/'
        '-c[Set Claude config path]:config:_files -/'
        '--claude-config[Set Claude config path]:config:_files -/'
        '-n[Set container name]:name:'
        '--name[Set container name]:name:'
        '-i[Set image name]:image:'
        '--image[Set image name]:image:'
        '--rm[Remove container after exit]'
        '--no-interactive[Run in non-interactive mode]'
        '--no-privileged[Run without privileged mode]'
        '--safe[Disable dangerous permissions]'
        '--build[Build the Docker image and exit]'
        '--rebuild[Force rebuild the Docker image and continue]'
        '--recreate[Remove existing container and create new one]'
        '--verbose[Show detailed output including Docker commands]'
        '--remove-containers[Remove stopped Claude Code containers and exit]'
        '--force-remove-all-containers[Remove ALL Claude Code containers and exit]'
        '--export-dockerfile[Export the embedded Dockerfile]:file:_files'
        '--push-to[Tag and push image to repository]:repository:'
        '--generate-completions[Generate shell completions]:shell:(bash zsh)'
        '(-h --help)'{-h,--help}'[Show help]'
    )
    _arguments -s -S $options
}
compdef _run_claude_zsh_completion run-claude.sh
EOF
    ;;
  *)
    echo -e "${RED}Error: Unsupported shell '$shell'. Use 'bash' or 'zsh'${NC}" >&2
    exit 1
    ;;
  esac
}

usage() {
  echo "Usage: $0 [OPTIONS] [COMMAND]"
  echo ""
  echo "OPTIONS:"
  echo "  -w, --workspace PATH    Set workspace path (default: current directory)"
  echo "  -c, --claude-config PATH Set Claude config path (default: ~/.claude)"
  echo "  -n, --name NAME         Set container name"
  echo "  -i, --image NAME        Set image name (default: claude-code:latest)"
  echo "  --rm                    Remove container after exit (default: persistent)"
  echo "  --no-interactive        Run in non-interactive mode"
  echo "  --no-privileged         Run without privileged mode"
  echo "  --safe                  Disable dangerous permissions"
  echo "  --build                 Build the Docker image and exit"
  echo "  --rebuild               Force rebuild the Docker image and continue"
  echo "  --recreate              Remove existing container and create new one"
  echo "  --verbose               Show detailed output including Docker commands"
  echo "  --remove-containers     Remove stopped Claude Code containers and exit"
  echo "  --force-remove-all-containers"
  echo "                          Remove ALL Claude Code containers (including active ones) and exit"
  echo "  --export-dockerfile FILE"
  echo "                          Export the embedded Dockerfile to specified file and exit"
  echo "  --push-to REPO          Tag and push image to repository (e.g., docker.io/user/repo:tag)"
  echo "  --generate-completions SHELL"
  echo "                          Generate shell completions (bash|zsh) and exit"
  echo "  -h, --help              Show this help"
  echo ""
  echo "EXAMPLES:"
  echo "  # Interactive shell"
  echo "  $0"
  echo ""
  echo "  # Run specific command"
  echo "  $0 claude --dangerously-skip-permissions 'help me with this project'"
  echo ""
  echo "  # Custom workspace"
  echo "  $0 -w /path/to/project"
  echo ""
  echo "  # One-shot command with cleanup"
  echo "  $0 --rm --no-interactive claude auth status"
  echo ""
  echo "  # Build image only"
  echo "  $0 --build"
  echo ""
  echo "  # Force rebuild image and run"
  echo "  $0 --rebuild"
  echo ""
  echo "  # Push to Docker Hub"
  echo "  $0 --push-to docker.io/username/claude-code:latest"
  echo ""
  echo "  # Install shell completions"
  echo "  # For bash:"
  echo "  echo 'eval \"\$($0 --generate-completions bash)\"' >> ~/.bashrc"
  echo ""
  echo "  # For zsh:"
  echo "  echo 'eval \"\$($0 --generate-completions zsh)\"' >> ~/.zshrc"
  echo ""
  echo "ENVIRONMENT VARIABLES:"
  echo "  CLAUDE_CODE_IMAGE_NAME  Override the default Docker Hub image (default: icanhasjonas/claude-code)"
  echo "                          Note: :latest tag is automatically appended"
  echo ""
  echo "  # Use custom image:"
  echo "  CLAUDE_CODE_IMAGE_NAME=myregistry/my-claude-code $0"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -w | --workspace)
    WORKSPACE_PATH="$2"
    shift 2
    ;;
  -c | --claude-config)
    CLAUDE_CONFIG_PATH="$2"
    shift 2
    ;;
  -n | --name)
    CONTAINER_NAME="$2"
    shift 2
    ;;
  -i | --image)
    IMAGE_NAME="$2"
    shift 2
    ;;
  --rm)
    REMOVE_CONTAINER=true
    shift
    ;;
  --no-interactive)
    INTERACTIVE=false
    shift
    ;;
  --no-privileged)
    PRIVILEGED=false
    shift
    ;;
  --safe)
    DANGEROUS_MODE=false
    shift
    ;;
  --build)
    BUILD_ONLY=true
    shift
    ;;
  --rebuild)
    FORCE_REBUILD=true
    shift
    ;;
  --recreate)
    RECREATE_CONTAINER=true
    shift
    ;;
  --verbose)
    VERBOSE=true
    shift
    ;;
  --remove-containers)
    REMOVE_CONTAINERS=true
    shift
    ;;
  --force-remove-all-containers)
    FORCE_REMOVE_ALL_CONTAINERS=true
    shift
    ;;
  --export-dockerfile)
    EXPORT_DOCKERFILE="$2"
    shift 2
    ;;
  --push-to)
    PUSH_TO_REPO="$2"
    shift 2
    ;;
  --generate-completions)
    generate_completions "$2"
    exit 0
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    # Remaining arguments are the command to run
    break
    ;;
  esac
done

# Validate paths
if [[ ! -d "$WORKSPACE_PATH" ]]; then
  echo -e "${RED}Error: Workspace path does not exist: $WORKSPACE_PATH${NC}"
  exit 1
fi

if [[ ! -d "$CLAUDE_CONFIG_PATH" ]]; then
  echo -e "${YELLOW}Warning: Claude config path does not exist: $CLAUDE_CONFIG_PATH${NC}"
  echo -e "${YELLOW}You may need to run 'claude auth' first${NC}"
fi

# Build docker run command
DOCKER_CMD="docker run"

if [[ "$REMOVE_CONTAINER" == "true" ]]; then
  DOCKER_CMD="$DOCKER_CMD --rm"
fi

if [[ "$INTERACTIVE" == "true" ]]; then
  DOCKER_CMD="$DOCKER_CMD -it"
fi

if [[ "$PRIVILEGED" == "true" ]]; then
  DOCKER_CMD="$DOCKER_CMD --privileged"
fi

DOCKER_CMD="$DOCKER_CMD --name $CONTAINER_NAME"

# Add labels for container identification
DOCKER_CMD="$DOCKER_CMD --label run-claude.managed=true"
DOCKER_CMD="$DOCKER_CMD --label run-claude.workspace=$WORKSPACE_PATH"
DOCKER_CMD="$DOCKER_CMD --label run-claude.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Get current user info
CURRENT_USER=$(whoami)

# Get basename of workspace for container mapping
WORKSPACE_BASENAME=$(basename "$WORKSPACE_PATH")

# Add environment variables
DOCKER_CMD="$DOCKER_CMD -e NODE_OPTIONS=--max-old-space-size=8192"
DOCKER_CMD="$DOCKER_CMD -e WORKSPACE_PATH=/home/$CURRENT_USER/$WORKSPACE_BASENAME"
DOCKER_CMD="$DOCKER_CMD -e CLAUDE_CONFIG_PATH=/home/$CURRENT_USER/.claude"
DOCKER_CMD="$DOCKER_CMD -e CONTAINER_USER=$CURRENT_USER"

if [[ "$DANGEROUS_MODE" == "true" ]]; then
  DOCKER_CMD="$DOCKER_CMD -e CLAUDE_DANGEROUS_MODE=1"
  DOCKER_CMD="$DOCKER_CMD -e ANTHROPIC_DANGEROUS_MODE=1"
fi

# Forward API keys and secrets if they exist
if [[ -n "$OPENAI_API_KEY" ]]; then
  DOCKER_CMD="$DOCKER_CMD -e OPENAI_API_KEY=$OPENAI_API_KEY"
fi

if [[ -n "$NUGET_API_KEY" ]]; then
  DOCKER_CMD="$DOCKER_CMD -e NUGET_API_KEY=$NUGET_API_KEY"
fi

if [[ -n "$UNSPLASH_ACCESS_KEY" ]]; then
  DOCKER_CMD="$DOCKER_CMD -e UNSPLASH_ACCESS_KEY=$UNSPLASH_ACCESS_KEY"
fi

# Forward OAuth account if it exists
if [[ -f "$HOME/.claude.json" ]]; then
  OAUTH_ACCOUNT=$(jq -c '.oauthAccount // empty' "$HOME/.claude.json" 2>/dev/null || echo "")
  if [[ -n "$OAUTH_ACCOUNT" && "$OAUTH_ACCOUNT" != "null" && "$OAUTH_ACCOUNT" != '""' ]]; then
    # Base64 encode to avoid shell escaping issues
    OAUTH_ACCOUNT_B64=$(printf '%s' "$OAUTH_ACCOUNT" | base64 | tr -d '\n')
    if [[ "$VERBOSE" == "true" ]]; then
      echo -e "${YELLOW}OAuth account detected and will be merged in container${NC}"
    fi
    DOCKER_CMD="$DOCKER_CMD -e CLAUDE_OAUTH_ACCOUNT_B64=$OAUTH_ACCOUNT_B64"
  fi
fi

# Add volume mounts
DOCKER_CMD="$DOCKER_CMD -v $CLAUDE_CONFIG_PATH:/home/$CURRENT_USER/.claude"
DOCKER_CMD="$DOCKER_CMD -v $WORKSPACE_PATH:/home/$CURRENT_USER/$WORKSPACE_BASENAME"

# Add optional read-only mounts if they exist
if [[ -d "$HOME/.ssh" ]]; then
  DOCKER_CMD="$DOCKER_CMD -v $HOME/.ssh:/home/$CURRENT_USER/.ssh:ro"
fi

if [[ -f "$HOME/.gitconfig" ]]; then
  DOCKER_CMD="$DOCKER_CMD -v $HOME/.gitconfig:/home/$CURRENT_USER/.gitconfig:ro"
fi

# Add image name
DOCKER_CMD="$DOCKER_CMD $IMAGE_NAME"

# Add command if provided
if [[ $# -gt 0 ]]; then
  DOCKER_CMD="$DOCKER_CMD $*"
fi

# Print what we're about to run
if [[ "$VERBOSE" == "true" ]]; then
  echo -e "${GREEN}Running Claude Code container...${NC}"
  echo -e "${YELLOW}Container name: $CONTAINER_NAME${NC}"
  echo -e "${YELLOW}Workspace: $WORKSPACE_PATH${NC}"
  echo -e "${YELLOW}Command: $DOCKER_CMD${NC}"
  echo ""
fi

# Function to build Docker image
build_image() {
  echo -e "${MAGENTA}Building Docker image ${BRIGHT_CYAN}$IMAGE_NAME${MAGENTA}...${NC}"

  # Create temporary directory for Dockerfile
  TEMP_DIR=$(mktemp -d)
  trap "rm -rf $TEMP_DIR" EXIT

  # Generate Dockerfile using shared function
  generate_dockerfile_content >"$TEMP_DIR/Dockerfile"

  # Build the image
  if docker build --build-arg USERNAME="$CURRENT_USER" -t "$IMAGE_NAME" "$TEMP_DIR"; then
    echo -e "${MAGENTA}Successfully built ${BRIGHT_CYAN}$IMAGE_NAME${NC}"
  else
    echo -e "${RED}Failed to build Docker image${NC}"
    exit 1
  fi
}

# Function to pull and tag remote image
pull_remote_image() {
  local REMOTE_IMAGE="${CLAUDE_CODE_IMAGE_NAME:-icanhasjonas/claude-code}:latest"
  
  echo -e "${MAGENTA}Pulling remote image ${BRIGHT_CYAN}$REMOTE_IMAGE${MAGENTA}...${NC}"
  if docker pull "$REMOTE_IMAGE"; then
    echo -e "${MAGENTA}Successfully pulled ${BRIGHT_CYAN}$REMOTE_IMAGE${NC}"
    echo -e "${MAGENTA}Tagging as ${BRIGHT_CYAN}$IMAGE_NAME${MAGENTA}...${NC}"
    if docker tag "$REMOTE_IMAGE" "$IMAGE_NAME"; then
      echo -e "${MAGENTA}Successfully tagged as ${BRIGHT_CYAN}$IMAGE_NAME${NC}"
    else
      echo -e "${RED}Failed to tag remote image${NC}"
      echo -e "${YELLOW}Falling back to building from source...${NC}"
      build_image
    fi
  else
    echo -e "${YELLOW}Failed to pull remote image. Building from source...${NC}"
    build_image
  fi
}

# Function to check if image exists and pull/build if necessary
build_image_if_missing() {
  if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo -e "${YELLOW}Docker image $IMAGE_NAME not found.${NC}"
    pull_remote_image
  fi
}

# Function to remove stopped Claude Code containers using labels
remove_stopped_containers() {
  echo -e "${GREEN}Searching for Claude Code containers...${NC}"

  # Find all containers with our label
  ALL_CONTAINERS=$(docker ps -aq --filter "label=run-claude.managed=true" 2>/dev/null || true)

  if [[ -z "$ALL_CONTAINERS" ]]; then
    echo -e "${YELLOW}No Claude Code containers found.${NC}"
    return 0
  fi

  # Find running containers with our label
  RUNNING_CONTAINERS=$(docker ps -q --filter "label=run-claude.managed=true" 2>/dev/null || true)

  # Find stopped containers (all - running)
  STOPPED_CONTAINERS=""
  for container in $ALL_CONTAINERS; do
    if ! echo "$RUNNING_CONTAINERS" | grep -q "$container"; then
      STOPPED_CONTAINERS="$STOPPED_CONTAINERS $container"
    fi
  done

  # Display all containers with status
  echo -e "${YELLOW}Found the following Claude Code containers:${NC}"
  docker ps -a --filter "label=run-claude.managed=true" --format "table {{.Names}}\t{{.Status}}\t{{.Label \"run-claude.workspace\"}}" 2>/dev/null || true
  echo ""

  # Handle running containers
  if [[ -n "$RUNNING_CONTAINERS" ]]; then
    echo -e "${YELLOW}Active containers (not removed):${NC}"
    for container in $RUNNING_CONTAINERS; do
      CONTAINER_NAME=$(docker inspect --format '{{.Name}}' "$container" | sed 's|^/||')
      echo -e "${YELLOW}  - $CONTAINER_NAME (running)${NC}"
      echo -e "    ${GREEN}To force remove:${NC}"
      echo -e "      \033[2mdocker stop \033[1m$CONTAINER_NAME\033[0m\033[2m && docker rm \033[1m$CONTAINER_NAME\033[0m"
    done
    echo ""
  fi

  # Remove stopped containers
  if [[ -n "$(echo $STOPPED_CONTAINERS | xargs)" ]]; then
    echo -e "${GREEN}Removing stopped containers...${NC}"
    docker rm $(echo $STOPPED_CONTAINERS | xargs) >/dev/null 2>&1 || true
    echo -e "${GREEN}Stopped Claude Code containers have been removed.${NC}"
  else
    echo -e "${YELLOW}No stopped containers to remove.${NC}"
  fi
}

# Function to force remove ALL Claude Code containers with warning
force_remove_all_containers() {
  echo -e "${RED}⚠️  WARNING: Force removing ALL Claude Code containers!${NC}"
  echo -e "${RED}This will STOP and DELETE all containers, including active ones.${NC}"
  echo -e "${RED}Any unsaved work in running containers will be LOST!${NC}"
  echo ""

  # Find all containers with our label
  ALL_CONTAINERS=$(docker ps -aq --filter "label=run-claude.managed=true" 2>/dev/null || true)

  if [[ -z "$ALL_CONTAINERS" ]]; then
    echo -e "${YELLOW}No Claude Code containers found.${NC}"
    return 0
  fi

  # Display all containers with status
  echo -e "${YELLOW}Found the following Claude Code containers:${NC}"
  docker ps -a --filter "label=run-claude.managed=true" --format "table {{.Names}}\t{{.Status}}\t{{.Label \"run-claude.workspace\"}}" 2>/dev/null || true
  echo ""

  # Ask for confirmation
  echo -e "${RED}Are you sure you want to force remove ALL containers? [y/N]:${NC} "
  read -r CONFIRM

  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    return 0
  fi

  echo ""
  echo -e "${GREEN}Force stopping all containers...${NC}"
  docker stop $ALL_CONTAINERS >/dev/null 2>&1 || true

  echo -e "${GREEN}Removing all containers...${NC}"
  docker rm $ALL_CONTAINERS >/dev/null 2>&1 || true

  echo -e "${GREEN}All Claude Code containers have been force removed.${NC}"
}

# Function to generate Dockerfile content
generate_dockerfile_content() {
  cat <<'DOCKERFILE_EOF'
# vim: set ft=dockerfile:

# ============================================================================
# Stage 1: Base tools and development environment
# ============================================================================
FROM ubuntu:25.04 AS base-tools

# Install system dependencies including zsh and tools
RUN apt-get update && apt-get install -y \
	build-essential \
	ca-certificates \
	curl \
	wget \
	git \
	python3 \
	unzip \
	python3-pip \
	sudo \
	fzf \
	zsh \
	gh \
	vim \
	neovim \
	htop \
	jq \
	tree \
	ripgrep \
	fd-find \
	&& rm -rf /var/lib/apt/lists/*

# Install Go
RUN ARCH=$(dpkg --print-architecture) && \
	if [ "$ARCH" = "amd64" ]; then GOARCH="amd64"; else GOARCH="arm64"; fi && \
	wget -O go.tar.gz "https://go.dev/dl/go1.21.5.linux-${GOARCH}.tar.gz" \
	&& tar -C /usr/local -xzf go.tar.gz \
	&& rm go.tar.gz
ENV PATH=/usr/local/go/bin:$PATH
ENV CGO_ENABLED=0

# Create user
ARG USERNAME
RUN useradd -m -s /bin/zsh ${USERNAME:-claude} \
	&& echo ${USERNAME:-claude} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${USERNAME:-claude} \
	&& chmod 0440 /etc/sudoers.d/${USERNAME:-claude}

# Build and install Unsplash MCP server
WORKDIR /tmp
RUN git config --global url."https://github.com/".insteadOf git@github.com: \
	&& git clone https://github.com/douglarek/unsplash-mcp-server.git \
	&& cd unsplash-mcp-server \
	&& go build -o /usr/local/bin/unsplash-mcp-server ./cmd/server \
	&& git config --global --unset url."https://github.com/".insteadOf

# ============================================================================
# Stage 2: User environment setup (zsh, fnm, node)
# ============================================================================
FROM base-tools AS user-env

# Switch to user and setup zsh with oh-my-zsh
USER $USERNAME
WORKDIR /home/$USERNAME

# Set up oh-my-zsh and plugins
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
	&& git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
	&& git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Setup fnm for user
RUN curl -o- https://fnm.vercel.app/install | bash
ENV PATH="/home/$USERNAME/.local/share/fnm:$PATH"
SHELL ["/bin/bash", "-c"]
RUN eval "$(fnm env)" && fnm install 22 && fnm default 22 && fnm use 22


# Install LazyVim
RUN git clone https://github.com/LazyVim/starter ~/.config/nvim \
	&& rm -rf ~/.config/nvim/.git

RUN nvim --headless "+Lazy! sync" +qa

# ============================================================================
# Stage 3: Claude and MCP servers
# ============================================================================
FROM user-env AS claude-mcp

# Install Claude CLI
RUN eval "$(fnm env)" && curl -fsSL https://claude.ai/install.sh | bash
ENV PATH=/home/$USERNAME/.local/bin:$PATH

# Install Playwright MCP via npm
RUN eval "$(fnm env)" && npm install -g @playwright/mcp@latest

# Setup MCP servers using claude mcp add
RUN eval "$(fnm env)" && claude mcp add unsplash \
	--scope user \
	/usr/local/bin/unsplash-mcp-server

RUN eval "$(fnm env)" && claude mcp add context7 \
	--scope user \
  --transport http \
	https://mcp.context7.com/mcp

RUN eval "$(fnm env)" && claude mcp add playwright \
	--scope user \
	npx @playwright/mcp@latest

# ============================================================================
# Stage 4: Final runtime image
# ============================================================================
FROM claude-mcp AS final

# Create entrypoint script that handles workspace directory change (as root)
USER root
RUN cat > /entrypoint.sh << 'EOF'
#!/bin/sh

# Merge OAuth account if provided
if [ -n "$CLAUDE_OAUTH_ACCOUNT_B64" ]; then
  CLAUDE_JSON="$HOME/.claude.json"
  
  # Decode base64 OAuth account
  CLAUDE_OAUTH_ACCOUNT=$(echo "$CLAUDE_OAUTH_ACCOUNT_B64" | tr -d '\n' | base64 -d)
  
  if [ ! -f "$CLAUDE_JSON" ] || ! jq -e '.oauthAccount' "$CLAUDE_JSON" >/dev/null 2>&1; then
    if [ -f "$CLAUDE_JSON" ]; then
      # Merge with existing file
      cat "$CLAUDE_JSON" | jq --argjson oauth "$CLAUDE_OAUTH_ACCOUNT" '.oauthAccount = $oauth' > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
    else
      # Create new file with OAuth account
      echo "{\"oauthAccount\": $CLAUDE_OAUTH_ACCOUNT}" | jq . > "$CLAUDE_JSON"
    fi
    echo "OAuth account merged into .claude.json"
  fi
  
  # Unset the environment variables for security
  unset CLAUDE_OAUTH_ACCOUNT_B64
  unset CLAUDE_OAUTH_ACCOUNT
fi

# Change to workspace directory if provided
if [ -n "$WORKSPACE_PATH" ] && [ -d "$WORKSPACE_PATH" ]; then
  cd "$WORKSPACE_PATH"
fi

exec "$@"
EOF
RUN chmod +x /entrypoint.sh

# Set working directory for user sessions
USER $USERNAME
WORKDIR /home/$USERNAME

# Configure zsh with theme, plugins, and aliases
RUN cat > ~/.zshrc << 'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

# Colorful prompt prefix
export PS1="%F{red}[%F{yellow}r%F{green}u%F{cyan}n%F{blue}-%F{magenta}c%F{red}l%F{yellow}a%F{green}u%F{cyan}d%F{blue}e%F{magenta}]%f $PS1"

# History configuration
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000

# Node version manager
eval "$(fnm env --use-on-cd --shell zsh)"

# Claude aliases - conditional based on dangerous mode
if [ "$CLAUDE_DANGEROUS_MODE" = "1" ] || [ "$ANTHROPIC_DANGEROUS_MODE" = "1" ]; then
	alias claude="claude --dangerously-skip-permissions"
fi
alias claude-safe="command claude"

# General aliases
alias ll="ls -la"
alias vim="nvim"
alias vi="nvim"

# Git SSH configuration
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
EOF

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/zsh"]
DOCKERFILE_EOF
}

# Function to export Dockerfile
export_dockerfile() {
  local OUTPUT_FILE="$1"

  if [[ -z "$OUTPUT_FILE" ]]; then
    echo -e "${RED}Error: No output file specified${NC}"
    exit 1
  fi

  echo -e "${MAGENTA}Exporting Dockerfile to: ${BRIGHT_CYAN}$OUTPUT_FILE${NC}"

  # Use the shared function to generate content
  generate_dockerfile_content >"$OUTPUT_FILE"

  echo -e "${MAGENTA}Dockerfile exported successfully!${NC}"
  echo -e "${YELLOW}To build: docker build --build-arg USERNAME=\$(whoami) -t your-image-name .${NC}"
}

# Function to push image to repository
push_to_repository() {
  local REPO="$1"

  if [[ -z "$REPO" ]]; then
    echo -e "${RED}Error: No repository specified${NC}"
    exit 1
  fi

  echo -e "${MAGENTA}Pushing image to repository: ${BRIGHT_CYAN}$REPO${NC}"

  # Check if local image exists
  if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo -e "${YELLOW}Local image $IMAGE_NAME not found. Getting it first...${NC}"
    pull_remote_image
  fi

  # Tag the image for the target repository
  echo -e "${MAGENTA}Tagging image ${BRIGHT_CYAN}$IMAGE_NAME${MAGENTA} as ${BRIGHT_CYAN}$REPO${MAGENTA}...${NC}"
  if ! docker tag "$IMAGE_NAME" "$REPO"; then
    echo -e "${RED}Failed to tag image${NC}"
    exit 1
  fi

  # Push the image
  echo -e "${MAGENTA}Pushing ${BRIGHT_CYAN}$REPO${MAGENTA} to registry...${NC}"
  if docker push "$REPO"; then
    echo -e "${MAGENTA}Successfully pushed ${BRIGHT_CYAN}$REPO${NC}"
    echo -e "${MAGENTA}Image is now available at: ${BRIGHT_CYAN}$REPO${NC}"
  else
    echo -e "${RED}Failed to push image${NC}"
    echo -e "${YELLOW}Make sure you are logged in: docker login${NC}"
    exit 1
  fi
}

# Handle special commands
if [[ -n "$EXPORT_DOCKERFILE" ]]; then
  export_dockerfile "$EXPORT_DOCKERFILE"
  exit 0
fi

if [[ -n "$PUSH_TO_REPO" ]]; then
  push_to_repository "$PUSH_TO_REPO"
  exit 0
fi

if [[ "$REMOVE_CONTAINERS" == "true" ]]; then
  remove_stopped_containers
  exit 0
fi

if [[ "$FORCE_REMOVE_ALL_CONTAINERS" == "true" ]]; then
  force_remove_all_containers
  exit 0
fi

if [[ "$BUILD_ONLY" == "true" ]]; then
  build_image
  echo -e "${MAGENTA}Build complete. Exiting.${NC}"
  exit 0
fi

if [[ "$FORCE_REBUILD" == "true" ]]; then
  echo -e "${YELLOW}Force rebuild requested - cleaning up first...${NC}"

  # Remove containers first to avoid conflicts
  echo -e "${GREEN}Removing existing containers...${NC}"
  remove_stopped_containers

  # Remove the image
  if docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo -e "${YELLOW}Removing existing image $IMAGE_NAME...${NC}"
    docker rmi "$IMAGE_NAME"
  fi
  build_image
else
  # Check if image exists and build if necessary
  build_image_if_missing
fi

# Function to handle existing container
handle_existing_container() {
  if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${MAGENTA}Container ${BRIGHT_CYAN}$CONTAINER_NAME${MAGENTA} already exists.${NC}"

    # Check if container is running
    if docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
      echo -e "${MAGENTA}Container ${BRIGHT_CYAN}$CONTAINER_NAME${MAGENTA} is already running. Executing command in existing container...${NC}"
      if [[ $# -gt 0 ]]; then
        exec docker exec -it "$CONTAINER_NAME" "$@"
      else
        exec docker exec -it "$CONTAINER_NAME" /bin/zsh
      fi
    else
      echo -e "${MAGENTA}Container ${BRIGHT_CYAN}$CONTAINER_NAME${MAGENTA} exists but is not running. Starting it...${NC}"
      if [[ $# -gt 0 ]]; then
        # Start container and then execute command in it
        docker start "$CONTAINER_NAME" >/dev/null
        exec docker exec -it "$CONTAINER_NAME" "$@"
      else
        # Start container interactively
        exec docker start -i "$CONTAINER_NAME"
      fi
    fi
  fi
}

# Handle existing container removal if recreate is requested
if [[ "$RECREATE_CONTAINER" == "true" ]]; then
  if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${MAGENTA}Removing existing container ${BRIGHT_CYAN}$CONTAINER_NAME${MAGENTA}...${NC}"
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null
  fi
fi

# Handle existing container unless we want to remove it
if [[ "$REMOVE_CONTAINER" == "false" && "$RECREATE_CONTAINER" == "false" ]]; then
  handle_existing_container "$@"
fi

# Execute the command (for new containers or when --rm is used)
exec $DOCKER_CMD
