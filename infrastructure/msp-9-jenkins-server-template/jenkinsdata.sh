#!/bin/bash
# Kullanım: sudo bash /home/ec2-user/jenkinsdata.sh
set -euo pipefail

# Root kontrolü (dnf, systemctl vb. için gerekli)
if [ "$EUID" -ne 0 ]; then
    echo "Bu script root yetkisiyle çalışmalı: sudo bash /home/ec2-user/jenkinsdata.sh"
    exit 1
fi

# Docker grubuna eklenecek kullanıcı (sudo ile çalıştıran kullanıcı, yoksa ec2-user)
TARGET_USER="${SUDO_USER:-ec2-user}"

# Update operating system
dnf update -y

# Set server hostname
hostnamectl set-hostname jenkins-server

# Install required packages
# NOT: curl çıkarıldı, Amazon Linux 2023'te curl-minimal zaten kurulu (çakışma yapar)
dnf install -y \
    git \
    wget \
    unzip \
    fontconfig \
    java-21-amazon-corretto \
    docker \
    python3-pip \
    python3-devel

# Set Java 21 as default (yol sürüme göre değişebileceği için dinamik bulunur)
JAVA_BIN="$(ls /usr/lib/jvm/java-21-amazon-corretto*/bin/java 2>/dev/null | head -1 || true)"
if [ -n "$JAVA_BIN" ]; then
    alternatives --set java "$JAVA_BIN" || true
fi

# Verify Java version
java -version

# Install Jenkins repository
wget -O /etc/yum.repos.d/jenkins.repo \
    https://pkg.jenkins.io/rpm-stable/jenkins.repo

# Import Jenkins GPG key
rpm --import https://pkg.jenkins.io/rpm-stable/jenkins.io-2023.key

# Install Jenkins
dnf install -y jenkins

# Install and start Docker
systemctl enable --now docker

# Add users to Docker group
usermod -aG docker "$TARGET_USER"
usermod -aG docker jenkins

# Configure Docker as Jenkins cloud agent
mkdir -p /etc/systemd/system/docker.service.d

cat > /etc/systemd/system/docker.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H tcp://127.0.0.1:2376 -H unix:///var/run/docker.sock --containerd=/run/containerd/containerd.sock
EOF

# Reload systemd and restart Docker
systemctl daemon-reload
systemctl restart docker

# Start Jenkins after Docker
systemctl enable jenkins
systemctl restart jenkins

# Install Docker Compose
curl -SL \
    https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
    -o /usr/local/bin/docker-compose

chmod +x /usr/local/bin/docker-compose

# Install Ansible
python3 -m pip install --upgrade ansible

# Install AWS Python SDK
python3 -m pip install --upgrade boto3 botocore

# Install Terraform (güncel sürüm otomatik bulunur, olmazsa yedek sürüm kullanılır)
TERRAFORM_VERSION="$(curl -fsS https://checkpoint-api.hashicorp.com/v1/check/terraform \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["current_version"])' 2>/dev/null || true)"
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.9.8}"
echo "Terraform sürümü: ${TERRAFORM_VERSION}"

wget \
    "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    -O /tmp/terraform.zip

unzip -o /tmp/terraform.zip -d /usr/local/bin

rm -f /tmp/terraform.zip

# Verify installations
export PATH="$PATH:/usr/local/bin"
git --version
java -version
docker --version
docker-compose --version
ansible --version
terraform version

echo "Jenkins server setup completed successfully."
echo "Docker grubunun aktif olması için çıkış yapıp tekrar SSH ile bağlan."
echo "Jenkins ilk şifre: sudo cat /var/lib/jenkins/secrets/initialAdminPassword"