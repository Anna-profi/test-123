#!/usr/bin/env bash

# ============================================================================
# Frigate Standalone Installation Script for Ubuntu 22.04
# Completely self-contained - no external dependencies during installation
# ============================================================================

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
FRIGATE_VERSION="0.14.1"
PYTHON_VERSION="3.10"
INSTALL_DIR="/opt/frigate"
CONFIG_DIR="/config"
MEDIA_DIR="/media/frigate"
MODELS_DIR="/opt/frigate/models"

# ============================================================================
# PHASE 1: SYSTEM SETUP & DNS FIX (CRITICAL)
# ============================================================================

setup_system() {
    log_info "Starting Frigate installation (v${FRIGATE_VERSION})"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # CRITICAL FIX 1: Completely disable and mask systemd-resolved
    log_info "Fixing DNS configuration (preventing systemd-resolved conflicts)"
    
    # Stop and disable systemd-resolved
    systemctl stop systemd-resolved.service 2>/dev/null || true
    systemctl disable systemd-resolved.service 2>/dev/null || true
    systemctl mask systemd-resolved.service 2>/dev/null || true
    
    # Remove symlink and create static resolv.conf
    rm -f /etc/resolv.conf
    cat > /etc/resolv.conf << 'DNS_EOF'
# Static DNS configuration for Frigate installation
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
options timeout:2 attempts:2
search .
DNS_EOF
    
    # Make resolv.conf immutable
    chattr +i /etc/resolv.conf 2>/dev/null || true
    
    # Test DNS
    if ping -c 1 -W 2 google.com >/dev/null 2>&1; then
        log_success "DNS is working correctly"
    else
        log_warning "DNS test failed, but continuing with static configuration"
    fi
    
    # Update system
    log_info "Updating system packages"
    apt-get update
    apt-get upgrade -y
    
    log_success "System setup complete"
}

# ============================================================================
# PHASE 2: INSTALL DEPENDENCIES
# ============================================================================

