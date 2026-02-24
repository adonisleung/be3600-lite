#!/bin/sh

# 安装 Argon 主题
install_argon_theme() {
  opkg update
  opkg install luci-lib-ipkg
  wget -q -O /tmp/luci-theme-argon.ipk https://cafe.cpolar.top/wkdaily/gl-inet-onescript/raw/branch/master/theme/luci-theme-argon-master_2.2.9.4_all.ipk
  wget -q -O /tmp/luci-app-argon-config.ipk https://cafe.cpolar.top/wkdaily/gl-inet-onescript/raw/branch/master/theme/luci-app-argon-config_0.9_all.ipk
  wget -q -O /tmp/luci-i18n-argon-config-zh-cn.ipk https://cafe.cpolar.top/wkdaily/gl-inet-onescript/raw/branch/master/theme/luci-i18n-argon-config-zh-cn.ipk
  opkg install /tmp/luci-theme-argon.ipk /tmp/luci-app-argon-config.ipk /tmp/luci-i18n-argon-config-zh-cn.ipk --force-depends
}

# 安装 iStore 商店
install_istore() {
  opkg update
  mkdir -p /tmp/ipk_store && cd /tmp/ipk_store
  wget -q -O luci-app-store.ipk https://repo.istoreos.com/repo/all/store/luci-app-store_latest_all.ipk
  opkg install luci-app-store.ipk --force-depends
}

# 安装 Quickstart 首页向导
install_quickstart() {
  opkg update
  mkdir -p /tmp/ipk_downloads && cd /tmp/ipk_downloads
  wget -q -O luci-app-quickstart.ipk https://repo.istoreos.com/repo/all/nas_luci/luci-app-quickstart_latest_all.ipk
  opkg install luci-app-quickstart.ipk --force-depends
}

# 安装 Docker
install_docker() {
  opkg update
  opkg install dockerd docker-compose luci-app-dockerman --force-depends
  /etc/init.d/dockerd enable
  /etc/init.d/dockerd start
}

# 安装最新版 OpenClash
install_openclash() {
  mkdir -p /tmp/openclash && cd /tmp/openclash
  wget -q -O luci-app-openclash.ipk https://github.com/vernesong/OpenClash/releases/latest/download/luci-app-openclash.ipk
  opkg install luci-app-openclash.ipk --force-depends
}

# 菜单
while true; do
  clear
  echo "******** GL-BE3600 一键工具箱 (精简版) ********"
  echo "1. 安装 Argon 紫色主题"
  echo "2. 安装 iStore 商店"
  echo "3. 安装 Quickstart 首页向导"
  echo "4. 一键安装 Docker"
  echo "5. 一键安装最新版 OpenClash"
  echo "Q. 退出"
  read -p "请选择一个选项: " choice

  case $choice in
    1) install_argon_theme ;;
    2) install_istore ;;
    3) install_quickstart ;;
    4) install_docker ;;
    5) install_openclash ;;
    q|Q) exit 0 ;;
    *) echo "无效选项，请重新选择。" ;;
  esac

  read -p "按 Enter 键继续..."
done
