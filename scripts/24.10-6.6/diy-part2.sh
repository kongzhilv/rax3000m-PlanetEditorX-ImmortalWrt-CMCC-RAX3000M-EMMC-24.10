#!/bin/bash
#
# 版权所有 (c) 2019-2020 P3TERX <https://p3terx.com>
# 这是一个自由软件，根据 MIT 许可证授权。
# https://github.com/P3TERX/Actions-OpenWrt

# ==========================================
# 1. 核心环境修复 (Rust 跨平台目标及 LLVM 修复)
# ==========================================
rustup target add aarch64-unknown-linux-musl || true
sed -i 's/find "$1" -type f -name "\\*.orig" -exec rm -f {} \\;/find "$1" -type f -name "\\*.orig" -a ! -name "Cargo.toml.orig" -exec rm -f {} \\;/g' scripts/patch-kernel.sh || true
echo "# CONFIG_RUST_DOWNLOAD_CI_LLVM is not set" >> .config
sed -i 's/download-ci-llvm.*/download-ci-llvm = false/g' feeds/packages/lang/rust/Makefile || true
find feeds/packages/lang/rust/ -type f -name "*.toml" -exec sed -i 's/download-ci-llvm.*/download-ci-llvm = false/g' {} + || true

# ==========================================
# 2. 软件包预装配置
# ==========================================
echo "CONFIG_PACKAGE_luci-app-openclash=y" >> .config
echo "CONFIG_PACKAGE_luci-app-wechatpush=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-wechatpush-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_adguardhome=y" >> .config 
echo "CONFIG_PACKAGE_luci-app-adguardhome=y" >> .config 

# 添加 USB 基础驱动与 5G 网络支持
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
# 3. 固件特定文件处理
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
# 4. 防火墙 wan 区域显示逻辑修复
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
# 5. 5G/USB IPv6 中继自愈守护脚本
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
            logger -t "IPv6-Guardian" "检测到移动网络接口 $INTERFACE 请求前缀，执行防死锁纠正..."
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
# 6. 【核心方案】Go 编译器源码级动态依赖修复
# ==========================================
echo "正在注入 Go 编译器动态修复逻辑..."

# (A) 解除断网编译限制，切换为国内代理加速
find feeds/ -type f -name "golang-values.mk" -exec sed -i 's/GOPROXY=off/GOPROXY=https:\/\/goproxy.cn,direct/g' {} +

# (B) 解除严格离线 vendor 模式限制，允许联网下载依赖
find feeds/ -type f -name "golang-package.mk" -exec sed -i 's/-mod=vendor/-mod=mod/g' {} +
find feeds/ -type f -name "golang-package.mk" -exec sed -i 's/-mod=readonly/-mod=mod/g' {} +

# (C) 在 Makefile 核心编译步骤前，强制注入 go mod download 和 tidy 命令
# 这将使所有存在依赖 Bug 的组件（如 docker-compose、sing-box 等）在编译时自动联网修复
find feeds/ -type f -name "golang-package.mk" -exec sed -i 's/$(GO_BIN) build/$(GO_BIN) mod download -e || true ; $(GO_PKG_VARS) $(GO_BIN) mod tidy -e || true ; $(GO_PKG_VARS) $(GO_BIN) build/g' {} +
# ==========================================
