terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.11.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.3.2"
    }
  }
}

# Variables and Locals
# ===================================
locals {
  namespace      = "coder"
  use_kubeconfig = false

  jupyter-type-arg = "${data.coder_parameter.jupyter.value == "notebook" ? "Notebook" : "Server"}"
}

# Providers
# ===================================
provider "coder" {
}
provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = "/coder/isaic.kubeconfig"
}


# VM Data
# ===================================
resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = kubernetes_pod.main[0].id

  item {
    key   = "Disk Size"
    value = data.coder_parameter.disk_size.value
  }
  item {
    key   = "Image"
    value = data.coder_parameter.image.value
  }
  item {
    key   = "DotFile URL"
    value = data.coder_parameter.dotfiles_uri.value
  }
}

# Params
# ===================================
data "coder_parameter" "disk_size" {
  name        = "PVC storage size"
  type        = "number"
  description = "Number of GB of storage"
  icon        = "https://www.pngall.com/wp-content/uploads/5/Database-Storage-PNG-Clipart.png"
  validation {
    min       = 10
    max       = 50
    monotonic = "increasing"
  }
  mutable     = true
  default     = 10
}
data "coder_parameter" "image" {
  name         = "container_image"
  display_name = "Container Image"
  description = "What container image and language do you want?"
  default      = "sharp6292/coder-gpu"
  type         = "string"
  mutable      = true
  icon        = "https://www.docker.com/wp-content/uploads/2022/03/vertical-logo-monochromatic.png"
}
data "coder_parameter" "dotfiles_uri" {
  name         = "dotfiles_uri"
  display_name = "dotfiles URI"
  description  = <<-EOF
  Dotfiles repo URI (optional)

  see https://dotfiles.github.io
  EOF
  default      = "https://github.com/Sharpz7/dotfiles"
  type         = "string"
  mutable      = true
}
data "coder_parameter" "jupyter" {
  name        = "Jupyter IDE type"
  type        = "string"
  description = "What type of Jupyter do you want?"
  mutable     = true
  default     = "lab"
  icon        = "/icon/jupyter.svg"

  option {
    name = "Jupyter Lab"
    value = "lab"
    icon = "https://raw.githubusercontent.com/gist/egormkn/672764e7ce3bdaf549b62a5e70eece79/raw/559e34c690ea4765001d4ba0e715106edea7439f/jupyter-lab.svg"
  }
  option {
    name = "Jupyter Notebook"
    value = "notebook"
    icon = "https://codingbootcamps.io/wp-content/uploads/jupyter_notebook.png"
  }
}


# Applications
# ================================
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  display_name = "VS Code Web"
  slug         = "code-server"
  url          = "http://localhost:8000?folder=/home/coder/projects"
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/code.svg"
  subdomain    = true
  share        = "owner"
}
resource "coder_app" "jupyter" {
  agent_id     = coder_agent.main.id
  slug          = "j"
  display_name  = "Jupyter ${upper(data.coder_parameter.jupyter.value)}"
  icon          = "/icon/jupyter.svg"
  url           = "http://localhost:8888/"
  share         = "owner"
  subdomain     = true

  healthcheck {
    url       = "http://localhost:8888/healthz/"
    interval  = 10
    threshold = 20
  }
}
resource "coder_app" "filebrowser" {
  agent_id     = coder_agent.main.id
  display_name = "File Browser"
  slug         = "filebrowser"
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/database.svg"
  url          = "http://localhost:8070"
  subdomain    = true
  share        = "owner"
}
resource "coder_app" "testport" {
  agent_id     = coder_agent.main.id
  display_name = "Exposed Test Port (6262)"
  slug         = "testport"
  icon         = "https://cdn-icons-png.flaticon.com/512/2995/2995440.png"
  url          = "http://localhost:6262"
  subdomain    = true
  share        = "public"
}


