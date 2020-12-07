set -e

###############################################################################
# Define Variables
###############################################################################
TMP_DIR="/tmp/iotedge"
EDGE_CONFIG_PATH="/etc/iotedge/config.yaml"
EDGE_CERT_STORE="/certs"


###############################################################################
# Install Dependencies
###############################################################################
function install_dependencies() {
    echo "Installing dependencies"
    echo "--------------------------------------------"

    echo "Initializing temp directory..."
    mkdir -p ${TMP_DIR}

    echo "Installing wget..."
    if rpm -q --quiet wget; then
        echo "- wget is already installed... skipping"
    else
        yum install wget
    fi

    echo "Installing yq"
    if [ -x "$(command -v yq)" ]; then
        echo "- ys is already installed... skipping"
    else
        wget -P ${TMP_DIR} https://github.com/mikefarah/yq/releases/download/3.4.1/yq_linux_amd64
        mv ${TMP_DIR}/yq_linux_amd64 /usr/local/bin/yq
        chmod +x /usr/local/bin/yq
        ln -s /usr/local/bin/yq /usr/bin/yq
    fi


    echo "Installing container-selinux"
    if rpm -q container-selinux --quiet; then
        echo "- container-selinux is already installed... skipping"
    else
        echo "- Configuring Microsoft RHEL repositories"
        rm -f /etc/yum/vars/releasever

        yum --disablerepo='*' remove 'rhui-azure-rhel7-eus'
        yum --config='https://rhelimage.blob.core.windows.net/repositories/rhui-microsoft-azure-rhel7.config' install 'rhui-azure-rhel7'

        echo "- Installing container-selinux"
        yum install container-selinux
    fi
}


###############################################################################
# Install the Moby CLI and Runtime
###############################################################################
function install_moby() {
    echo "Instal Moby CLI and Engine"
    echo "--------------------------------------------"

    echo "Installing Moby CLI"
    if rpm -q --quiet moby-cli; then
        echo "- Moby CLI is already installed... skipping"
    else
        wget -P ${TMP_DIR} https://packages.microsoft.com/centos/7/prod/moby-cli-3.0.10%2Bazure-0.x86_64.rpm
        yum install ${TMP_DIR}/moby-cli-3.0.10+azure-0.x86_64.rpm
    fi

    echo "Installing Moby Engine"
    if rpm -q --quiet moby-engine; then
        echo "- Moby Engine is already installed... skipping"
    else
        wget -P ${TMP_DIR} https://packages.microsoft.com/centos/7/prod/moby-engine-3.0.10%2Bazure-0.x86_64.rpm
        yum install ${TMP_DIR}/moby-engine-3.0.10+azure-0.x86_64.rpm
    fi
}

###############################################################################
# Install IoT Edge
###############################################################################
function install_edge()
{
    echo "Install IoT Edge"
    echo "--------------------------------------------"

    echo "Installing libiothsm-std"
    if rpm -q --quiet libiothsm-std; then
        echo "- libiothsm-std is already installed... skipping"
    else
        wget -P ${TMP_DIR} https://github.com/Azure/azure-iotedge/releases/download/1.0.10.2/libiothsm-std_1.0.10.2-1.el7.x86_64.rpm
        rpm -Uhv ${TMP_DIR}/libiothsm-std_1.0.10.2-1.el7.x86_64.rpm
    fi

    echo "Installing IoT Edge"
    if rpm -q --quiet iotedge; then
        echo "- IoT Edge is already installed... skipping"
    else
        wget -P ${TMP_DIR} https://github.com/Azure/azure-iotedge/releases/download/1.0.10.2/iotedge-1.0.10.2-1.el7.x86_64.rpm
        rpm -Uhv ${TMP_DIR}/iotedge-1.0.10.2-1.el7.x86_64.rpm
    fi
}


