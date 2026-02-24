#!/bin/sh

# GL-iNet BE-3600 配置工具箱
# 稳定兼容版

# ===================== 基础配置 =====================
set_timezone() {
    echo "设置时区为 Asia/Shanghai..."
    uci set system.@system[0].zonename='Asia/Shanghai'
    uci set system.@system[0].timezone='CST-8'
    uci commit system
    echo "时区设置完成"
}

install_argon_theme() {
    echo "安装 Argon 紫色主题..."
    
    # 创建临时目录
    mkdir -p /tmp/argon_theme
    cd /tmp/argon_theme
    
    # 下载主题文件
    echo "下载主题文件..."
    wget -q --user-agent="Mozilla/5.0" -O luci-theme-argon.ipk "https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/theme/luci-theme-argon-master_2.2.9.4_all.ipk" || {
        echo "主题下载失败"
        return 1
    }
    
    # 安装主题
    echo "安装 Argon 主题..."
    opkg install luci-theme-argon.ipk --force-depends 2>/dev/null
    
    # 设置主题
    uci set luci.main.mediaurlbase='/luci-static/argon'
    uci set luci.main.lang='zh_cn'
    uci commit luci
    
    echo "Argon 主题安装完成"
}

install_iStore() {
    echo "安装 iStore 应用商店..."
    
    # 更新软件源
    opkg update
    
    # 下载iStore相关IPK
    mkdir -p /tmp/istore
    cd /tmp/istore
    
    # 从iStore官方源下载
    echo "下载 iStore 组件..."
    wget -q -O- "https://repo.istoreos.com/repo/all/store/" | grep -oE 'href="[^"]+\.ipk"' | cut -d'"' -f2 | while read ipk; do
        echo "下载: $ipk"
        wget -q "https://repo.istoreos.com/repo/all/store/$ipk"
    done
    
    # 安装所有IPK
    echo "安装 iStore 组件..."
    opkg install ./*.ipk 2>/dev/null || true
    
    echo "iStore 安装完成"
}

install_docker() {
    echo "安装 Docker 和 DockerMan..."
    
    # 更新软件源
    opkg update
    
    # 安装Docker组件
    echo "安装 Docker 组件..."
    opkg install dockerd 2>/dev/null || echo "dockerd 安装失败"
    opkg install docker-compose 2>/dev/null || echo "docker-compose 安装失败"
    opkg install luci-app-dockerman 2>/dev/null || echo "luci-app-dockerman 安装失败"
    opkg install luci-i18n-dockerman-zh-cn 2>/dev/null || echo "docker中文语言包安装失败"
    
    # 启动Docker服务
    echo "启动 Docker 服务..."
    /etc/init.d/dockerd enable
    /etc/init.d/dockerd start
    
    echo "Docker 安装完成"
    echo "访问地址: http://192.168.8.1/cgi-bin/luci/admin/docker"
}

install_openclash() {
    echo "安装 OpenClash..."
    
    # 创建临时目录
    mkdir -p /tmp/openclash
    cd /tmp/openclash
    
    # 下载最新版OpenClash
    echo "下载 OpenClash..."
    wget -q -O luci-app-openclash.ipk "https://github.com/vernesong/OpenClash/releases/latest/download/luci-app-openclash.ipk" || {
        echo "OpenClash 下载失败，请检查网络连接"
        return 1
    }
    
    # 安装OpenClash
    echo "安装 OpenClash..."
    opkg install luci-app-openclash.ipk --force-depends 2>/dev/null
    
    echo "OpenClash 安装完成"
    echo "访问地址: http://192.168.8.1/cgi-bin/luci/admin/services/openclash"
}

show_menu() {
    clear
    echo "========================================"
    echo "     GL-iNet BE-3600 配置工具箱         "
    echo "========================================"
    echo ""
    echo "1. 设置系统时区"
    echo "2. 安装 Argon 紫色主题"
    echo "3. 安装 iStore 应用商店"
    echo "4. 安装 Docker 和 DockerMan"
    echo "5. 安装 OpenClash"
    echo "6. 一键安装所有组件"
    echo ""
    echo "0. 退出"
    echo ""
    echo "========================================"
    echo "请选择操作 [0-6]: "
}

main() {
    # 检查是否以root运行
    if [ "$(id -u)" != "0" ]; then
        echo "请使用root权限运行此脚本"
        exit 1
    fi
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1)
                set_timezone
                ;;
            2)
                install_argon_theme
                ;;
            3)
                install_iStore
                ;;
            4)
                install_docker
                ;;
            5)
                install_openclash
                ;;
            6)
                echo "开始一键安装所有组件..."
                set_timezone
                install_argon_theme
                install_iStore
                install_docker
                install_openclash
                echo "所有组件安装完成!"
                echo "请访问: http://192.168.8.1:8080"
                ;;
            0)
                echo "退出工具箱"
                exit 0
                ;;
            *)
                echo "无效选项，请重新选择"
                ;;
        esac
        
        echo ""
        echo "按回车键继续..."
        read _
    done
}

# 执行主函数
main "$@"
