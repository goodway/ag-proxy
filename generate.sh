#!/bin/bash

echo -e "\033[36m###########################"
echo -e "\033[36m#                         #"
echo -e "\033[36m#     █████╗  ██████╗     #"
echo -e "\033[36m#    ██╔══██╗██╔════╝     #"
echo -e "\033[36m#    ███████║██║  ███╗    #"
echo -e "\033[36m#    ██╔══██║██║   ██║    #"
echo -e "\033[36m#    ██║  ██║╚██████╔╝    #"
echo -e "\033[36m#    ╚═╝  ╚═╝ ╚═════╝     #"
echo -e "\033[36m#                         #"
echo -e "\033[36m###########################"
echo -e "\033[36m"
echo -e "\033[36m  🌐 AG Nginx Proxy Generator"
echo -e "\033[36m  Генератор прокси-конфигураций для Nginx"
echo -e "\033[36m  Версия 1.0"
echo
read -p $'\033[36m  Нажмите Enter, чтобы начать настройку... \033[0m'


# Функция для добавления ограничений в /etc/security/limits.conf
setup_limits() {
    local CONFIG_FILE="/etc/security/limits.conf"
    
    # Проверяем существование файла
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Ошибка: Файл $CONFIG_FILE не найден"
        return 1
    fi

    # Проверяем права доступа (нужны root)
    if [[ $EUID -ne 0 ]]; then
        echo "Ошибка: Скрипт должен быть запущен с правами root"
        return 1
    fi

    # Проверяем, существуют ли уже нужные строки
    local CHECK_NPROC_SOFT=$(grep -E "^soft\s+nproc\s+65536" "$CONFIG_FILE" | wc -l)
    local CHECK_NPROC_HARD=$(grep -E "^hard\s+nproc\s+65536" "$CONFIG_FILE" | wc -l)
    local CHECK_NOFILE_SOFT=$(grep -E "^soft\s+nofile\s+65536" "$CONFIG_FILE" | wc -l)
    local CHECK_NOFILE_HARD=$(grep -E "^hard\s+nofile\s+65536" "$CONFIG_FILE" | wc -l)

    # Если строки уже существуют, выводим сообщение
    if [[ $CHECK_NPROC_SOFT -gt 0 && $CHECK_NPROC_HARD -gt 0 && $CHECK_NOFILE_SOFT -gt 0 && $CHECK_NOFILE_HARD -gt 0 ]]; then
        echo "Ограничения уже заданы в файле $CONFIG_FILE"
        return 0
    fi

    # Если не все строки существуют, добавляем их
    echo "Добавление ограничений в файл $CONFIG_FILE..."

    # Добавляем строки с проверкой на дублирование
    if ! grep -q "^* soft nofile 65536" "$CONFIG_FILE"; then
        echo "* soft nofile 65536" >> "$CONFIG_FILE"
    fi

    if ! grep -q "^* hard nofile 65536" "$CONFIG_FILE"; then
        echo "* hard nofile 65536" >> "$CONFIG_FILE"
    fi

    if ! grep -q "^* soft nproc 65536" "$CONFIG_FILE"; then
        echo "* soft nproc 65536" >> "$CONFIG_FILE"
    fi

    if ! grep -q "^* hard nproc 65536" "$CONFIG_FILE"; then
        echo "* hard nproc 65536" >> "$CONFIG_FILE"
    fi

    echo "Ограничения успешно добавлены в файл $CONFIG_FILE"
    echo "Для применения изменений необходимо перезагрузить систему или войти в систему заново"
    return 0
}

replace_nginx_config() {
    echo "Создание резервной копии текущего конфига..."
    cp "$NGINX_CONF" "${NGINX_CONF}.backup"
    
    # Проверяем, успешно ли создалась резервная копия
    if [[ $? -ne 0 ]]; then
        echo "Ошибка при создании резервной копии!"
        return 1
    fi
    
    echo "Резервная копия создана: ${NGINX_CONF}.backup"
    
    # Создаем новый конфиг с содержимым из вашего текста
    cat > "$NGINX_CONF" << 'EOF'
user www-data;
worker_processes auto;
worker_rlimit_nofile 64000;

pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections  8192;
    accept_mutex on;
    multi_accept on;
    use epoll;
}

http {

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout  30;
    keepalive_requests 256;
    types_hash_max_size 2048;
    client_body_timeout 10;
    send_timeout 5;

    server_names_hash_bucket_size 128;

    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    gzip on;
    gzip_disable "msie6";

    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 2;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
        gzip_types 
        text/plain
        text/css
        application/json
        application/javascript
        text/xml
        application/xml
        application/xml+rss
        text/javascript
        font/eot
        font/otf
        font/ttf
        image/svg+xml;
    gzip_min_length 500;


    ##
    # SSL Settings
    ##

    ssl_session_cache   shared:SSL:10m; # ssl_session cache 10mb ~ 40000 sessions
    ssl_session_timeout 30m; # ssl_session timeout

    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3; # Dropping SSLv3, ref: POODLE
    ssl_prefer_server_ciphers on;


    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
    
    # Проверяем, успешно ли записан новый конфиг
    if [[ $? -eq 0 ]]; then
        echo "Новый конфиг успешно записан в $NGINX_CONF"
        return 0
    else
        echo "Ошибка при записи нового конфига!"
        return 1
    fi
}

NGINX_CONF="/etc/nginx/nginx.conf"

# Обновление пакетов и установка необходимых утилит
apt update
apt install -y sudo
#sudo apt upgrade -y

# Установка дополнительных пакетов
sudo apt install -y curl gnupg2 ca-certificates lsb-release

