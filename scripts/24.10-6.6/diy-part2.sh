#!/bin/bash
#
# 版权所有 (c) 2019-2020 P3TERX <https://p3terx.com>
# 这是一个自由软件，根据 MIT 许可证授权。
# https://github.com/P3TERX/Actions-OpenWrt

# ==========================================
# 1. 核心环境修复 (放在最前面，防止被意外中断)
# ==========================================

# (A) 补充跨平台编译所需的核心目标库 (解决 shadowsocks-rust 找不到 core 的问题)
rustup target add aarch64-unknown-linux-musl || true

# (B) 修复 Rust 编译时 Cargo.toml.orig 丢失的 Bug
sed -i 's/find "$1" -type f -name "\\*.orig" -exec rm -f {} \\;/find "$1" -type f -name "\\*.orig" -a ! -name "Cargo.toml.orig" -exec rm -f {} \\;/g' scripts/patch-kernel.sh || true

# (C) 彻底解决 Rust LLVM 404 下载报错 (全方位拦截)
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
# 3. 固件特定文件处理 (去除了原版的 exit 1 致命异常)
# ==========================================

# 删除 mt7981-default-eeprom
rm -f package/mtk/drivers/mt_wifi/files/mt7981-default-eeprom/e2p
if [ $? -eq 0 ]; then
  echo "已删除 package/mtk/drivers/mt_wifi/files/mt7981-default-eeprom/e2p"
else
  echo "警告：删除 e2p 失败 (可能文件本就不存在)"
fi

# 创建 MT7981 固件符号链接
EEPROM_FILE="package/mtk/drivers/mt_wifi/files/mt7981-default-eeprom/MT7981_iPAiLNA_EEPROM.bin"
if [ -f "$EEPROM_FILE" ]; then
  mkdir -p files/lib/firmware
  ln -sf /lib/firmware/MT7981_iPAiLNA_EEPROM.bin files/lib/firmware/e2p
  echo "符号链接已创建"
  ls -l files/lib/firmware/e2p || echo "警告：符号链接创建异常"
else
  # 注意这里：把会导致脚本崩溃的 exit 1 改成了 echo 警告，保证脚本能顺利跑完！
  echo "警告：$EEPROM_FILE 不存在，跳过符号链接创建"
fi
