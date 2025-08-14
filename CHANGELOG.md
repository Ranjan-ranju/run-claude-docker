# Changelog

All notable changes to the run-claude Docker wrapper script will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-08-15

### Added
- **Multi-User Support**: User-specific Docker image names (`claude-code-{USERNAME}:latest`) to prevent conflicts on shared servers
- **Version Management**: Script versioning with version mismatch detection and upgrade warnings
- **Comprehensive Authentication Forwarding**:
  - SSH agent socket forwarding with conditional detection
  - GPG agent forwarding with cross-platform support and user control options
  - Claude config bind-mounting replacing base64 encoding
- **Enhanced Security & Configuration**:
  - `--no-gpg` and `--gpg` flags for GPG control
  - `RUN_CLAUDE_NO_GPG` environment variable support  
  - Integration with `--safe` mode
  - Local-only Docker builds (removed automatic external pulls)
- **Development Tools**:
  - git-delta package for enhanced git diff output with syntax highlighting
- **Improved User Experience**:
  - Verbose mode forwarding to containers (`RUN_CLAUDE_VERBOSE=1`)
  - Enhanced ANSI color coding (dark magenta for text, bright cyan for variables)
  - Container labeling system for better tracking and management
  - Professional shell completions for bash and zsh

### Changed
- **BREAKING**: Removed automatic docker pull from external registries - users must build locally
- **BREAKING**: USERNAME defaults to `$(whoami)` for Claude authentication compatibility
- Enhanced Dockerfile with multi-stage builds for better caching
- Improved container lifecycle management with interactive restart
- Better error handling and user guidance throughout

### Security
- Replaced base64 config encoding with secure bind-mounting
- Implemented local-only container builds
- Added comprehensive user tracking and container isolation

---

## [0.9.x] - Development Phase (2025-08-14)

### Added
- **Core Infrastructure**:
  - Docker wrapper script with workspace-based container naming
  - Unique container identification using workspace path hash
  - MIT License for open source distribution

- **Container Management**:
  - `--remove-containers` for safe container cleanup
  - `--force-remove-all-containers` with interactive confirmation
  - `--rebuild` and `--recreate` options for development workflow
  - `--export-dockerfile` for standalone Dockerfile generation

- **Advanced Features**:
  - `--push-to` command for Docker registry publishing
  - Host network support for localhost service access
  - TERM environment variable forwarding
  - Comprehensive OAuth and config merging

- **Developer Experience**:
  - Verbose mode with detailed Docker execution information
  - Colorful rainbow zsh prompt in containers
  - Auto-cd to workspace directory on container start
  - Shell completion support (bash/zsh)

- **Documentation**:
  - Detailed ASCII workflow diagrams
  - Comprehensive README with setup instructions
  - Contributing guidelines and development workflow

### Technical Improvements
- Multi-stage Dockerfile optimization for faster builds
- Proper layer caching strategies
- Enhanced error handling and user feedback
- Professional ANSI color theming throughout
- Docker label-based container identification

---

## Project Overview

**run-claude** is a Docker wrapper script that provides a secure, isolated environment for running Claude Code with comprehensive authentication forwarding and multi-user support.

### Key Features
- 🐳 **Containerized Claude Environment**: Full Docker isolation with development tools
- 🔐 **Authentication Forwarding**: SSH, GPG, and Claude config passthrough  
- 👥 **Multi-User Support**: User-specific images prevent conflicts on shared servers
- 🎨 **Enhanced UX**: Colorful output, verbose modes, and professional shell completions
- 🛡️ **Security First**: Local builds only, secure config mounting, comprehensive user tracking
- ⚡ **Developer Optimized**: Fast rebuilds, workspace isolation, and convenient management commands

### Architecture
The script creates isolated Docker containers with:
- Ubuntu base with essential development tools
- Node.js, Go, Python environments pre-configured
- LazyVim and oh-my-zsh for enhanced development experience
- Secure mounting of host credentials and configurations
- Automatic workspace detection and container naming

For detailed usage instructions, see the [README.md](README.md).