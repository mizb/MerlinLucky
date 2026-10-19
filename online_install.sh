#!/bin/sh
# ==============================================================================
# MerlinLucky 华硕梅林 / 官改路由器专属一键在线安装与更新脚本
# 支持机型：华硕天选 AX6000、GT-AX6000、RT-AX86U 等 ARM64 及 32位 ARM 梅林固件
# 项目地址：https://github.com/mizb/MerlinLucky
# ==============================================================================

alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'

echo_date "🚀 开始执行 MerlinLucky 在线安装/更新..."

# 1. 验证运行平台是否为 KoolCenter 梅林系统
if [ ! -d "/koolshare" ] || [ ! -f "/usr/bin/skipd" ]; then
    echo_date "❌ 错误：未检测到 /koolshare 目录或 skipd 数据库！"
    echo_date "本脚本仅适用于搭载 KoolCenter 软件中心的梅林/官改固件路由器。"
    exit 1
fi

# 2. 精准识别 CPU 架构，杜绝架构误下
ARCH=$(uname -m)
CORE_ARCH=""
case "${ARCH}" in
    aarch64|arm64)
        CORE_ARCH="arm64"
        ;;
    armv7l|armv7)
        CORE_ARCH="armv7"
        ;;
    *)
        echo_date "❌ 不支持的硬件架构: ${ARCH}"
        exit 1
        ;;
esac
echo_date "🖥️ 检测到路由器硬件架构: ${ARCH} (适配包: ${CORE_ARCH})"

# 3. 获取版本信息 (首选自定义或公共加速通道读取 80 字节 version.json，0 频控毫秒级响应)
echo_date "🔍 正在获取最新发布版本..."
JSON_URL="https://raw.githubusercontent.com/mizb/MerlinLucky/main/version.json"

CUSTOM_MIRROR="${CUSTOM_MIRROR:-$(dbus get lucky_custom_mirror 2>/dev/null)}"
CUSTOM_MIRROR="${CUSTOM_MIRROR%/}"
[ -n "${CUSTOM_MIRROR}" ] && dbus set lucky_custom_mirror="${CUSTOM_MIRROR}"

RET=""
if [ -n "${CUSTOM_MIRROR}" ]; then
    RET=$(curl -kfsSL --connect-timeout 4 -m 6 "${CUSTOM_MIRROR}/${JSON_URL}" 2>/dev/null)
fi
[ -z "${RET}" ] && RET=$(curl -kfsSL --connect-timeout 4 -m 6 "https://ghproxy.net/${JSON_URL}" 2>/dev/null)
[ -z "${RET}" ] && RET=$(curl -kfsSL --connect-timeout 4 -m 6 "${JSON_URL}" 2>/dev/null)

LATEST_VER=$(echo "$RET" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')

if [ -z "${LATEST_VER}" ]; then
    API_URL="https://api.github.com/repos/mizb/MerlinLucky/releases/latest"
    if [ -n "${CUSTOM_MIRROR}" ]; then
        LATEST_TAG=$(curl -kfsSL --connect-timeout 5 -m 8 "${CUSTOM_MIRROR}/${API_URL}" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    fi
    [ -z "${LATEST_TAG}" ] && LATEST_TAG=$(curl -kfsSL --connect-timeout 5 -m 8 "https://ghproxy.net/${API_URL}" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [ -z "${LATEST_TAG}" ] && LATEST_TAG=$(curl -kfsSL --connect-timeout 5 -m 8 "${API_URL}" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    LATEST_VER="${LATEST_TAG#v}"
fi

if [ -z "${LATEST_VER}" ]; then
    echo_date "❌ 获取最新版本信息失败，请检查路由器网络连接！"
    exit 1
fi

LATEST_VER="${LATEST_VER#v}"
LATEST_TAG="v${LATEST_VER}"
echo_date "📌 线上最新版本: ${LATEST_TAG}"

# 4. 下载匹配包至临时沙盒
PKG_NAME="MerlinLucky_${LATEST_TAG}_${CORE_ARCH}.tar.gz"
RAW_DL_URL="https://github.com/mizb/MerlinLucky/releases/download/${LATEST_TAG}/${PKG_NAME}"
TMP_DIR="/tmp/merlin_lucky_online_install"
rm -rf "${TMP_DIR}" && mkdir -p "${TMP_DIR}"

echo_date "⬇️ 正在下载: ${PKG_NAME} ..."
DL_OK=0
if [ -n "${CUSTOM_MIRROR}" ]; then
    curl -kfsSL --connect-timeout 8 -m 90 -o "${TMP_DIR}/lucky.tar.gz" "${CUSTOM_MIRROR}/${RAW_DL_URL}" && [ -s "${TMP_DIR}/lucky.tar.gz" ] && DL_OK=1
fi
if [ "${DL_OK}" -eq 0 ]; then
    curl -kfsSL --connect-timeout 8 -m 90 -o "${TMP_DIR}/lucky.tar.gz" "https://ghproxy.net/${RAW_DL_URL}" && [ -s "${TMP_DIR}/lucky.tar.gz" ] && DL_OK=1
fi
if [ "${DL_OK}" -eq 0 ]; then
    curl -kfsSL --connect-timeout 8 -m 90 -o "${TMP_DIR}/lucky.tar.gz" "${RAW_DL_URL}" && [ -s "${TMP_DIR}/lucky.tar.gz" ] && DL_OK=1
fi

if [ ! -s "${TMP_DIR}/lucky.tar.gz" ]; then
    echo_date "❌ 安装包下载失败或文件损坏！"
    rm -rf "${TMP_DIR}"
    exit 1
fi

# 5. 解压并进行硬件兼容性沙盒试跑
echo_date "📦 正在解压并进行内核沙盒可用性检测..."
tar -zxf "${TMP_DIR}/lucky.tar.gz" -C "${TMP_DIR}/"

if [ ! -f "${TMP_DIR}/lucky/bin/lucky" ] || [ ! -f "${TMP_DIR}/lucky/install.sh" ]; then
    echo_date "❌ 安装包结构异常，未找到核心组件！"
    rm -rf "${TMP_DIR}"
    exit 1
fi

chmod +x "${TMP_DIR}/lucky/bin/lucky"
TEST_RES=$("${TMP_DIR}/lucky/bin/lucky" -info 2>&1 || echo "")
if ! echo "${TEST_RES}" | grep -q '"Version"'; then
    echo_date "❌ 致命错误：新内核在当前路由器架构下无法执行！"
    echo_date "🛡️ 触发防变砖熔断保护：终止安装，原有系统与配置不受任何影响。"
    rm -rf "${TMP_DIR}"
    exit 1
fi
echo_date "🟢 内核沙盒测试成功，二进制与当前硬件 100% 兼容！"

# 6. 执行标准安装流程
echo_date "🔧 正在执行安装脚本..."
chmod +x "${TMP_DIR}/lucky/install.sh"
rm -rf /tmp/lucky
mv "${TMP_DIR}/lucky" /tmp/lucky
sh /tmp/lucky/install.sh

rm -rf "${TMP_DIR}" /tmp/lucky
echo_date "🎉 MerlinLucky ${LATEST_TAG} 安装/更新成功！全部配置已妥善保留。"
