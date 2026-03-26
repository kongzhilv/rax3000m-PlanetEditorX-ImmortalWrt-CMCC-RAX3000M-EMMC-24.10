#!/bin/bash
#
# 版权所有 (c) 2019-2020 P3TERX <https://p3terx.com>
# 这是一个自由软件，根据 MIT 许可证授权。
# https://github.com/P3TERX/Actions-OpenWrt

# ==========================================
# 1. 核心环境修复 (跨平台编译与上游 Bug 修复)
# ==========================================
# 补充跨平台编译所需的核心目标库 (解决 shadowsocks-rust 等找不到 core 的问题)
rustup target add aarch64-unknown-linux-musl || true

# 修复 Rust 编译时 Cargo.toml.orig 丢失的 Bug
sed -i 's/find "$1" -type f -name "\\*.orig" -exec rm -f {} \\;/find "$1" -type f -name "\\*.orig" -a ! -name "Cargo.toml.orig" -exec rm -f {} \\;/g' scripts/patch-kernel.sh || true

# 彻底解决 Rust LLVM 404 下载报错 (全方位拦截)
echo "# CONFIG_RUST_DOWNLOAD_CI_LLVM is not set" >> .config
sed -i 's/download-ci-llvm.*/download-ci-llvm = false/g' feeds/packages/lang/rust/Makefile || true
find feeds/packages/lang/rust/ -type f -name "*.toml" -exec sed -i 's/download-ci-llvm.*/download-ci-llvm = false/g' {} + || true


# ==========================================
# 2. 软件包预装配置
# ==========================================
# 预装基础插件
echo "CONFIG_PACKAGE_luci-app-openclash=y" >> .config
echo "CONFIG_PACKAGE_luci-app-wechatpush=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-wechatpush-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_adguardhome=y" >> .config 
echo "CONFIG_PACKAGE_luci-app-adguardhome=y" >> .config 

# 添加 USB 基础驱动
echo "CONFIG_PACKAGE_kmod-usb-core=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config

# 添加 USB 有线网卡驱动
echo "CONFIG_PACKAGE_kmod-usb-net=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net-rtl8152=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net-asix-ax88179=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net-asix=y" >> .config

# 添加手机 USB 共享网络支持 & 4G/5G 模块
echo "CONFIG_PACKAGE_kmod-usb-net-rndis=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net-cdc-ether=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net-huawei-cdc-ncm=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-net-qmi-wwan=y" >> .config


# ==========================================
# 3. 固件特定文件处理 (去除了会导致报错中断的 exit 1)
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
# 6. 终极修复：绕过 docker-compose 源码编译 Bug，直接注入官方二进制程序
# ==========================================
# (A) 从编译清单中剔除存在源码依赖 Bug 的 docker-compose 包，阻止它去送死
sed -i 's/CONFIG_PACKAGE_docker-compose=y/# CONFIG_PACKAGE_docker-compose is not set/' .config || true

# (B) 建立固件的本地文件挂载点
mkdir -p files/usr/bin

# (C) 直接从 Docker 官方拉取完美适配 RAX3000M (ARM64) 架构的预编译程序
echo "正在下载官方 docker-compose 二进制文件..."
curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64 -o files/usr/bin/docker-compose

# (D) 赋予执行权限，固件刷入后即可直接在命令行输入 docker-compose 使用
chmod +x files/usr/bin/docker-compose
# ==========================================
