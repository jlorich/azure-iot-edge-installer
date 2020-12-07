# Azure IoT Edge Installer
A tool for making IoT Edge installations easier.  Currently targeted at RHEL7.5+ only.  Debian support will be coming later.

## Examples

#### Install IoT Edge

```
./edge-installer.sh install
```

#### Configure Upstream Protocol and Proxy Support

```
./edge-installer.sh configure AmqpWs http://proxy.cat.com
```

#### Configure DPS X509 Auth

```
./edge-installer.sh \
    auth dps x509 \
    SCOPE_ID \
    "file:///certs/iot-edge-device-identity-x509-1.cert.pem" \
    "file:///certs/iot-edge-device-identity-x509-1.cert.pem"
 ```
 