read -p $'\033[36m Установить и активировать firewall (ufw) с нужными портами? (y/n): \033[0m' -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
   # Установка ufw и настройка правил для SSH, HTTP и HTTPS
   sudo apt install ufw -y
   sudo ufw allow 'OpenSSH'
   sudo ufw allow 'Nginx Full'
   sudo ufw enable
   echo -e "\033[36m Firewall активирован, порты настроены \033[0m"
fi

read -p $'\033[36m Установить Nginx веб-сервер? (y/n): \033[0m' -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
   # Установка nginx
   sudo apt install nginx -y

   # Включение nginx
   sudo systemctl enable nginx
   sudo systemctl start nginx
   echo -e "\033[36m Nginx установлен и активирован \033[0m"
fi


read -p $'\033[36m Заменить ваш текущий nginx.conf на оптимизированную под прокси версию? (y/n): \033[0m' -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
   replace_nginx_config
fi


SETUP_LIMITS=0

read -p $'\033[36m  Убрать soft и hard лимиты по ресурсам ? (для средне и высокопосещаемых проектов) (y/n): ' -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
   setup_limits
   SETUP_LIMITS=1
fi

if [ "$SETUP_LIMITS" == 1 ]; then
    read -p $'\033[36m  Перезапустить систему (y/n): ' -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reboot
    fi
fi

# Установка certbot и python3-certbot-nginx
sudo apt install certbot python3-certbot-nginx -y

filename="api_balancer"
upstream_name="api_olimp"
server_name="api.test.com"
server="prod.domain:443"
type="web"

# Запрос у пользователя информации для конфигурационного файла
read -p $'\033[36m Введите название конфигурационного файла (без расширения): \033[0m' filename
read -p $'\033[36m Введите название upstream: \033[0m' upstream_name
read -p $'\033[36m Введите текущий прокси-домен: \033[0m' server_name
read -p $'\033[36m Введите домен/IP и порт конечного сервера для upstream (например, final.host:443): \033[0m' server
read -p $'\033[36m Введите тип конфигурации (web или octane): \033[0m' type

# Определение значения по умолчанию для блока map $http_upgrade $type
if [ "$type" == "web" ]; then
    default_value="web"
elif [ "$type" == "octane" ]; then
    default_value="octane"
else
    echo -e "\033[31m Неверный тип. Выберите 'web' или 'octane'. \033[0m"
    exit 1
fi

# Определение названий файлов логов с учетом названия upstream
access_log="var/log/nginx/${upstream_name}.access.log"
error_log="var/log/nginx/${upstream_name}.error.log"
octane_proxy="${upstream_name}\$suffix"


# Создание конфигурационного файла nginx
cat <<EOF > "$filename.conf"
map \$http_upgrade \$type {
  default "$default_value";
  websocket "ws";
}

map \$http_upgrade2 \$connection_upgrade {
    default upgrade;
    ''      close;
}

upstream $upstream_name {
    least_conn;
    zone $upstream_name 64k;

    server $server; # max_fails=1 fail_timeout=3s; // we will use this attr-s for multiple servers configuration

    keepalive 5;
}

server {
    server_name $server_name;

    access_log off;
    #access_log  /$access_log main;
    error_log  /$error_log error;

    location / {
        try_files /nonexistent @\$type;
    }

    # @ws для WebSocket
    location @ws {
        proxy_pass https://$upstream_name;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout     60;
        proxy_connect_timeout  60;
        proxy_redirect         off;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_cache_bypass \$http_upgrade;
    }

EOF

if [ "$type" == "web" ]; then
cat <<EOF >> "$filename.conf"
    location @web {
        proxy_pass https://$upstream_name;
        proxy_set_header HOST \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_redirect off;

        proxy_next_upstream error timeout http_500;
    }
EOF
else
cat <<EOF >> "$filename.conf"
    location @octane {
        set \$suffix "";
 
        if (\$uri = /index.php) {
            set \$suffix ?\$query_string;
        }
 
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header Scheme \$scheme;
        proxy_set_header SERVER_PORT \$server_port;
        proxy_set_header REMOTE_ADDR \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade2;
        proxy_set_header Connection \$connection_upgrade;

        proxy_pass https://${octane_proxy};
    }
EOF
fi

cat <<'EOF' >> "$filename.conf"

    client_max_body_size 10M;

}
EOF

read -p $'\033[36m ✅  Конфигурационный файл '$filename.conf' был успешно создан. Применить его? (y/n): ' -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then

   # Копирование конфигурационного файла в папку /etc/nginx/conf.d/
   sudo cp "$filename.conf" "/etc/nginx/conf.d/"

   # Проверка конфигурации nginx
   if ! sudo nginx -t; then
      echo -e "\033[31m Ошибка в конфигурации. Исправьте ошибки и попробуйте снова. \033[0m"
      exit 1
   fi

   echo -e "\033[36m Конфигурационный файл скопирован в /etc/nginx/cond.f/  \033[0m"

   echo -e "\033[36m Перезагрузка nginx для применения изменений ... \033[0m"
   sudo systemctl reload nginx

   echo -e "\033[36m ✅  Конфигурация домена успешно применена. \033[0m"

   read -p $'\033[36m  Выпустить LetsEncrypt сертификат для прокси-домена? (y/n): ' -n 1 -r
   echo

   if [[ $REPLY =~ ^[Yy]$ ]]; then
      if sudo certbot --nginx -d $server_name; then
         echo -e "\033[36m ✅  Сертификат успешно установлен  \033[0m"
         exit 0
      else
         echo -e "\033[31m Ошибка установки сертификата  \033[0m"
        exit 1
      fi
   fi
fi