# MerlinLucky (梅林 KoolCenter 软件中心 Lucky 插件)

一款运行于华硕梅林 / 官改路由器（KoolCenter 软件中心）的高性能网络工具插件，由 Golang 编写，集成了 **反向代理 / DDNS / Web服务 / Stun内网穿透 / 网络唤醒 / 计划任务 / ACME自动证书 / 网络存储** 等强大网络功能。

- **上游核心开源项目**：[gdy666/lucky](https://github.com/gdy666/lucky)
- **本项目主页**：[mizb/MerlinLucky](https://github.com/mizb/MerlinLucky)

---

## 🌟 核心特色与深度调优

- **纯轻量 XiaoJV 核心**：移除了不适用于路由器的重型组件（如 WAF 与 gRPC），常驻内存低至 15MB~25MB，零冗余开销。
- **文件句柄百万级放开**：启动时注入 `ulimit -n 65535` 与 `fs.file-max=1048576`，彻底杜绝大流量反代与穿透时的断流与丢包。
- **Go 运行时内存精细调控**：注入 `GOMEMLIMIT=64MiB` 与 `MADV_DONTNEED`，杜绝 GC STW 停顿，常驻物理内存平稳可控。
- **五重安全在线自愈更新**：内置硬件架构探测、沙盒可用性预检、配置隔离保护与自动秒级回滚机制，永不升级错架构，绝不丢失配置与证书。

---

## 🚀 安装与更新方式

### 方式 1：梅林终端 SSH 一键在线安装 / 更新（🌟 强烈推荐）

无需先下载文件到本地电脑，在路由器 SSH 终端直接粘贴执行以下单行命令，自动识别硬件架构并完成安装与平滑升级：

```bash
sh -c "$(curl -kfsSL https://raw.githubusercontent.com/mizb/MerlinLucky/main/online_install.sh)"
```

> **说明**：该脚本内置国内 GitHub 加速镜像降级，升级过程保留 `/koolshare/configs/lucky/` 下的全部业务规则、DDNS 与证书，无需重新配置。

---

### 方式 2：插件管理页面【一键在线更新】与【定时自更】

已安装本插件的用户，可直接在梅林路由器后台操作：
1. 登录路由器后台 $\to$ **软件中心** $\to$ **Lucky**；
2. 在状态面板中查看当前运行版本与线上最新版本；
3. 点击 **`[ 🔍 检查更新 ]`** $\to$ 发现新版本后点击 **`[ 🚀 立即更新 ]`**；
4. 亦可勾选 **`[√] 每天凌晨 04:30 自动巡检并静默升级内核`**，永葆最新稳定内核。

---

### 方式 3：软件中心离线上传安装

1. 从 [Releases](https://github.com/mizb/MerlinLucky/releases) 下载对应架构的离线安装包：
   - 🌟 **华硕天选 AX6000 (MT7986A)、GT-AX6000、RT-AX86U Pro 等 64 位机型**：下载 `MerlinLucky_v*.tar.gz` 或 `*_arm64.tar.gz`
   - **老款 32 位机型 (如 RT-AC86U 等)**：下载 `*_armv7.tar.gz`
2. 进入梅林后台 $\to$ **软件中心** $\to$ **离线安装** $\to$ 上传 `.tar.gz` 文件安装即可。

---

## 🛡️ 硬件机型支持

| 平台架构 | 适配芯片型号 | 代表路由器机型 | 推荐安装包 |
| :--- | :--- | :--- | :--- |
| **ARM64 (aarch64)** | 联发科 MT7986A / 博通 BCM4908 / BCM4912 | 华硕天选 AX6000 (TX-AX6000)、TUF-AX4200Q、ROG GT-AX6000、RT-AX86U Pro 等 | `MerlinLucky_v*_arm64.tar.gz` (默认) |
| **ARMv7 (32位)** | 博通 BCM4906 / MT7622 等 | RT-AC86U、RT-AX88U (早期rev) 等 | `MerlinLucky_v*_armv7.tar.gz` |

---

## 💡 使用技巧：自签与泛域名证书注入路由器

Lucky 支持通过 ACME 申请 Cloudflare 等泛域名 SSL 证书，并可设置自动触发脚本将最新证书软链接/复制给路由器 Web 管理界面或 WebDAV 使用：

```bash
cp /koolshare/configs/lucky/ca/CF.crt /tmp/etc/cert.crt
cp /koolshare/configs/lucky/ca/CF.crt /tmp/etc/cert.pem
cp /koolshare/configs/lucky/ca/CF.key /tmp/etc/key.pem
cat /tmp/etc/key.pem /tmp/etc/cert.pem > /tmp/etc/server.pem
chmod 640 /tmp/etc/key.pem
tar -C / -czf /jffs/cert.tgz etc/cert.pem etc/key.pem
service restart_httpd
local aicloud_enable=$(nvram get aicloud_enable)
if [ "${aicloud_enable}" == "1" ]; then
	service restart_webdav
fi
```
