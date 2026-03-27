#!/bin/bash
#
# 版权所有 (c) 2019-2020 P3TERX <https://p3terx.com>
# 这是一个自由软件，根据 MIT 许可证授权。

# ==========================================
# 0. 核心排雷：清理被 GitHub Actions 污染的缓存
# ==========================================
echo "正在物理抹除被污染的 Go 依赖缓存..."
rm -rf ./dl/go-mod-cache
rm -rf ./dl/*go*.tar.*
rm -rf ./dl/*rust*.tar.*

# ==========================================
# 1. 编译环境修复 (Rust 跨平台目标及 LLVM 拦截)
# ==========================================
rustup target add aarch64-unknown-linux-musl || true
sed -i 's/find "$1" -type f -name "\\*.orig" -exec rm -f {} \\;/find "$1" -type f -name "\\*.orig" -a ! -name "Cargo.toml.orig" -exec rm -f {} \\;/g' scripts/patch-kernel.sh || true
echo "# CONFIG_RUST_DOWNLOAD_CI_LLVM is not set" >> .config
sed -i 's/download-ci-llvm.*/download-ci-llvm = false/g' feeds/packages/lang/rust/Makefile || true
find feeds/packages/lang/rust/ -type f -name "*.toml" -exec sed -i 's/download-ci-llvm.*/download-ci-llvm = false/g' {} + || true

# ==========================================
# 2. 软件包预装配置 (所有包已成功编译，解决最后打包冲突)
# ==========================================
echo "CONFIG_PACKAGE_luci-app-openclash=y" >> .config
echo "CONFIG_PACKAGE_luci-app-wechatpush=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-wechatpush-zh-cn=y" >> .config

echo "CONFIG_PACKAGE_adguardhome=y" >> .config 
echo "CONFIG_PACKAGE_luci-app-adguardhome=y" >> .config 
echo "CONFIG_PACKAGE_docker-compose=y" >> .config
echo "CONFIG_PACKAGE_filebrowser=y" >> .config
echo "CONFIG_PACKAGE_luci-app-filebrowser=y" >> .config
echo "CONFIG_PACKAGE_sing-box=y" >> .config

# 【临门一脚：解决 Copilot 发现的冲突报错】
# 物理删除导致固件打包冲突的 filebrowser-go 变体及其汉化包
rm -rf feeds/luci/applications/luci-app-filebrowser-go
sed -i '/filebrowser-go/d' .config || true
echo "# CONFIG_PACKAGE_luci-app-filebrowser-go is not set" >> .config
echo "# CONFIG_PACKAGE_luci-i18n-filebrowser-go-zh-cn is not set" >> .config

# USB 基础驱动与 5G/4G 拨号模块网卡驱动
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
# 3. 固件特定文件处理 (MT7981 EEPROM)
# ==========================================
rm -f package/mtk/drivers/mt_wifi/files/mt7981-default-eeprom/e2p
if [ $? -eq 0 ]; then
  echo "已删除 mt7981-default-eeprom/e2p"
fi

EEPROM_FILE="package/mtk/drivers/mt_wifi/files/mt7981-default-eeprom/MT7981_iPAiLNA_EEPROM.bin"
if [ -f "$EEPROM_FILE" ]; then
  mkdir -p files/lib/firmware
  ln -sf /lib/firmware/MT7981_iPAiLNA_EEPROM.bin files/lib/firmware/e2p
  echo "EEPROM 符号链接已创建"
else
  echo "警告：$EEPROM_FILE 不存在，跳过符号链接创建"
fi

# ==========================================
# 4. 防火墙 UI 显示状态修复
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
# 5. 蜂窝网络/USB 共享 IPv6 中继自愈守护进程
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
            logger -t "IPv6-Guardian" "检测到外接物理网络接口 $INTERFACE 发生 PD 锁死风险，执行配置阻断..."
            uci set network."$INTERFACE".reqprefix='disabled'
            uci commit network
            
            ifdown "$INTERFACE"
            sleep 2
            ifup "$INTERFACE"
            exit 0
        fi

        logger -t "IPv6-Guardian" "下发热插拔指令，强制 odhcpd 服务重载 $INTERFACE 中继链路..."
        sleep 5
        /etc/init.d/odhcpd restart
        ;;
esac
exit 0
EOF
chmod +x package/base-files/files/etc/hotplug.d/iface/98-5g-ipv6-guardian

# ==========================================
# 6. Go 编译器网络环境双重保障
# ==========================================
find feeds/ -type f -name "golang-package.mk" -exec sed -i 's/GOPROXY=off/GOPROXY=https:\/\/goproxy.io,direct/g' {} +
find feeds/ -type f -name "golang-package.mk" -exec sed -i 's/-mod=vendor/-mod=mod/g' {} +
find feeds/ -type f -name "golang-package.mk" -exec sed -i 's/-mod=readonly/-mod=mod/g' {} +
