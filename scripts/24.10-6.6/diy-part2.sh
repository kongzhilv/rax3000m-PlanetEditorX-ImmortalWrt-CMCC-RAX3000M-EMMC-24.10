#!/bin/bash
#
# 版权所有 (c) 2019-2020 P3TERX <https://p3terx.com>
# 这是一个自由软件，根据 MIT 许可证授权。
# https://github.com/P3TERX/Actions-OpenWrt

# ==========================================
# 1. 核心环境修复 (跨平台编译与上游 Bug 修复)
# ==========================================
rustup target add aarch64-unknown-linux-musl || true
sed -i 's/find "$1" -type f -name "\\*.orig" -exec rm -f {} \\;/find "$1" -type f -name "\\*.orig" -a ! -name "Cargo.toml.orig" -exec rm -f {} \\;/g' scripts/patch-kernel.sh || true
echo "# CONFIG_RUST_DOWNLOAD_CI_LLVM is not set" >> .config
sed -i 's/download-ci-llvm.*/download-ci-llvm = false/g' feeds/packages/lang/rust/Makefile || true
find feeds/packages/lang/rust/ -type f -name "*.toml" -exec sed -i 's/download-ci-llvm.*/download-ci-llvm = false/g' {} + || true

# ==========================================
# 2. 软件包预装配置 (你的核心需求)
# ==========================================
echo "CONFIG_PACKAGE_luci-app-openclash=y" >> .config
echo "CONFIG_PACKAGE_luci-app-wechatpush=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-wechatpush-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_adguardhome=y" >> .config 
echo "CONFIG_PACKAGE_luci-app-adguardhome=y" >> .config 

# USB 基础驱动与 5G/4G 上网卡驱动
echo "CONFIG_PACKAGE_kmod-usb-core=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net-rtl8152=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net-asix-ax88179=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net-asix=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net-rndis=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net-cdc-ether=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net-huawei-cdc-ncm=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net-qmi-wwan=y" >> .config

# ==========================================
# 3. 固件特定文件处理 (防崩溃版)
# ==========================================
rm -f package/mtk/drivers/mt_wifi/files/mt7981-default-eeprom/e2p
if [ $? -eq 0 ]; then
  echo "已删除 mt7981-default-eeprom/e2p"
fi

EEPROM_FILE="package/mtk/drivers/mt_wifi/files/mt7981-default-eeprom/MT7981_iPAiLNA_EEPROM.bin"
if [ -f "$EEPROM_FILE" ]; then
  mkdir -p files/lib/firmware
  ln -sf /lib/firmware/MT7981_iPAiLNA_EEPROM.bin files/lib/firmware/e2p
  echo "符号链接已创建"
else
  echo "警告：$EEPROM_FILE 不存在，跳过符号链接创建"
fi

# ==========================================
# 4. 高泛用性修复：防火墙 wan 区域显示为“空”
# ==========================================
mkdir -p package/base-files/files/etc/uci-defaults
cat <<EOF > package/base-files/files/etc/uci-defaults/99-fix-firewall-wan
#!/bin/sh
for i in \$(seq 0 10); do
    zone_name=\$(uci -q get firewall.@zone[\$i].name)
    if [ "\$zone_name" = "wan" ]; then
        uci -q set firewall.@zone[\$i].network='wan wan6'
        uci commit firewall
        break
    fi
done
exit 0
EOF

# ==========================================
# 5. 终极泛用性修复：5G/USB IPv6 中继自愈守护脚本
# ==========================================
mkdir -p package/base-files/files/etc/hotplug.d/iface
cat <<'EOF' > package/base-files/files/etc/hotplug.d/iface/98-5g-ipv6-guardian
#!/bin/sh
[ "$ACTION" = "ifup" ] || exit 0

dev_prefix=$(echo "$DEVICE" | grep -o '^[a-zA-Z]*')

case "$dev_prefix" in
    usb|wwan|rmnet|modem)
        proto=$(uci -q get network."$INTERFACE".proto)
        reqprefix=$(uci -q get network."$INTERFACE".reqprefix)
        
        if [ "$proto" = "dhcpv6" ] && [ "$reqprefix" != "disabled" ]; then
            logger -t "IPv6-Guardian" "检测到移动网络/USB接口 $INTERFACE 请求前缀，执行防死锁纠正..."
            uci set network."$INTERFACE".reqprefix='disabled'
            uci commit network
            
            ifdown "$INTERFACE"
            sleep 2
            ifup "$INTERFACE"
            exit 0
        fi

        logger -t "IPv6-Guardian" "刷新 odhcpd 中继服务以适配 $INTERFACE..."
        sleep 5
        /etc/init.d/odhcpd restart
        ;;
esac
exit 0
EOF
chmod +x package/base-files/files/etc/hotplug.d/iface/98-5g-ipv6-guardian

# ==========================================
# 6. 【全面清扫】物理毁灭所有近期损坏的 Go/Rust 边缘插件
# ==========================================
echo "开始清理上游损坏的插件源码..."
rm -rf feeds/packages/utils/docker-compose
rm -rf feeds/packages/utils/filebrowser
rm -rf feeds/luci/applications/luci-app-filebrowser
rm -rf feeds/packages/net/sing-box
rm -rf feeds/luci/applications/luci-app-sing-box
rm -rf feeds/packages/net/rustdesk-server
rm -rf feeds/luci/applications/luci-app-rustdesk-server

# 暴力清除 .config 中的配置残留
sed -i '/docker-compose/d' .config || true
sed -i '/filebrowser/d' .config || true
sed -i '/sing-box/d' .config || true
sed -i '/rustdesk/d' .config || true

echo "# CONFIG_PACKAGE_docker-compose is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-docker-compose is not set" >> .config
echo "# CONFIG_PACKAGE_filebrowser is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-filebrowser is not set" >> .config
echo "# CONFIG_PACKAGE_sing-box is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-sing-box is not set" >> .config
echo "# CONFIG_PACKAGE_rustdesk-server is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-rustdesk-server is not set" >> .config

# 建立固件的本地文件挂载点
mkdir -p files/usr/bin

# 保留 docker-compose 的官方二进制版注入 (不参与源码编译，完美避开 Bug)
echo "正在下载官方 docker-compose 二进制文件..."
curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64 -o files/usr/bin/docker-compose
chmod +x files/usr/bin/docker-compose
# ==========================================
