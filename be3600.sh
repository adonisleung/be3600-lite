#!/bin/sh

# ===================== 配置常量 =====================
readonly HTTP_HOST="https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main"
readonly THIRD_PARTY_SOURCE="https://istore.linkease.com/repo/all/nas_luci"
readonly OPENCLASH_URL="https://github.com/vernesong/OpenClash/releases/latest/download/luci-app-openclash.ipk"

# ===================== 颜色输出函数 =====================
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[31;1m'
readonly COLOR_GREEN='\033[32;1m'
readonly COLOR_YELLOW='\033[33;1m'
readonly COLOR_BLUE='\033[34;1m'
readonly COLOR_MAGENTA='\033[35;1m'
readonly COLOR_CYAN='\033[36;1m'

log_info() { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"; }
log_success() { echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $1"; }
log_warning() { echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $1"; }
log_error() { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1" >&2; }
log_debug() { [ -n "${DEBUG}" ] && echo -e "${COLOR_CYAN}[DEBUG]${COLOR_RESET} $1"; }

# ===================== 工具函数 =====================
is_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_internet_connection() {
    log_info "检查网络连接..."
    if ! curl -s --connect-timeout 5 https://repo.istoreos.com >/dev/null; then
        log_error "网络连接失败，请检查网络"
        return 1
    fi
    log_success "网络连接正常"
    return 0
}

require_root() {
    [ "$(id -u)" -eq 0 ] || {
        log_error "请使用root权限运行此脚本"
        exit 1
    }
}

cleanup_temp_dirs() {
    for dir in /tmp/ipk_store /tmp/ipk_downloads /tmp/luci-app-filetransfer /tmp/qstart /tmp/luci-app-uninstall /tmp/openclash /tmp/theme_deps; do
        [ -d "$dir" ] && rm -rf "$dir"
    done
}

# ===================== 系统信息函数 =====================
get_router_model() {
    cat /tmp/sysinfo/model 2>/dev/null || echo "Unknown Model"
}

get_router_hostname() {
    uci get system.@system[0].hostname 2>/dev/null || echo "OpenWrt"
}

is_iStoreOS() {
    [ -f /etc/openwrt_release ] || return 1
    local distrib_id
    distrib_id=$(grep "DISTRIB_ID" /etc/openwrt_release | cut -d "'" -f 2)
    [ "$distrib_id" = "iStoreOS" ]
}

# ===================== 软件源管理 =====================
manage_software_sources() {
    local mode="$1"
    local opkg_conf="/etc/opkg.conf"
    local custom_feeds="/etc/opkg/customfeeds.conf"
    
    case "$mode" in
        "restore")
            echo "# Custom package feeds" > "$custom_feeds"
            is_iStoreOS && echo "option check_signature 1" >> "$opkg_conf"
            opkg update
            log_success "已恢复原始软件源"
            ;;
        "thirdparty")
            sed -i '/option check_signature/d' "$opkg_conf"
            echo "# Custom package feeds" > "$custom_feeds"
            echo "src/gz third_party_source $THIRD_PARTY_SOURCE" >> "$custom_feeds"
            opkg update
            log_success "已设置第三方软件源"
            ;;
        *)
            log_error "无效的模式: $mode"
            return 1
            ;;
    esac
}

# ===================== 基础配置 =====================
configure_system_basics() {
    log_info "开始基础配置..."
    
    # 设置时区
    uci set system.@system[0].zonename='Asia/Shanghai'
    uci set system.@system[0].timezone='CST-8'
    uci commit system 2>/dev/null
    /etc/init.d/system reload 2>/dev/null
    
    # 添加安卓时间服务器
    if ! uci show dhcp 2>/dev/null | grep -q "time.android.com"; then
        uci add dhcp domain 2>/dev/null
        uci set "dhcp.@domain[-1].name=time.android.com" 2>/dev/null
        uci set "dhcp.@domain[-1].ip=203.107.6.88" 2>/dev/null
        uci commit dhcp 2>/dev/null
    fi
    
    log_success "基础配置完成"
}

# ===================== 安装函数 =====================
install_package_safe() {
    local package="$1"
    local retries=3
    local count=0
    
    while [ $count -lt $retries ]; do
        if opkg install "$package" 2>/dev/null; then
            return 0
        fi
        count=$((count + 1))
        log_warning "安装 $package 失败，重试 $count/$retries"
        sleep 2
    done
    
    log_error "无法安装 $package"
    return 1
}

install_argon_theme() {
    log_info "正在安装 Argon 紫色主题..."
    
    # 创建临时目录
    local temp_dir="/tmp/theme_deps"
    mkdir -p "$temp_dir"
    cd "$temp_dir" || return 1
    
    # 安装依赖
    local dependencies=(
        "luci-lua-runtime_all.ipk"
        "libopenssl3.ipk"
    )
    
    for dep in "${dependencies[@]}"; do
        log_info "安装依赖: $dep"
        if ! wget --user-agent="Mozilla/5.0" -O "$dep" "$HTTP_HOST/theme/$dep" 2>/dev/null; then
            log_error "下载依赖 $dep 失败"
            return 1
        fi
        opkg install "$dep" 2>/dev/null || log_warning "依赖 $dep 安装失败"
    done
    
    # 下载并安装主题
    local theme_packages=(
        "luci-theme-argon-master_2.2.9.4_all.ipk"
        "luci-app-argon-config_0.9_all.ipk"
        "luci-i18n-argon-config-zh-cn.ipk"
    )
    
    for pkg in "${theme_packages[@]}"; do
        log_info "下载主题包: $pkg"
        if ! wget --user-agent="Mozilla/5.0" -O "$pkg" "$HTTP_HOST/theme/$pkg" 2>/dev/null; then
            log_error "下载 $pkg 失败"
            continue
        fi
        
        if ! opkg install "$pkg" 2>/dev/null; then
            log_warning "$pkg 安装失败"
        fi
    done
    
    # 应用主题配置
    uci set luci.main.mediaurlbase='/luci-static/argon' 2>/dev/null
    uci set luci.main.lang='zh_cn' 2>/dev/null
    uci commit luci 2>/dev/null
    
    # 修复登录按钮文本
    sed -i 's/value="<%:Login%>"/value="登录"/' \
        /usr/lib/lua/luci/view/themes/argon/sysauth.htm 2>/dev/null
    
    log_success "Argon 主题安装完成"
    cd /tmp
}

install_iStore() {
    log_info "正在安装 iStore 商店..."
    
    if ! opkg update 2>/dev/null; then
        log_error "软件源更新失败"
        return 1
    fi
    
    local store_url="https://repo.istoreos.com/repo/all/store/"
    local temp_dir="/tmp/istore_ipk"
    
    mkdir -p "$temp_dir"
    cd "$temp_dir" || return 1
    
    # 下载所有IPK包
    log_info "下载 iStore 组件..."
    if ! wget -qO- "$store_url" 2>/dev/null | grep -oE 'href="[^"]+\.ipk"' | cut -d'"' -f2 | \
        while read -r ipk; do
            log_debug "下载: $ipk"
            wget -q "${store_url}${ipk}" 2>/dev/null
        done; then
        log_error "下载IPK文件失败"
        return 1
    fi
    
    # 批量安装
    log_info "安装 iStore 组件..."
    if ! opkg install ./*.ipk 2>/dev/null; then
        log_warning "部分包安装失败，尝试单独安装..."
        for ipk in ./*.ipk; do
            opkg install "$ipk" 2>/dev/null || true
        done
    fi
    
    log_success "iStore 安装完成"
    cd /tmp
}

# ===================== 高级功能 =====================
configure_fan_temperature() {
    echo "=== 风扇温度设置 ==="
    echo "适用于带风扇的 GL-iNet 路由器"
    
    while true; do
        read -rp "请输入风扇启动温度(40-70℃): " temp
        
        if ! [[ "$temp" =~ ^[0-9]+$ ]]; then
            log_error "请输入有效的数字"
            continue
        fi
        
        if [ "$temp" -lt 40 ] || [ "$temp" -gt 70 ]; then
            log_warning "建议温度范围: 40-70℃"
            read -rp "是否继续? (y/N): " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || continue
        fi
        
        uci set glfan.@globals[0].temperature="$temp" 2>/dev/null
        uci set glfan.@globals[0].warn_temperature="$temp" 2>/dev/null
        uci set glfan.@globals[0].integration=4 2>/dev/null
        uci set glfan.@globals[0].differential=20 2>/dev/null
        uci commit glfan 2>/dev/null
        
        if /etc/init.d/gl_fan restart 2>/dev/null; then
            log_success "风扇温度设置为 ${temp}℃"
        else
            log_error "风扇服务重启失败"
        fi
        
        break
    done
}

toggle_adguard_home() {
    if ! uci get adguardhome.config.enabled >/dev/null 2>&1; then
        log_error "AdGuardHome 未安装"
        read -rp "是否现在安装? (y/N): " install_choice
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            log_info "开始安装 AdGuardHome..."
            opkg install luci-app-adguardhome 2>/dev/null || {
                log_error "AdGuardHome 安装失败"
                return 1
            }
        else
            return 1
        fi
    fi
    
    local current_status
    current_status=$(uci get adguardhome.config.enabled 2>/dev/null)
    
    if [ "$current_status" -eq 1 ]; then
        uci set adguardhome.config.enabled='0' 2>/dev/null
        /etc/init.d/adguardhome stop 2>/dev/null
        /etc/init.d/adguardhome disable 2>/dev/null
        log_success "AdGuardHome 已关闭"
    else
        uci set adguardhome.config.enabled='1' 2>/dev/null
        /etc/init.d/adguardhome enable 2>/dev/null
        /etc/init.d/adguardhome start 2>/dev/null
        log_success "AdGuardHome 已开启 - 访问: http://192.168.8.1:3000"
    fi
    
    uci commit adguardhome 2>/dev/null
}

# ===================== OpenClash 安装 =====================
install_openclash() {
    log_info "开始安装 OpenClash..."
    
    local temp_dir="/tmp/openclash"
    mkdir -p "$temp_dir"
    cd "$temp_dir" || return 1
    
    log_info "下载 OpenClash..."
    if ! wget -O luci-app-openclash.ipk "$OPENCLASH_URL" 2>/dev/null; then
        log_error "下载 OpenClash 失败，请检查网络连接"
        return 1
    fi
    
    log_info "安装 OpenClash (可能需要几分钟)..."
    if opkg install luci-app-openclash.ipk --force-depends 2>/dev/null; then
        log_success "OpenClash 安装完成"
        echo "请访问: http://192.168.8.1/cgi-bin/luci/admin/services/openclash"
    else
        log_error "OpenClash 安装失败"
        return 1
    fi
    
    cd /tmp
    return 0
}

# ===================== Docker 安装 =====================
install_docker() {
    log_info "开始安装 Docker 和 DockerMan..."
    
    # 更新软件源
    if ! opkg update 2>/dev/null; then
        log_error "软件源更新失败"
        return 1
    fi
    
    # 安装 Docker 组件
    local docker_packages=(
        "dockerd"
        "docker-compose"
        "luci-app-dockerman"
        "luci-i18n-dockerman-zh-cn"
    )
    
    log_info "安装 Docker 组件..."
    for pkg in "${docker_packages[@]}"; do
        log_info "正在安装: $pkg"
        if ! opkg install "$pkg" 2>/dev/null; then
            log_warning "$pkg 安装失败，尝试从第三方源安装..."
            # 尝试从第三方源安装
            opkg install "$pkg" --force-depends 2>/dev/null || {
                log_error "$pkg 安装失败"
                return 1
            }
        fi
    done
    
    # 启动并启用 Docker 服务
    log_info "启动 Docker 服务..."
    if /etc/init.d/dockerd start 2>/dev/null; then
        /etc/init.d/dockerd enable 2>/dev/null
        log_success "Docker 服务已启动并设为开机自启"
    else
        log_error "Docker 服务启动失败"
        return 1
    fi
    
    # 检查 Docker 是否正常运行
    sleep 2
    if docker version >/dev/null 2>&1; then
        log_success "Docker 安装完成并运行正常"
        echo "Docker 版本: $(docker --version 2>/dev/null | head -n1)"
        echo "Docker Compose 版本: $(docker-compose --version 2>/dev/null)"
        echo "Web 管理界面: http://192.168.8.1/cgi-bin/luci/admin/docker"
    else
        log_warning "Docker 已安装但可能未完全启动，请检查日志"
    fi
    
    return 0
}

# ===================== 安装流程 =====================
install_iStoreOS_style() {
    log_info "开始安装 iStoreOS 风格..."
    
    # 1. 安装主题
    install_argon_theme
    
    # 2. 安装必要工具
    local essential_packages=(
        "luci-i18n-ttyd-zh-cn"
        "openssh-sftp-server"
    )
    
    for pkg in "${essential_packages[@]}"; do
        log_info "安装: $pkg"
        opkg install "$pkg" 2>/dev/null || log_warning "$pkg 安装失败"
    done
    
    # 3. 安装文件传输插件
    install_filetransfer
    
    # 4. 安装iStore
    install_iStore
    
    # 5. 修改系统标识
    local release_file="/etc/openwrt_release"
    if [ -f "$release_file" ]; then
        sed -i "s/DISTRIB_DESCRIPTION='.*'/DISTRIB_DESCRIPTION='OpenWrt with iStoreOS Style'/" \
            "$release_file"
    fi
    
    log_success "iStoreOS 风格安装完成"
}

# ===================== 文件传输插件 =====================
install_filetransfer() {
    log_info "安装文件传输插件..."
    
    local temp_dir="/tmp/luci-app-filetransfer"
    mkdir -p "$temp_dir"
    cd "$temp_dir" || return 1
    
    # 下载插件
    wget --user-agent="Mozilla/5.0" -O luci-app-filetransfer_all.ipk \
        "$HTTP_HOST/luci-app-filetransfer/luci-app-filetransfer_all.ipk" 2>/dev/null
    
    wget --user-agent="Mozilla/5.0" -O luci-lib-fs_1.0-14_all.ipk \
        "$HTTP_HOST/luci-app-filetransfer/luci-lib-fs_1.0-14_all.ipk" 2>/dev/null
    
    # 安装插件
    opkg install *.ipk --force-depends 2>/dev/null || {
        log_warning "文件传输插件安装失败"
        return 1
    }
    
    log_success "文件传输插件安装完成"
    cd /tmp
}

# ===================== UI辅助插件 =====================
install_ui_helper() {
    log_info "开始安装 UI 辅助插件..."
    
    echo "请确保当前固件版本大于 4.7.2，若低于此版本建议先升级。"
    read -rp "按回车键继续，或按 Ctrl+C 退出: " _
    
    local ipk_file="/tmp/glinjector_3.0.5-6_all.ipk"
    local sha_file="${ipk_file}.sha256"
    
    log_info "下载插件文件..."
    wget -O "$sha_file" "$HTTP_HOST/ui/glinjector_3.0.5-6_all.ipk.sha256" 2>/dev/null || {
        log_error "下载 SHA256 文件失败"
        return 1
    }
    
    wget --user-agent="Mozilla/5.0" -O "$ipk_file" \
        "$HTTP_HOST/ui/glinjector_3.0.5-6_all.ipk" 2>/dev/null || {
        log_error "下载插件文件失败"
        return 1
    }
    
    log_info "验证文件完整性..."
    cd "$(dirname "$ipk_file")"
    if ! sha256sum -c "$sha_file" 2>/dev/null; then
        log_error "文件校验失败，可能已损坏"
        rm -f "$ipk_file"
        return 1
    fi
    
    log_info "开始安装..."
    opkg update 2>/dev/null
    opkg install "$ipk_file" 2>/dev/null || {
        log_error "插件安装失败"
        return 1
    }
    
    log_success "UI 辅助插件安装完成"
}

# ===================== 高级卸载插件 =====================
install_advanced_uninstaller() {
    log_info "安装高级卸载插件..."
    
    wget -O /tmp/advanced_uninstall.run \
        "$HTTP_HOST/luci-app-uninstall.run" 2>/dev/null || {
        log_error "下载卸载插件失败"
        return 1
    }
    
    chmod +x /tmp/advanced_uninstall.run
    sh /tmp/advanced_uninstall.run || {
        log_error "安装卸载插件失败"
        return 1
    }
    
    log_success "高级卸载插件安装完成"
}

# ===================== 恢复出厂设置 =====================
perform_factory_reset() {
    echo "⚠️ 警告：此操作将恢复出厂设置，所有配置将被清除！"
    echo "⚠️ 请确保已备份必要数据。"
    
    read -rp "是否确定执行恢复出厂设置？(输入 yes 确认): " confirm
    
    if [ "$confirm" = "yes" ]; then
        log_info "正在执行恢复出厂设置..."
        firstboot -y >/dev/null 2>&1
        log_info "操作完成，正在重启设备..."
        reboot
    else
        log_info "操作已取消"
    fi
}

# ===================== 系统状态检查 =====================
show_system_status() {
    echo "=== 系统状态 ==="
    echo "设备型号: $(get_router_model)"
    echo "主机名: $(get_router_hostname)"
    
    if command -v top >/dev/null 2>&1; then
        echo "CPU使用率: $(top -n 1 2>/dev/null | grep 'CPU:' | awk '{print $2}' || echo 'N/A')"
    fi
    
    if command -v free >/dev/null 2>&1; then
        echo "内存使用: $(free -m 2>/dev/null | grep Mem | awk '{print $3"/"$2"MB"}' || echo 'N/A')"
    fi
    
    if command -v df >/dev/null 2>&1; then
        echo "存储空间: $(df -h / 2>/dev/null | grep -v Filesystem | awk '{print $3"/"$2" ("$5")"}' || echo 'N/A')"
    fi
    
    if [ -f /proc/uptime ]; then
        uptime_seconds=$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)
        days=$((uptime_seconds/86400))
        hours=$((uptime_seconds%86400/3600))
        minutes=$((uptime_seconds%3600/60))
        echo "运行时间: ${days}天${hours}小时${minutes}分钟"
    fi
}

# ===================== 主菜单 =====================
show_menu() {
    clear
    local model hostname
    model=$(get_router_model)
    hostname=$(get_router_hostname)
    
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    GL-iNet BE-3600 配置工具箱                    ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║ 设备型号: $model"
    echo "║ 设备名称: $hostname"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo
    echo "  1. 一键安装 iStoreOS 风格（完整套件）"
    echo "  2. 单独安装 Argon 紫色主题"
    echo "  3. 单独安装 iStore 商店"
    echo "  4. 设置第三方软件源"
    echo "  5. 配置风扇温度（带风扇机型）"
    echo "  6. 启用/关闭 AdGuardHome"
    echo "  7. 安装 UI 辅助插件"
    echo "  8. 安装高级卸载插件"
    echo "  9. 安装 OpenClash"
    echo " 10. 安装 Docker 和 DockerMan"
    echo " 11. 恢复出厂设置"
    echo " 12. 系统状态检查"
    echo
    echo "  Q. 退出"
    echo
    echo "请选择操作 [1-12/Q]:"
}

# ===================== 主程序 =====================
main() {
    # 初始化检查
    require_root
    
    trap 'cleanup_temp_dirs; exit 0' INT TERM
    trap 'cleanup_temp_dirs' EXIT
    
    log_info "开始运行配置工具箱"
    
    # 主循环
    while true; do
        show_menu
        read -r choice
        
        case "${choice:-}" in
            1)
                if check_internet_connection; then
                    install_iStoreOS_style
                    configure_system_basics
                    log_success "安装完成！请访问: http://192.168.8.1:8080"
                fi
                ;;
            2)
                install_argon_theme
                ;;
            3)
                if check_internet_connection; then
                    install_iStore
                fi
                ;;
            4)
                manage_software_sources "thirdparty"
                ;;
            5)
                configure_fan_temperature
                ;;
            6)
                toggle_adguard_home
                ;;
            7)
                install_ui_helper
                ;;
            8)
                install_advanced_uninstaller
                ;;
            9)
                if check_internet_connection; then
                    install_openclash
                fi
                ;;
            10)
                if check_internet_connection; then
                    install_docker
                fi
                ;;
            11)
                perform_factory_reset
                ;;
            12)
                show_system_status
                ;;
            q|Q)
                log_info "退出工具箱"
                break
                ;;
            *)
                log_warning "无效选项"
                ;;
        esac
        
        echo
        read -rp "按回车键继续..." _
    done
}

# 执行主程序
main "$@"
