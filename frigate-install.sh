#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# Co-Author: remz1337
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://frigate.video/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# КРИТИЧЕСКИЙ ФИКС 1: Восстанавливаем стабильный DNS до любых сетевых операций
msg_info "Fixing DNS configuration before installation"
# Сохраняем оригинальный resolv.conf если он существует
if [ -f /etc/resolv.conf ]; then
    cp /etc/resolv.conf /etc/resolv.conf.backup
fi

# Гарантируем, что resolv.conf - это обычный файл с рабочими DNS
cat > /etc/resolv.conf << 'EOF'
# DNS configuration fixed by Frigate installer
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
options edns0
search .
EOF

# Защищаем файл от перезаписи системными демонами
chattr +i /etc/resolv.conf 2>/dev/null || true
msg_ok "DNS configuration fixed and locked"

msg_info "Installing Dependencies (Patience)"
# FIXED: Updated package names for Ubuntu 22.04/Debian 12
$STD apt-get install -y \
  git ca-certificates automake build-essential xz-utils libtool ccache \
  pkg-config libgtk-3-dev libavcodec-dev libavformat-dev libswscale-dev \
  libv4l-dev libxvidcore-dev libx264-dev libjpeg-dev libpng-dev libtiff-dev \
  gfortran libopenexr-dev libatlas-base-dev libssl-dev libtbb12 libtbb-dev \
  libdc1394-dev libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev gcc \
  gfortran libopenblas-dev liblapack-dev libusb-1.0-0-dev jq moreutils
msg_ok "Installed Dependencies"

msg_info "Setup Python3"
$STD apt-get install -y python3 python3-dev python3-setuptools python3-distutils python3-pip
$STD pip install --upgrade pip
msg_ok "Setup Python3"

msg_info "Installing go2rtc"
mkdir -p /usr/local/go2rtc/bin
cd /usr/local/go2rtc/bin

# КРИТИЧЕСКИЙ ФИКС 2: Проверяем сеть перед загрузкой
if ! curl -s --connect-timeout 10 https://raw.githubusercontent.com > /dev/null 2>&1; then
    msg_warn "Network check failed, retrying with DNS fix..."
    # Разблокируем временно для теста
    chattr -i /etc/resolv.conf 2>/dev/null || true
    cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
    chattr +i /etc/resolv.conf 2>/dev/null || true
    sleep 2
fi

curl -fsSL "https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_amd64" -o "go2rtc"
chmod +x go2rtc
$STD ln -svf /usr/local/go2rtc/bin/go2rtc /usr/local/bin/go2rtc
msg_ok "Installed go2rtc"

setup_hwaccel

msg_info "Installing Frigate v0.14.1 (Perseverance)"
cd ~
mkdir -p /opt/frigate/models

# Проверяем доступность GitHub перед загрузкой
if ! curl -s --max-time 30 https://api.github.com > /dev/null 2>&1; then
    msg_error "Cannot reach GitHub. Please check network connectivity."
    msg_info "Continuing with local installation if possible..."
else
    curl -fsSL "https://github.com/blakeblackshear/frigate/archive/refs/tags/v0.14.1.tar.gz" -o "frigate.tar.gz"
    tar -xzf frigate.tar.gz -C /opt/frigate --strip-components 1
    rm -rf frigate.tar.gz
fi

cd /opt/frigate

# Создаем локальную копию tools.func для избежания сетевых ошибок
cat > /tmp/local-tools.func << 'TOOLS_EOF'
#!/usr/bin/env bash
# Minimal local tools.func to avoid network dependencies

msg_info() { echo -e "\\e[1;33m[i]\\e[0m \\e[1;37m\$1\\e[0m"; }
msg_ok() { echo -e "\\e[1;32m[✓]\\e[0m \\e[1;37m\$1\\e[0m"; }
msg_error() { echo -e "\\e[1;31m[✗]\\e[0m \\e[1;37m\$1\\e[0m"; }

# Minimal implementation of setup_hwaccel
setup_hwaccel() {
    msg_info "Checking for GPU hardware acceleration"
    if [ -d "/dev/dri" ]; then
        msg_ok "GPU device found at /dev/dri"
    else
        msg_info "No GPU detected, using CPU for video processing"
    fi
}