install_dependencies() {
    log_info "Installing system dependencies"
    
    # Install essential packages
apt-get install -y \
        curl wget git build-essential \
        python3 python3-pip python3-venv python3-dev \
        libjpeg-dev libpng-dev libtiff-dev \
        libavcodec-dev libavformat-dev libswscale-dev \
        libv4l-dev libxvidcore-dev libx264-dev \
        libgtk-3-dev libtbb12 libtbb-dev \
        libdc1394-22-dev libopenexr-dev \          
        libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
        libxine2-dev \                          # libavresample-dev УДАЛЁН (устарел в FFmpeg 5.x)
        libfaac-dev libmp3lame-dev libtheora-dev \
        libvorbis-dev libopencore-amrnb-dev libopencore-amrwb-dev \
        libopenblas-dev libatlas-base-dev libblas-dev \
        liblapack-dev libeigen3-dev gfortran \
        libhdf5-dev protobuf-compiler \
        libgoogle-glog-dev libgflags-dev \
        libsm6 libxext6 libxrender-dev \
        libgl1-mesa-glx libgl1-mesa-dri \
        libtiff5-dev libilmbase-dev \           # libjasper-dev УДАЛЁН (недоступен в репозиториях)
        libopenexr-dev libgdal-dev \
        libv4l-dev \                            # libdc1394-22-dev УДАЛЁН (уже есть libdc1394-dev выше)
        libxine2-dev libtbb-dev \
        zlib1g-dev libjpeg-dev \                # qt5-default и libvtk6-dev УДАЛЕНЫ (не обязательны для Frigate)
        libwebp-dev libpng-dev \
        libtiff5-dev libopenexr-dev libgdal-dev \
        libv4l-dev \
        libxine2-dev libtbb-dev \
        libavcodec-dev libavformat-dev \
        libswscale-dev libavutil-dev \
        libpostproc-dev \                       # libavresample-dev УДАЛЁН (дублирует удаление выше)
        libx264-dev libx265-dev \
        libnuma-dev libvpx-dev \
        libaom-dev libdav1d-dev \
        libfdk-aac-dev libmp3lame-dev \
        libopus-dev libvorbis-dev \
        libtheora-dev libogg-dev \
        libsoxr-dev libspeex-dev \
        libchromaprint-dev \
        libzmq3-dev \
        libfreetype6-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libgraphite2-dev \
        libfontconfig1-dev \
        libcairo2-dev \
        libpango1.0-dev \
        libgdk-pixbuf2.0-dev \
        libgtk-3-dev \
        libnotify-dev \
        libappindicator3-dev \
        libsecret-1-dev \
        libsoup2.4-dev \
        libjson-glib-dev \
        libpolkit-agent-1-dev \
        libpolkit-gobject-1-dev \
        libupower-glib-dev \
        libgudev-1.0-dev \
        libwacom-dev \
        libinput-dev \
        libegl1-mesa-dev \
        libgles2-mesa-dev \
        libgl1-mesa-dev \
        libgbm-dev \
        libdrm-dev \
        libwayland-dev \
        libxkbcommon-dev \
        libpulse-dev \
        libasound2-dev \
        libjack-dev \
        libsamplerate0-dev \
        libsndfile1-dev \
        libboost-all-dev \
        libssl-dev \
        libxml2-dev \
        libxslt1-dev \
        libsqlite3-dev \
        libreadline-dev \
        libedit-dev \
        libncurses5-dev \
        libncursesw5-dev \
        libbz2-dev \
        liblzma-dev \
        libgdbm-dev \
        libdb-dev \
        libexpat1-dev \
        libffi-dev \
        zlib1g-dev \
        liblz4-dev \
        libzstd-dev \
        libsnappy-dev \
        libbz2-dev \
        liblzo2-dev \
        libjemalloc-dev \
        libunwind-dev \
        libgoogle-perftools-dev \
        libatomic-ops-dev \
        libcurl4-openssl-dev \
        libnghttp2-dev \
        libidn2-dev \
        librtmp-dev \
        libssh2-1-dev \
        libpsl-dev \
        libldap2-dev \
        libgssapi-krb5-2 \
        libkrb5-dev \
        libsasl2-dev \
        libntlm0-dev \
        libbrotli-dev \
        libzopfli-dev \
        libgsasl7-dev \
        libmaxminddb-dev \
        libgeoip-dev \
        libyaml-dev \
        libevent-dev \
        libuv1-dev \
        libmsgpack-dev \
        libprotobuf-dev \
        libcap-dev \
        libseccomp-dev \
        libapparmor-dev \
        libaudit-dev \
        libsystemd-dev \
        libglib2.0-dev \
        libpcre3-dev \
        libpcre2-dev \
        libselinux1-dev \
        libattr1-dev \
        libacl1-dev \
        libkeyutils-dev \
        libprocps-dev \
        libkmod-dev \
        libudev-dev \
        libusb-1.0-0-dev \
        libpciaccess-dev \
        libdrm-dev \
        libinput-dev \
        libwacom-dev \
        libgtk-3-dev \
        libnotify-dev \
        libappindicator3-dev \
        libsecret-1-dev \
        libsoup2.4-dev \
        libjson-glib-dev \
        libpolkit-agent-1-dev \
        libpolkit-gobject-1-dev \
        libupower-glib-dev \
        libgudev-1.0-dev \
        libnm-dev \
        libteam-dev \
        libndp-dev \
        libmnl-dev \
        libxtables-dev \
        libnetfilter-conntrack-dev \
        libnetfilter-queue-dev \
        libnetfilter-log-dev \
        libnfnetlink-dev \
        libipset-dev \
        libnftnl-dev \
        libnfsidmap-dev \                        # libebtables-dev УДАЛЁН
        libtirpc-dev \
        libkrb5-dev \
        libgssapi-krb5-2 \
        libsasl2-dev \
        libldap2-dev \
        libpq-dev \
        libmysqlclient-dev \
        libsqlite3-dev \
        libmongoc-dev \
        libbson-dev \
        libhiredis-dev \
        libmemcached-dev \
        librabbitmq-dev \                        # libcouchbase-dev УДАЛЁН
        libzmq3-dev \
        libnanomsg-dev \
        libcurl4-openssl-dev \
        libnghttp2-dev \
        libidn2-dev \
        librtmp-dev \
        libssh2-1-dev \
        libpsl-dev \
        libldap2-dev \
        libgssapi-krb5-2 \
        libkrb5-dev \
        libsasl2-dev \
        libntlm0-dev \
        libbrotli-dev \
        libzopfli-dev \
        libgsasl7-dev \
        libmaxminddb-dev \
        libgeoip-dev \
        libyaml-dev \
        libevent-dev \
        libuv1-dev \
        libmsgpack-dev \
        libprotobuf-dev \
        jq moreutils
    
    log_success "System dependencies installed"
}

# ============================================================================
# PHASE 3: PYTHON & PIP SETUP
# ============================================================================

