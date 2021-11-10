#!/usr/bin/env bash

set -euo pipefail

: ${ADMIN_PASSWORD}
: ${AWS_REGION}
: ${S3_BUCKET}
: ${SUPERVISOR_ACCESS_TOKEN}

latest_release() {
    curl -sSL "https://api.github.com/repos/$1/releases/latest" | jq -r .tag_name
}

# I think there is a race condition related to Ubuntu wanting to do an
# automated system upgrade at boot, which causes 'apt-get update' to
# sometimes fail with an obscure error message.
sleep 5

mkdir /tmp/riju-work
pushd /tmp/riju-work

export DEBIAN_FRONTEND=noninteractive

sudo -E apt-get update
sudo -E apt-get dist-upgrade -y

sudo -E apt-get install -y curl gnupg lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo -E apt-key add -

ubuntu_name="$(lsb_release -cs)"

sudo tee -a /etc/apt/sources.list.d/custom.list >/dev/null <<EOF
deb [arch=amd64] https://download.docker.com/linux/ubuntu ${ubuntu_name} stable
EOF

sudo -E apt-get update
sudo -E apt-get install -y docker-ce docker-ce-cli containerd.io jq unzip whois

wget -nv https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -O awscli.zip
unzip -q awscli.zip
sudo ./aws/install

wget -nv https://s3.us-west-1.amazonaws.com/amazon-ssm-us-west-1/latest/debian_amd64/amazon-ssm-agent.deb

wget -nv https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo apt-get install -y ./amazon-cloudwatch-agent.deb

sudo chown root:root                                             \
     /tmp/cloudwatch.json /tmp/docker.json /tmp/riju.service     \
     /tmp/riju.slice /tmp/riju-init-volume /tmp/riju-supervisor

sudo mv /tmp/docker.json /etc/docker/daemon.json
sudo mv /tmp/riju.service /tmp/riju.slice /etc/systemd/system/
sudo mv /tmp/cloudwatch.json /opt/aws/amazon-cloudwatch-agent/bin/config.json
sudo mv /tmp/riju-init-volume /tmp/riju-supervisor /usr/local/bin/

sudo sed -Ei 's|^#?PermitRootLogin .*|PermitRootLogin no|' /etc/ssh/sshd_config
sudo sed -Ei 's|^#?PasswordAuthentication .*|PasswordAuthentication no|' /etc/ssh/sshd_config
sudo sed -Ei 's|^#?PermitEmptyPasswords .*|PermitEmptyPasswords no|' /etc/ssh/sshd_config
sudo sed -Ei "s|\\\$AWS_REGION|${AWS_REGION}|" /etc/systemd/system/riju.service
sudo sed -Ei "s|\\\$ANALYTICS_TAG|${ANALYTICS_TAG:-}|" /etc/systemd/system/riju.service
sudo sed -Ei "s|\\\$S3_BUCKET|${S3_BUCKET}|" /etc/systemd/system/riju.service
sudo sed -Ei "s|\\\$SENTRY_DSN|${SENTRY_DSN:-}|" /etc/systemd/system/riju.service
sudo sed -Ei "s|\\\$SUPERVISOR_ACCESS_TOKEN|${SUPERVISOR_ACCESS_TOKEN}|" /etc/systemd/system/riju.service

sudo passwd -l root
sudo useradd admin -g admin -G sudo -s /usr/bin/bash -p "$(echo "${ADMIN_PASSWORD}" | mkpasswd -s)" -m

sudo amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json
sudo systemctl enable riju

if [[ -n "${GRAFANA_API_KEY:-}" ]]; then
    ver="$(latest_release grafana/loki)"

    wget -nv "https://github.com/grafana/loki/releases/download/${ver}/promtail-linux-amd64.zip"
    unzip promtail-linux-amd64.zip
    sudo cp promtail-linux-amd64 /usr/local/bin/promtail

    sudo chown root:root /tmp/promtail.service /tmp/promtail.yaml

    sudo mkdir /etc/promtail
    sudo mv /tmp/promtail.yaml /etc/promtail/config.yaml
    sudo mv /tmp/promtail.service /etc/systemd/system/
    sudo sed -Ei "s/\\\$GRAFANA_API_KEY/${GRAFANA_API_KEY}/" /etc/promtail/config.yaml

    sudo systemctl enable promtail
else
    sudo rm /tmp/promtail.yaml /tmp/promtail.service
fi

sudo userdel ubuntu -f

popd
rm -rf /tmp/riju-work