# Agent Setup
# =================================================
resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"

  startup_script = <<EOT
    set -e
    # start jupyter
    jupyter ${data.coder_parameter.jupyter.value} --${local.jupyter-type-arg}App.token="" --ip="*" >/tmp/jupyter.log 2>&1 &

    sudo dockerd -H tcp://0.0.0.0:2375 --dns 8.8.8.8 >/dev/null 2>&1 &

    # Create user data directory
    mkdir -p ~/data
    mkdir -p ~/projects

    # Install and start filebrowser
    curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
    filebrowser --port 8070 --noauth --root /home/coder/data >/tmp/filebrowser.log 2>&1 &

    mkdir -p /tmp/code-server
    HASH=$(curl https://update.code.visualstudio.com/api/commits/stable/server-linux-x64-web | cut -d '"' -f 2)
    wget -O- https://az764295.vo.msecnd.net/stable/$HASH/vscode-server-linux-x64-web.tar.gz | tar -xz -C /tmp/code-server --strip-components=1 >/dev/null 2>&1

    if [ -n "$DOTFILES_URI" ]; then
      echo "Installing dotfiles from $DOTFILES_URI"
      coder dotfiles -y "$DOTFILES_URI"
    fi

    /tmp/code-server/bin/code-server --accept-server-license-terms serve-local --without-connection-token --telemetry-level off >/dev/null 2>&1 &
  EOT

  dir = "/home/coder"

  env = {
    GIT_AUTHOR_NAME     = "${data.coder_workspace.me.owner}"
    GIT_COMMITTER_NAME  = "${data.coder_workspace.me.owner}"
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace.me.owner_email}"
    GIT_COMMITTER_EMAIL = "${data.coder_workspace.me.owner_email}"
    DOTFILES_URI        = data.coder_parameter.dotfiles_uri.value != "" ? data.coder_parameter.dotfiles_uri.value : null
  }

  metadata {
    display_name = "CPU Usage Workspace"
    interval     = 10
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
  }

  metadata {
    display_name = "CPU Usage Host"
    interval     = 10
    key          = "2_cpu_usage"
    script       = "coder stat cpu --host"
  }

  metadata {
    display_name = "RAM Usage Host"
    interval     = 10
    key          = "3_ram_usage"
    script       = "coder stat mem --host"
  }

  metadata {
    display_name = "Disk Usage"
    interval     = 600
    key          = "6_disk_usage"
    script       = "coder stat disk $HOME"
  }
}

# Pod Setup
# =================================================
resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
    namespace = local.namespace
  }
  spec {
    container {
      name    = "dev"
      image   = data.coder_parameter.image.value
      command = ["sh", "-c", coder_agent.main.init_script]
      security_context {
        privileged = true
      }
      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }
      volume_mount {
        mount_path = "/home/coder"
        name       = "home"
        read_only  = false
      }
      volume_mount {
        mount_path = "/var/lib/docker"
        name       = "dind-storage"
        read_only  = false
      }
      volume_mount {
        mount_path = "/lib/modules"
        name       = "modules"
        read_only  = true
      }
      volume_mount {
        mount_path = "/sys/fs/cgroup"
        name       = "cgroup"
        read_only  = false
      }
      env {
        name  = "DOCKER_HOST"
        value = "0.0.0.0:2375"
      }

      resources {
        requests = {
          "nvidia.com/mig-2g.20gb" = "1"
          "cpu"    = "4"
          "memory" = "28Gi"
        }
        limits = {
          "nvidia.com/mig-2g.20gb" = "1"
          "cpu"    = "4"
          "memory" = "28Gi"
        }
      }
    }

    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home.metadata.0.name
        read_only  = false
      }
    }

    volume {
      name = "dind-storage"
      empty_dir {}
    }

    volume {
      name = "modules"
      host_path {
        path = "/lib/modules"
        type = "Directory"
      }
    }
    volume {
      name = "cgroup"
      host_path {
        path = "/sys/fs/cgroup"
        type = "Directory"
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}-home"
    namespace = local.namespace
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${data.coder_parameter.disk_size.value}Gi"
      }
    }
  }
  lifecycle {
    ignore_changes = all
  }
}

# Empties
# ===================================
data "coder_workspace" "me" {}