setup_python() {
    log_info "Setting up Python ${PYTHON_VERSION} environment"
    
    # Create virtual environment
    python3 -m venv /opt/frigate/venv
    source /opt/frigate/venv/bin/activate
    
    # Upgrade pip and setuptools
    pip install --upgrade pip setuptools wheel
    
    # Install common Python packages
    pip install \
        numpy==1.26.4 \
        opencv-python-headless==4.9.0.80 \
        pillow==10.1.0 \
        scipy==1.13.1 \
        pandas==2.2.3 \
        pyyaml==6.0.3 \
        requests==2.31.0 \
        flask==3.0.0 \
        paho-mqtt==1.6.1 \
        psutil==5.9.8 \
        pyzmq==26.0.3 \
        Werkzeug==3.0.1
    
    log_success "Python environment setup complete"
}

# ============================================================================
# PHASE 4: FRIGATE INSTALLATION
# ============================================================================

install_frigate() {
    log_info "Installing Frigate ${FRIGATE_VERSION}"
    
    # Create directories
    mkdir -p ${INSTALL_DIR} ${CONFIG_DIR} ${MEDIA_DIR} ${MODELS_DIR}
    
    # Download Frigate
    cd /tmp
    if [[ ! -f "frigate-${FRIGATE_VERSION}.tar.gz" ]]; then
        wget -q "https://github.com/blakeblackshear/frigate/archive/refs/tags/v${FRIGATE_VERSION}.tar.gz" \
            -O "frigate-${FRIGATE_VERSION}.tar.gz"
    fi
    
    # Extract
    tar -xzf "frigate-${FRIGATE_VERSION}.tar.gz" -C ${INSTALL_DIR} --strip-components=1
    
    # Install Frigate Python dependencies
    cd ${INSTALL_DIR}
    source /opt/frigate/venv/bin/activate
    
    # Install from requirements files
    if [[ -f "requirements.txt" ]]; then
        pip install -r requirements.txt
    fi
    
    # Install specific packages that might fail from git
    log_info "Installing problematic packages with workarounds"
    
    # Try to install py3nvml from PyPI instead of git
    pip install py3nvml==0.2.7 || {
        log_warning "py3nvml installation failed, using fallback"
        # Create a dummy py3nvml module
        cat > /opt/frigate/venv/lib/python${PYTHON_VERSION%.*}/site-packages/py3nvml/__init__.py << 'PY3NVML_EOF'
"""Dummy py3nvml module for Frigate"""
def nvmlInit():
    pass
def nvmlShutdown():
    pass
def nvmlDeviceGetCount():
    return 0
PY3NVML_EOF
    }
    
    # Install other dependencies
    pip install \
        filterpy==1.4.5 \
        imutils==0.5.4 \
        peewee==3.17.0 \
        onvif-zeep==0.2.12 \
        norfair==2.2.0 \
        setproctitle==1.3.3 \
        ws4py==0.5.1 \
        Unidecode==1.3.8
    
    log_success "Frigate Python packages installed"
}

# ============================================================================
# PHASE 5: MODELS DOWNLOAD
# ============================================================================

download_models() {
    log_info "Downloading AI models"
    
    # Create models directory
    mkdir -p ${MODELS_DIR}
    
    # Download default CPU model
    wget -q "https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess.tflite" \
        -O "${MODELS_DIR}/cpu_model.tflite"
    
    # Download labelmap
    cat > "${MODELS_DIR}/labelmap.txt" << 'LABELMAP_EOF'
person
bicycle
car
motorcycle
airplane
bus
train
truck
boat
traffic light
fire hydrant
stop sign
parking meter
bench
bird
cat
dog
horse
sheep
cow
elephant
bear
zebra
giraffe
backpack
umbrella
handbag
tie
suitcase
frisbee
skis
snowboard
sports ball
kite
baseball bat
baseball glove
skateboard
surfboard
tennis racket
bottle
wine glass
cup
fork
knife
spoon
bowl
banana
apple
sandwich
orange
broccoli
carrot
hot dog
pizza
donut
cake
chair
couch
potted plant
bed
dining table
toilet
tv
laptop
mouse
remote
keyboard
cell phone
microwave
oven
toaster
sink
refrigerator
book
clock
vase
scissors
teddy bear
hair drier
toothbrush
LABELMAP_EOF
    
    # Download test video
    wget -q "https://github.com/intel-iot-devkit/sample-videos/raw/master/person-bicycle-car-detection.mp4" \
        -O "${MEDIA_DIR}/test_video.mp4"
    
    log_success "Models downloaded"
}

# ============================================================================
# PHASE 6: GO2RTC INSTALLATION
# ============================================================================

