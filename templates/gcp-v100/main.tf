terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.11.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 4.34.0"
    }
  }
}


# Variables and Locals
# ===================================
locals {
  zone         = "us-central1-a"
  machine_type = "n1-standard-4"
  gpu          = "nvidia-tesla-v100"

  jupyter-type-arg = "${data.coder_parameter.jupyter.value == "notebook" ? "Notebook" : "Server"}"

  linux_user = "coder"
}
variable "project_id" {
  description = "Which Google Compute Project should your workspace live in?"
}


# Providers
# ===================================
provider "coder" {
}
provider "google" {
  zone    = local.zone
  project = var.project_id
}


# Coder Params
# ===================================
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


# Displayed Args
# ===================================
resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = google_compute_instance.dev[0].id

  item {
    key   = "Machine Type"
    value = google_compute_instance.dev[0].machine_type
  }
  item {
    key = "GPU Type"
    value   = local.gpu
  }
  item {
    key   = "VM Zone"
    value = local.zone
  }
}


# Storage
# ===================================
resource "google_compute_disk" "root" {
  name  = "coder-${data.coder_workspace.me.id}-root"
  size  = 100
  type  = "pd-ssd"
  zone  = local.zone
  image = "projects/ml-images/global/images/c0-deeplearning-common-gpu-v20230807-debian-11-py310"
  lifecycle {
    ignore_changes = [name, image]
  }
}
resource "coder_metadata" "home_info" {
  resource_id = google_compute_disk.root.id

  item {
    key   = "size"
    value = "${google_compute_disk.root.size} GiB"
  }
}

# Resources
# =====================================
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


# VM Setup
# =====================================
resource "coder_agent" "main" {
  auth                   = "google-instance-identity"
  arch                   = "amd64"
  os                     = "linux"
  startup_script_timeout = 500
  startup_script         = <<-EOT
    set -e

    sudo apt install -y git python3-distutils python3-apt neofetch

    # Jupyter
    export PATH=$PATH:/home/coder/.local/bin
    pip3 install jupyterlab==3.5.2 notebook==6.5.2 jupyter-core==5.1.3
    jupyter ${data.coder_parameter.jupyter.value} --${local.jupyter-type-arg}App.token="" --ip="*" --port=8888 >/tmp/jupyter.log 2>&1 &

    # FileBrowser
    mkdir -p ~/data
    mkdir -p ~/projects
    curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
    filebrowser -p 8070 --noauth --root /home/coder/data >/tmp/filebrowser.log 2>&1 &

    mkdir -p ~/.coder-vscode
    curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' --output vscode_cli.tar.gz
    tar -xf vscode_cli.tar.gz -C ~/.coder-vscode

    if [ -n "$DOTFILES_URI" ]; then
      echo "Installing dotfiles from $DOTFILES_URI"
      coder dotfiles -y "$DOTFILES_URI"
    fi

    ~/.coder-vscode/code serve-web --log trace --verbose --accept-server-license-terms --without-connection-token --port 8000 --host 0.0.0.0 >/tmp/vscode.log 2>&1 &
  EOT

  env = {
    GIT_AUTHOR_NAME     = "${data.coder_workspace.me.owner}"
    GIT_COMMITTER_NAME  = "${data.coder_workspace.me.owner}"
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace.me.owner_email}"
    GIT_COMMITTER_EMAIL = "${data.coder_workspace.me.owner_email}"
    DOTFILES_URI        = data.coder_parameter.dotfiles_uri.value != "" ? data.coder_parameter.dotfiles_uri.value : null
  }

  metadata {
    key          = "cpu"
    display_name = "CPU Usage"
    interval     = 5
    timeout      = 5
    script       = <<-EOT
      #!/bin/bash
      set -e
      top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4 "%"}'
    EOT
  }
  metadata {
    key          = "memory"
    display_name = "Memory Usage"
    interval     = 5
    timeout      = 5
    script       = <<-EOT
      #!/bin/bash
      set -e
      free -m | awk 'NR==2{printf "%.2f%%\t", $3*100/$2 }'
    EOT
  }
  metadata {
    key          = "disk"
    display_name = "Disk Usage"
    interval     = 600 # every 10 minutes
    timeout      = 30  # df can take a while on large filesystems
    script       = <<-EOT
      #!/bin/bash
      set -e
      df /home/coder | awk '$NF=="/"{printf "%s", $5}'
    EOT
  }
  metadata {
    display_name = "GPU Usage"
    interval     = 10
    key          = "4_gpu_usage"
    script       = <<EOT
      (nvidia-smi 1> /dev/null 2> /dev/null) && (nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | awk '{printf "%s%%", $1}') || echo "N/A"
    EOT
  }
  metadata {
    display_name = "GPU Memory Usage"
    interval     = 10
    key          = "5_gpu_memory_usage"
    script       = <<EOT
      (nvidia-smi 1> /dev/null 2> /dev/null) && (nvidia-smi --query-gpu=utilization.memory --format=csv,noheader,nounits | awk '{printf "%s%%", $1}') || echo "N/A"
    EOT
  }
}
resource "google_compute_instance" "dev" {
  zone         = local.zone
  count        = data.coder_workspace.me.start_count
  name         = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}-root"
  machine_type = local.machine_type
  network_interface {
    network = "default"
    access_config {
      // Ephemeral public IP
    }
  }
  scheduling {
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
    preemptible         = true
    provisioning_model  = "SPOT"
  }
  guest_accelerator {
    count = 1
    type  = "projects/${var.project_id}/zones/${local.zone}/acceleratorTypes/${local.gpu}"
  }
  boot_disk {
    auto_delete = false
    source      = google_compute_disk.root.name
  }
  service_account {
    email  = data.google_compute_default_service_account.default.email
    scopes = ["cloud-platform"]
  }
  # The startup script runs as root with no $HOME environment set up, so instead of directly
  # running the agent init script, create a user (with a homedir, default shell and sudo
  # permissions) and execute the init script as that user.
  metadata_startup_script = <<EOMETA
#!/usr/bin/env sh
set -eux

# If user does not exist, create it and set up passwordless sudo
if ! id -u "${local.linux_user}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "${local.linux_user}"
  echo "${local.linux_user} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder-user
fi

echo 'export PATH=$PATH:/home/coder/.local/bin' >> /etc/profile

exec sudo -u "${local.linux_user}" sh -c '${coder_agent.main.init_script}'
EOMETA
}

# Empty
# ====================================
data "google_compute_default_service_account" "default" {
}

data "coder_workspace" "me" {
}
