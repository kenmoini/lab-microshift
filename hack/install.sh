#!/bin/bash

# This script installs MicroShift on a RHEL 8.x system
# All that is needed is a subscribed system with an extra disk attached to be added to the root VG (and maybe Git)

## Add that extra disk to the root VG
# check vgs for free space

# vgs

# Set the hostname
# hostnamectl set-hostname microshift.kemo.labs

# Install the Satellite CA
# rpm -Uvh http://satellite.kemo.labs/pub/katello-ca-consumer-latest.noarch.rpm

# Subscribe the system to Satellite
# subscription-manager register --org="Default_Organization" --activationkey="everything"

# Enable needed repos
subscription-manager repos \
  --enable rhocp-4.12-for-rhel-8-$(uname -i)-rpms \
  --enable fast-datapath-for-rhel-8-$(uname -i)-rpms

# Enable needed Community repos
dnf copr enable -y @redhat-et/microshift

# Install needed packages
dnf install -y cri-o cri-tools microshift firewalld bash-completion cockpit nano git

# Install the latest client tools
mkdir -p /tmp/ocbintmp
cd /tmp/ocbintmp

curl -O https://mirror.openshift.com/pub/openshift-v4/$(uname -m)/clients/ocp/stable/openshift-client-linux.tar.gz
tar -xf openshift-client-linux.tar.gz -C /usr/local/bin oc kubectl

# Install Kustomize
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash
mv kustomize /usr/local/bin/kustomize

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

cd -
rm -rf /tmp/ocbintmp

# Enable and start firewalld
systemctl enable firewalld --now

# Set firewall rules
firewall-cmd --zone=trusted --add-source=10.42.0.0/16 --permanent
firewall-cmd --zone=trusted --add-source=169.254.169.1 --permanent
firewall-cmd --zone=public --add-port=80/tcp --permanent
firewall-cmd --zone=public --add-port=443/tcp --permanent
firewall-cmd --zone=public --add-port=5353/udp --permanent
firewall-cmd --zone=public --add-port=6443/tcp --permanent
firewall-cmd --zone=public --add-service=cockpit --permanent
firewall-cmd --reload

## Copy your pull secret to /etc/crio/openshift-pull-secret
chown root:root /etc/crio/openshift-pull-secret
chmod 600 /etc/crio/openshift-pull-secret

# Enable CRIO
systemctl enable crio --now

# Enable and start cockpit
systemctl enable cockpit.socket --now

# Create the Configuration file for Microshift
cat << EOF > /etc/microshift/microshift.yaml
dns:
  baseDomain: $(hostname)
network:
  clusterNetwork:
    - cidr: 10.42.0.0/16
  serviceNetwork:
    - 10.43.0.0/16
  serviceNodePortRange: 30000-32767
node:
  hostnameOverride: ""
  nodeIP: ""
apiServer:
  subjectAltNames:
    - api.$(hostname)
    - api-int.$(hostname)
debugging:
  logLevel: "Normal"
EOF

# Enable and start MicroShift
systemctl enable microshift --now

# Create a kubeconfig file
mkdir -p ~/.kube
cat /var/lib/microshift/resources/kubeadmin/kubeconfig > ~/.kube/config
cp ~/.kube/config ~/.kube/remote-config

sed -i 's/127.0.0.1/api.'$(hostname)'/g' ~/.kube/remote-config

oc get pods -A