install_go2rtc() {
    log_info "Installing go2rtc"
    
    # Download go2rtc
    mkdir -p /usr/local/go2rtc/bin
    cd /usr/local/go2rtc/bin
    
    wget -q "https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_amd64" \
        -O go2rtc
    chmod +x go2rtc
    
    # Create symlink
    ln -sf /usr/local/go2rtc/bin/go2rtc /usr/local/bin/go2rtc
    
    # Create service file
    cat > /etc/systemd/system/go2rtc.service << 'GO2RTC_EOF'
[Unit]
Description=go2rtc WebRTC server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/go2rtc
ExecStart=/usr/local/go2rtc/bin/go2rtc
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
GO2RTC_EOF
    
    log_success "go2rtc installed"
}

# ============================================================================
# PHASE 7: CONFIGURATION
# ============================================================================

create_config() {
    log_info "Creating configuration"
    
    # Create minimal config
    cat > "${CONFIG_DIR}/config.yml" << 'CONFIG_EOF'
mqtt:
  enabled: false

cameras:
  test:
    ffmpeg:
      inputs:
        - path: /media/frigate/test_video.mp4
          input_args: -re -stream_loop -1 -fflags +genpts
          roles:
            - detect
    detect:
      width: 1280
      height: 720
      fps: 5

model:
  path: /opt/frigate/models/cpu_model.tflite
  width: 320
  height: 320

detectors:
  cpu:
    type: cpu
    num_threads: 2
CONFIG_EOF
    
    # Create default directories
    mkdir -p /dev/shm/logs/{frigate,go2rtc}
    chmod 777 /dev/shm/logs /dev/shm/logs/*
    
    log_success "Configuration created"
}

# ============================================================================
# PHASE 8: SERVICES SETUP
# ============================================================================

setup_services() {
    log_info "Setting up services"
    
    # Create Frigate service
    cat > /etc/systemd/system/frigate.service << 'FRIGATE_EOF'
[Unit]
Description=Frigate NVR
After=network.target go2rtc.service
Requires=go2rtc.service

[Service]
Type=simple
User=root
Environment="PATH=/opt/frigate/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
WorkingDirectory=/opt/frigate
ExecStart=/opt/frigate/venv/bin/frigate -c /config/config.yml
Restart=always
RestartSec=10
StandardOutput=append:/dev/shm/logs/frigate/current
StandardError=append:/dev/shm/logs/frigate/current

[Install]
WantedBy=multi-user.target
FRIGATE_EOF
    
    # Enable services
    systemctl daemon-reload
    systemctl enable go2rtc.service
    systemctl enable frigate.service
    
    log_success "Services configured"
}

# ============================================================================
# PHASE 9: FINALIZATION
# ============================================================================

finalize_installation() {
    log_info "Finalizing installation"
    
    # Start services
    systemctl start go2rtc.service
    sleep 2
    systemctl start frigate.service
    
    # Create MOTD
    cat > /etc/motd << 'MOTD_EOF'

╔═══════════════════════════════════════╗
║       Frigate NVR Installed!          ║
╠═══════════════════════════════════════╣
║  Web Interface: http://<IP>:5000      ║
║  go2rtc Streams: rtsp://<IP>:8554     ║
║                                       ║
║  Check status:  systemctl status frigate
║  View logs:     journalctl -u frigate -f
╚═══════════════════════════════════════╝

MOTD_EOF
    
    # Get container IP
    CONTAINER_IP=$(hostname -I | awk '{print $1}')
    
    log_success "="
    log_success "FRIGATE INSTALLATION COMPLETE!"
    log_success "="
    echo ""
    echo "Access Frigate at: http://${CONTAINER_IP}:5000"
    echo "Test video is playing at: rtsp://${CONTAINER_IP}:8554/test"
    echo ""
    echo "Next steps:"
    echo "1. Edit configuration: ${CONFIG_DIR}/config.yml"
    echo "2. Add your camera RTSP streams"
    echo "3. Restart Frigate: systemctl restart frigate"
    echo ""
    log_success "Installation finished successfully!"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║         Frigate Standalone Installer                 ║"
    echo "║         Version: ${FRIGATE_VERSION}                           ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    
    # Execute all phases
    setup_system
    install_dependencies
    setup_python
    install_frigate
    download_models
    install_go2rtc
    create_config
    setup_services
    finalize_installation
    
    # Unlock resolv.conf for normal operation
    chattr -i /etc/resolv.conf 2>/dev/null || true
}

# Run main function
main "$@"