###############################################################################
# Clear Edge Cache
###############################################################################
function clear_cache()
{
    echo "Clear Edge Cache"
    echo "--------------------------------------------"

    echo "Removing HSM files"
    rm -f /var/lib/iotedge/hsm/certs/*
    rm -f /var/lib/iotedge/hsm/cert_keys/*
    rm -f /var/lib/iotedge/hsm/enc_keys/*

    echo "Removing Cache files"
    rm -f /var/lib/iotedge/cache/*
}


###############################################################################
# Set Proxy URLs
###############################################################################
function set_proxy()
{
    if [[ $# -ne 1 ]] || [[ -z ${1} ]]; then
        echo "Usage error: Please provide a <proxyUrl>"
        exit 1
    fi

    local proxy_url="${1}"

    echo "Set Edge Proxy"
    echo "--------------------------------------------"

    echo "Setting Docker Daemon Proxy"
    sudo mkdir -p /etc/systemd/system/docker.service.d

    { echo "[Service]";
      echo "Environment=\"http_proxy=${proxy_url}\"";
      echo "Environment=\"https_proxy=${proxy_url}\"";
    } > /etc/systemd/system/docker.service.d/http-proxy.conf


    echo "Setting Edge Daemon Proxy"
    {
      echo "[Service]";
      echo "Environment=\"https_proxy=${proxy_url}\"";
    } > /etc/systemd/system/iotedge.service.d/http-proxy.conf

    echo "Setting IoT Edge Agent Proxy"
    yq w -i ${EDGE_CONFIG_PATH} agent.env.https_proxy ${proxy_url}

    echo "Reloading and restarting processes"
    systemctl daemon-reload
    systemctl restart docker
    systemctl restart iotedge
}


###############################################################################
# Clear Proxy URLs
###############################################################################
function clear_proxy()
{
    echo "Clear Edge Proxy"
    echo "--------------------------------------------"

    echo "Clearing Docker Daemon Proxy"
    rm -f /etc/systemd/system/docker.service.d/http-proxy.conf
    rm -f /etc/systemd/system/docker.service.d/override.conf

    echo "Clearing Edge Daemon Proxy"
    rm -f /etc/systemd/system/iotedge.service.d/http-proxy.conf
    rm -f /etc/systemd/system/iotedge.service.d/override.conf

    systemctl daemon-reload
    systemctl restart docker

    echo "Clearing IoT Edge Agent Proxy"
    {yq d -i ${EDGE_CONFIG_PATH} agent.env.https_proxy} &> /dev/null
}


###############################################################################
# Set the IoT Edge Upstream Protocol
###############################################################################
function set_upstream_protocol()
{
    if [[ $# -ne 1 ]] || [[ -z ${1} ]]; then
        echo "Usage error: Please provide an <upstreamProtocol>"
        exit 1
    fi

    local upstream_protocol="${1}"

    yq w -i ${EDGE_CONFIG_PATH} agent.env.UpstreamProtocol ${upstream_protocol}

}

###############################################################################
# Set IoT Edge Authentication
###############################################################################
function set_auth()
{
    if [[ -z ${1} ]]; then
        echo "Usage error: Please provide a <source>"
        exit 1
    fi

    local source="${1}"

    echo "Deleting current provisioning settings"
    yq d -i ${EDGE_CONFIG_PATH} provisioning

    if [ ${source} == "manual" ]; then
        echo "Setting manual provisioning settings"

       if [[ -z ${2} ]]; then
            echo "Usage error: Please provide a <deviceConnectionString>"
            exit 1
        fi

        yq w -i ${EDGE_CONFIG_PATH} provisioning.source "manual"
        yq w -i ${EDGE_CONFIG_PATH} provisioning.device_connection_string "${2}"
        return
    elif [ ${source} == "dps" ]; then
        echo "Setting DPS provisioning settings"
        if [[ -z ${2} ]]; then
            echo "Usage error: Please provide a <method>"
            exit 1
        fi

        local method="${2}"

        if [[ -z ${3} ]]; then
            echo "Usage error: Please provide a <scopeId>"
            exit 1
        fi

        local scope_id="${3}"

        yq w -i ${EDGE_CONFIG_PATH} provisioning.source "dps"
        yq w -i ${EDGE_CONFIG_PATH} provisioning.global_endpoint "https://global.azure-devices-provisioning.net"
        yq w -i ${EDGE_CONFIG_PATH} provisioning.scope_id "${3}"

        if [ ${method} == "x509" ]; then
            yq w -i ${EDGE_CONFIG_PATH} provisioning.attestation.method "x509"
            yq w -i ${EDGE_CONFIG_PATH} provisioning.attestation.identity_cert "${4}"
            yq w -i ${EDGE_CONFIG_PATH} provisioning.attestation.identity_pk "${5}"
        fi
    fi
}


###############################################################################
# Set Proxy URLs
###############################################################################
function remove_edge()
{
    echo "Remove IoT Edge"
    echo "--------------------------------------------"

    echo "Removing IoT Edge"
    rpm -e iotedge || true

    echo "Removing libiothsm"
    rpm -e libiothsm || true

    echo "Clearning IoT Edge Cache"
    clear_cache || true

    echo "Clearing proxy settings"
    clear_proxy || true
}


if [ "${1}" == "install" ]; then
    install_dependencies
    install_moby
    install_edge
elif [ "${1}" == "configure" ]; then
    set_upstream_protocol "${2}"
    set_proxy "${3}"
elif [ "${1}" == "auth" ]; then
    set_auth "${2}" "${3}" "${4}" "${5}" "${6}"
elif [ "${1}" == "install_dependencies" ]; then
    install_dependencies
elif [ "${1}" == "install_moby" ]; then
    install_moby
elif [ "${1}" == "install_edge" ]; then
    install_edge
elif [ "${1}" == "clear_cache" ]; then
    clear_cache
elif [ "${1}" == "set_proxy" ]; then
    set_proxy "${2}"
elif [ "${1}" == "clear_proxy" ]; then
    clear_proxy
elif [ "${1}" == "set_upstream_protocol" ]; then
    set_upstream_protocol "${2}"
elif [ "${1}" == "remove" ]; then
    remove_edge
else
    echo "Usage: install                                  # Install IoT edge and all dependencies"
    echo "       auth <source> <args>                     # Configures authenticaiton"
    echo "            manual <deviceConnectionString>"    # Sets up manual auth with a connection string
    echo "            dps x509 <scopeId> <cert> <key>"    # Sets up auth with X.509 certs and DPS
    echo "       configure <upstreamProtocol> <proxyUrl>  # Configures common Edge settings"
    echo "       install_dependencies                     # Installs the required IoT Edge system dependencies"
    echo "       install_moby                             # Installs the Moby CLI and Engine"
    echo "       install_edge                             # Installs IoT Edge"
    echo "       clear_cache                              # Clears the IoT Edge Cache"
    echo "       clear_proxy                              # Clears the IoT Edge proxy settings"
    echo "       set_proxy <proxyUrl>                     # Set the IoT Edge Proxy URL"
    echo "       set_upstream_protocol <upstreamProtocol> # Configure Iot edge proxy"
    echo "       remove                                   # Remove edge and all dependencies"
    exit 1
fi