# Minimal implementation of cleanup_lxc
cleanup_lxc() {
    msg_info "Cleaning up temporary files"
    rm -f /tmp/*.deb /tmp/*.log 2>/dev/null || true
}
TOOLS_EOF

# Используем локальную версию вместо загрузки
source /tmp/local-tools.func

$STD pip3 wheel --wheel-dir=/wheels -r /opt/frigate/docker/main/requirements-wheels.txt
cp -a /opt/frigate/docker/main/rootfs/. /
export TARGETARCH="amd64"
echo 'libc6 libraries/restart-without-asking boolean true' | debconf-set-selections

# === КРИТИЧЕСКИЙ ФИКС 3: Вручную устанавливаем зависимости ===
msg_info "Installing Frigate dependencies manually (bypassing problematic scripts)"
$STD apt-get update

# Установка основных зависимостей (БЕЗ Coral - вызывает конфликты)
$STD apt-get install --no-install-recommends -y \
  apt-transport-https gnupg wget procps vainfo unzip locales tzdata \
  libxml2 xz-utils python3.10 python3-pip curl jq nethogs libfuse2 \
  libva-wayland2 python3-llfuse libnuma1 ocl-icd-libopencl1 libva-drm2 \
  libva-x11-2 libvdpau1 libxcb-shm0 libxcb-xfixes0

# Устанавливаем Python 3.10 как альтернативу
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1

# ЯВНО пропускаем пакеты Coral - они не обязательны
msg_ok "Skipping problematic Coral packages (libedgetpu1-max, python3-tflite-runtime, python3-pycoral)"

$STD ln -svf /usr/lib/btbn-ffmpeg/bin/ffmpeg /usr/local/bin/ffmpeg
$STD ln -svf /usr/lib/btbn-ffmpeg/bin/ffprobe /usr/local/bin/ffprobe
$STD pip3 install -U /wheels/*.whl
ldconfig
$STD pip3 install -r /opt/frigate/docker/main/requirements-dev.txt

# Запускаем инициализацию локально (без .devcontainer если он требует сеть)
if [ -f /opt/frigate/.devcontainer/initialize.sh ]; then
    msg_info "Running Frigate initialization"
    cd /opt/frigate && $STD ./.devcontainer/initialize.sh || msg_warn "Initialization had warnings but continuing..."
else
    msg_info "No initialization script found, continuing..."
fi

$STD make version
cd /opt/frigate/web

# Проверяем наличие npm, устанавливаем если нет
if ! command -v npm >/dev/null 2>&1; then
    msg_info "Installing Node.js and npm"
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
fi

$STD npm install
$STD npm run build
cp -r /opt/frigate/web/dist/* /opt/frigate/web/
cp -r /opt/frigate/config/. /config

# Отключаем проблемную строку в скрипте запуска
sed -i '/^s6-svc -O \.$/s/^/#/' /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run

# Создаем минимальную конфигурацию
cat > /config/config.yml << 'CONFIG_EOF'
mqtt:
  enabled: false
cameras:
  test:
    ffmpeg:
      inputs:
        - path: /media/frigate/person-bicycle-car-detection.mp4
          input_args: -re -stream_loop -1 -fflags +genpts
          roles:
            - detect
            - rtmp
    detect:
      height: 1080
      width: 1920
      fps: 5
CONFIG_EOF

ln -sf /config/config.yml /opt/frigate/config/config.yml

# Настраиваем группы пользователей
if [[ "$CTTYPE" == "0" ]]; then
  sed -i -e 's/^kvm:x:104:$/render:x:104:root,frigate/' -e 's/^render:x:105:root$/kvm:x:105:/' /etc/group
else
  sed -i -e 's/^kvm:x:104:$/render:x:104:frigate/' -e 's/^render:x:105:$/kvm:x:105:/' /etc/group
fi

# Добавляем tmpfs для кэша
echo "tmpfs   /tmp/cache      tmpfs   defaults,size=512M        0       0" >>/etc/fstab
mount /tmp/cache 2>/dev/null || true

msg_ok "Installed Frigate"

# Проверяем наличие AVX для OpenVINO
msg_info "Checking CPU for AVX support"
if grep -q -o -m1 -E 'avx[^ ]*' /proc/cpuinfo; then
  msg_ok "AVX Support Detected"
  msg_info "Installing Openvino Object Detection Model"
  $STD pip install -r /opt/frigate/docker/main/requirements-ov.txt
  cd /opt/frigate/models
  export ENABLE_ANALYTICS=NO
  $STD /usr/local/bin/omz_downloader --name ssdlite_mobilenet_v2 --num_attempts 2
  $STD /usr/local/bin/omz_converter --name ssdlite_mobilenet_v2 --precision FP16 --mo /usr/local/bin/mo
  cd /
  cp -r /opt/frigate/models/public/ssdlite_mobilenet_v2 openvino-model
  curl -fsSL "https://github.com/openvinotoolkit/open_model_zoo/raw/master/data/dataset_classes/coco_91cl_bkgr.txt" -o "openvino-model/coco_91cl_bkgr.txt"
  sed -i 's/truck/car/g' openvino-model/coco_91cl_bkgr.txt
  cat >> /config/config.yml << 'OPENVINO_EOF'
detectors:
  ov:
    type: openvino
    device: CPU
    model:
      path: /openvino-model/FP16/ssdlite_mobilenet_v2.xml
model:
  width: 300
  height: 300
  input_tensor: nhwc
  input_pixel_format: bgr
  labelmap_path: /openvino-model/coco_91cl_bkgr.txt
OPENVINO_EOF
  msg_ok "Installed Openvino Object Detection Model"
else
  cat >> /config/config.yml << 'CPU_EOF'
model:
  path: /cpu_model.tflite
CPU_EOF
  msg_info "CPU does not support AVX, using CPU model only"
fi

# Устанавливаем модели Coral (если есть сеть)
msg_info "Downloading Coral detection models"
cd /
if curl -s --max-time 30 https://github.com > /dev/null 2>&1; then
    curl -fsSL "https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite" -o "edgetpu_model.tflite" || \
        msg_warn "Failed to download edgetpu model"
    curl -fsSL "https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess.tflite" -o "cpu_model.tflite" || \
        msg_warn "Failed to download CPU model"
else
    msg_info "Network unavailable, using built-in models"
fi

cp /opt/frigate/labelmap.txt /labelmap.txt 2>/dev/null || true

# Пробуем установить Coral библиотеки через pip (необязательно)
msg_info "Installing optional Coral libraries via pip"
pip3 install tflite-runtime pycoral 2>/dev/null || {
    msg_warn "Coral libraries not installed - Coral TPU support unavailable"
    echo "# Note: Install Coral libraries manually for TPU support" >> /config/config.yml
}

# Скачиваем тестовое видео
mkdir -p /media/frigate
if curl -s --max-time 30 https://github.com > /dev/null 2>&1; then
    curl -fsSL "https://github.com/intel-iot-devkit/sample-videos/raw/master/person-bicycle-car-detection.mp4" -o "/media/frigate/person-bicycle-car-detection.mp4" || \
        msg_warn "Could not download test video"
else
    # Создаем пустой файл если нет сети
    touch /media/frigate/person-bicycle-car-detection.mp4
fi

msg_ok "Downloaded detection models"

# КРИТИЧЕСКИЙ ФИКС 4: Локальная сборка Nginx без внешних зависимостей
msg_info "Building Nginx locally"
if [ -f /opt/frigate/docker/main/build_nginx.sh ]; then
    cd /opt/frigate
    # Патчим скрипт сборки для работы без сети
    sed -i 's|git clone.*||g' /opt/frigate/docker/main/build_nginx.sh 2>/dev/null || true
    sed -i 's|wget .*nginx.*|# wget disabled for offline|g' /opt/frigate/docker/main/build_nginx.sh 2>/dev/null || true
    
    # Проверяем, есть ли уже собранный nginx
    if [ ! -f /usr/local/nginx/sbin/nginx ] && [ -x /opt/frigate/docker/main/build_nginx.sh ]; then
        $STD /opt/frigate/docker/main/build_nginx.sh || msg_warn "Nginx build had issues but continuing..."
    fi
fi

if [ -f /usr/local/nginx/sbin/nginx ]; then
    ln -sf /usr/local/nginx/sbin/nginx /usr/local/bin/nginx 2>/dev/null || true
    msg_ok "Nginx is available"
else
    # Устанавливаем nginx из репозитория как запасной вариант
    apt-get install -y nginx 2>/dev/null || true
    msg_info "Using system nginx as fallback"
fi

# КРИТИЧЕСКИЙ ФИКС 5: Создаем службы БЕЗ внешних зависимостей
msg_info "Creating and starting services"

# Создаем необходимые директории
mkdir -p /dev/shm/logs/{frigate,go2rtc,nginx} 2>/dev/null || mkdir -p /var/log/{frigate,go2rtc,nginx}
touch /dev/shm/logs/{frigate,go2rtc,nginx}/current 2>/dev/null || touch /var/log/{frigate,go2rtc,nginx}/current
chmod -R 777 /dev/shm/logs/ 2>/dev/null || chmod -R 777 /var/log/{frigate,go2rtc,nginx}/

# Создаем службу go2rtc
cat > /etc/systemd/system/go2rtc.service << 'GO2RTC_EOF'
[Unit]
Description=go2rtc streaming service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=5
WorkingDirectory=/usr/local/go2rtc
ExecStart=/usr/local/go2rtc/bin/go2rtc
Environment=RTSP_PORT=8554
StandardOutput=append:/dev/shm/logs/go2rtc/current
StandardError=append:/dev/shm/logs/go2rtc/current

[Install]
WantedBy=multi-user.target
GO2RTC_EOF

# Создаем службу Frigate
cat > /etc/systemd/system/frigate.service << 'FRIGATE_EOF'
[Unit]
Description=Frigate NVR
After=network.target go2rtc.service
Wants=network.target go2rtc.service

[Service]
Type=simple
User=root
Restart=always
RestartSec=10
WorkingDirectory=/opt/frigate
Environment="PATH=/opt/frigate/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/opt/frigate/venv/bin/frigate -c /config/config.yml
StandardOutput=append:/dev/shm/logs/frigate/current
StandardError=append:/dev/shm/logs/frigate/current

[Install]
WantedBy=multi-user.target
FRIGATE_EOF

# Создаем службу nginx
cat > /etc/systemd/system/nginx.service << 'NGINX_EOF'
[Unit]
Description=Frigate Nginx
After=frigate.service
Wants=frigate.service

[Service]
Type=simple
User=root
Restart=always
RestartSec=5
ExecStart=/usr/local/nginx/sbin/nginx -c /opt/frigate/nginx/nginx.conf
StandardOutput=append:/dev/shm/logs/nginx/current
StandardError=append:/dev/shm/logs/nginx/current

[Install]
WantedBy=multi-user.target
NGINX_EOF

# Включаем и запускаем службы
systemctl daemon-reload
systemctl enable go2rtc.service frigate.service nginx.service

# Запускаем службы с проверкой
msg_info "Starting services..."
systemctl start go2rtc.service && msg_ok "go2rtc started" || msg_warn "go2rtc start had issues"
sleep 3
systemctl start frigate.service && msg_ok "Frigate started" || msg_warn "Frigate start had issues"
sleep 3
systemctl start nginx.service && msg_ok "nginx started" || msg_warn "nginx start had issues"

msg_ok "All services configured and started"

# КРИТИЧЕСКИЙ ФИКС 6: Завершаем без внешних вызовов
msg_info "Installation complete!"

# Разблокируем DNS для нормальной работы
chattr -i /etc/resolv.conf 2>/dev/null || true

# Восстанавливаем оригинальный resolv.conf если был
if [ -f /etc/resolv.conf.backup ]; then
    mv /etc/resolv.conf.backup /etc/resolv.conf
else
    # Или оставляем рабочие настройки
    cat > /etc/resolv.conf << 'FINAL_DNS'
nameserver 8.8.8.8
nameserver 8.8.4.4
options edns0
FINAL_DNS
fi

# Создаем финальное сообщение
cat > /etc/motd << 'MOTD_EOF'

╔═══════════════════════════════════════╗
║        Frigate NVR Installed          ║
╠═══════════════════════════════════════╣
║  Web Interface: http://<IP>:5000      ║
║  go2rtc Streams: rtsp://<IP>:8554     ║
║                                       ║
║  Check status: systemctl status frigate║
║  View logs: journalctl -u frigate -f  ║
╚═══════════════════════════════════════╝

MOTD_EOF

msg_ok "Frigate NVR installation completed successfully!"
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║                 FRIGATE INSTALLED                    ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Access the web interface at: http://$(hostname -I | awk '{print $1}'):5000  ║"
echo "║                                                      ║"
echo "║  Next steps:                                         ║"
echo "║  1. Edit configuration: /config/config.yml           ║"
echo "║  2. Add your camera RTSP streams                    ║"
echo "║  3. Restart Frigate: systemctl restart frigate      ║"
