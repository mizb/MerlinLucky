# MerlinLucky (梅林 KoolCenter 软件中心 Lucky 插件)

一款专为华硕梅林改版 / 官改路由器（KoolCenter 软件中心）深度调优的高性能网络工具插件。由 Golang 编写，集成了 **反向代理 / DDNS / Web服务 / STUN内网穿透 / 网络唤醒 / 计划任务 / ACME自动证书 / 网络存储** 等强大网络功能。

- **上游核心开源项目**：[gdy666/lucky](https://github.com/gdy666/lucky)
- **本项目主页**：[mizb/MerlinLucky](https://github.com/mizb/MerlinLucky)
- **适配机型**：华硕天选 AX6000 (TX-AX6000, MT7986A)、TUF-AX4200Q、ROG GT-AX6000、RT-AX86U Pro、RT-AC86U 等全系 ARM64 / ARMv7 梅林与官改机型。

---

## 🌟 核心特色与深度调优

- **🍭 纯轻量 XiaoJV 核心定制**：移除了路由器不适用的重型组件（如 WAF 防火墙与 gRPC），常驻内存低至 **15MB ~ 25MB**，超低 CPU 占用。
- **⚡ 80 字节极简静态版本探针**：每次检测版本只需请求极简静态 `version.json`，比对速度仅需几十毫秒，**流量压缩 99%**，且**彻底免除 GitHub API 速率限制（Rate Limit: 60次/小时）**。
- **🚀 多梯队加速通道 & 私有镜像本地隔离**：
  - **默认公共通道**：支持 `ghproxy.net` 与 GitHub 官方源自动竞速降级；
  - **私有专属镜像**：支持在插件界面自定义私有加速源（如自建 Cloudflare Worker 加速反代），配置**仅保存在路由器本地 dbus，不上传 GitHub，严密保护个人域名与隐私**。
- **🔄 界面级双模更新与免重启保存**：
  - **手动一键热升级**：界面点击【🔍 检查更新】与【🚀 立即更新】，沙盒校验后秒级完成安全替换；
  - **定时静默自动巡检**：勾选开启【每天凌晨 04:30 自动巡检并静默升级内核】，自动跟踪最新发布；
  - **免重启独立保存**：新增独立的【💾 保存配置】按钮，更新镜像或定时策略时**绝不中断/重启正在运行的 Lucky 进程**。
- **🛡️ 五重防变砖安全熔断**：更新全过程采用沙盒机制——下载后先在独立沙盒解压，并在当前路由器架构下**预执行与校验返回值**，只有 100% 验证可用才替换文件；若架构不符或下载损坏则**瞬间熔断中止**，原有配置、证书与旧内核完好无损。
- **🚀 极速离线安装与 0 报错优化**：精简安装流程，剔除冗余 sleep 阻塞，将离线安装时间压缩至 0.8 秒以内，彻底根治 KoolCenter 前端因 5 秒硬超时引起的 `TypeError: Cannot read properties of undefined (reading 'includes')` 通讯失联假报错。
- **🔓 文件句柄与内存深度优化**：自动解除内核限制（`ulimit -n 65535` 与 `fs.file-max=1048576`），注入 `GOMEMLIMIT=64MiB` 与 `MADV_DONTNEED`，杜绝大流量反代断流与 GC STW 停顿。

---

## 🔄 界面内更新与加速源配置说明

安装本插件后，进入梅林路由器后台 $\to$ **软件中心** $\to$ **Lucky**，即可在主界面进行版本管理与加速配置：

### 1. 手动检查更新与一键热升级
* 点击 **`[ 🔍 检查更新 ]`**：插件将通过 80 字节极简静态探针毫秒级获取线上最新版本；
* 当检测到有新版本发布时，界面将自动弹出绿色的 **`[ 🚀 立即更新 ]`** 按钮；
* 点击后将在后台沙盒自动下载、校验并安全替换，**您的全部规则、DDNS、端口转发与证书 100% 完整保留**。

### 2. 每天凌晨 04:30 自动静默巡检升级
* 在更新区域勾选 **`[√] 每天凌晨 04:30 自动巡检并静默升级内核`**；
* 路由器后台将在每天深夜空闲时自动检测；若有新版则在后台静默完成沙盒校验并升级，第二天醒来即可享受最新内核。

### 3. 下载加速镜像配置（支持私有自建通道）
在 **【下载加速镜像】** 输入框中，您可以自由指定加速节点：
* **默认留空**：自动使用知名公共镜像通道（`https://ghproxy.net`）并在异常时降级至 GitHub 官方源；
* **填入私有加速源**：如果您搭建了专属的 GitHub 加速 Worker（例如 `https://your-worker-domain.com`），直接填入输入框即可；
* **隐私安全保障**：填写的加速地址**只保存在您路由器本地的 dbus 中（`lucky_custom_mirror`）**，绝不会提交或上传到任何远程服务器；
* **独立保存**：输入后点击右侧的 **`[ 💾 保存 ]`** 或底部的 **`[ 保存配置 ]`**，配置即刻生效，**无需重启 Lucky 进程，不会造成任何网络中断**。

---

## 🚀 安装方式

### 方式 1：梅林终端 SSH 一键在线安装 / 更新（🌟 强烈推荐）

无需在本地电脑下载安装包，通过 SSH 连接路由器后，直接粘贴执行以下单行命令：

```bash
sh -c "$(curl -kfsSL https://ghproxy.net/https://raw.githubusercontent.com/mizb/MerlinLucky/main/online_install.sh)"
```

> **提示**：
> 1. 安装脚本自带架构自适应（自动匹配 ARM64 或 ARMv7 包）与双通道加速下载；
> 2. 若要在一键安装时直接指定您的私有加速镜像，可运行：
>    ```bash
>    CUSTOM_MIRROR="https://your-worker-domain.com" sh -c "$(curl -kfsSL https://ghproxy.net/https://raw.githubusercontent.com/mizb/MerlinLucky/main/online_install.sh)"
>    ```
>    脚本会自动将该加速镜像永久写入路由器本地配置，后续所有自动更新与界面更新均优先走此通道。

---

### 方式 2：软件中心离线上传安装

1. 从 [Releases 页面](https://github.com/mizb/MerlinLucky/releases/latest) 下载对应硬件架构的离线安装包：
   - 🌟 **华硕天选 AX6000 (MT7986A)、TUF-AX4200Q、GT-AX6000、RT-AX86U Pro 等 64 位机型**：下载 `MerlinLucky_v*.tar.gz` 或 `*_arm64.tar.gz`
   - **老款 32 位机型 (如 RT-AC86U 等)**：下载 `*_armv7.tar.gz`
2. 进入梅林后台 $\to$ **软件中心** $\to$ **离线安装** $\to$ 上传下载的 `.tar.gz` 文件即可完成安装。

---

## 🛡️ 硬件机型支持列表

| 平台架构 | 核心芯片 / 方案 | 代表路由器机型 | 推荐安装包 |
| :--- | :--- | :--- | :--- |
| **ARM64 (aarch64)** | 联发科 MT7986A (Filogic 830) / 博通 BCM4908 / BCM4912 / 高通 IPQ 等 | 华硕天选 AX6000 (TX-AX6000)、TUF-AX4200Q、ROG GT-AX6000、RT-AX86U Pro、RT-AX88U Pro 等 | `MerlinLucky_v*_arm64.tar.gz` (默认) |
| **ARMv7 (32位)** | 博通 BCM4906 / 联发科 MT7622 等 | RT-AC86U、RT-AX88U (早期版本) 等 | `MerlinLucky_v*_armv7.tar.gz` |

---

## 💡 使用技巧：自签与泛域名证书自动同步至路由器

Lucky 内置强大的 ACME 证书管理，可自动申请并续签 Cloudflare / 阿里云 / 腾讯云等泛域名 SSL 证书。您可以在 Lucky 的【证书管理】中添加**更新后触发脚本**，在证书自动续签时自动将证书部署至路由器 Web 管理界面或 AiCloud / WebDAV：

```bash
#!/bin/sh
# 将 Lucky 续签后的证书自动同步至路由器管理后台
cp /koolshare/configs/lucky/ca/CF.crt /tmp/etc/cert.crt
cp /koolshare/configs/lucky/ca/CF.crt /tmp/etc/cert.pem
cp /koolshare/configs/lucky/ca/CF.key /tmp/etc/key.pem
cat /tmp/etc/key.pem /tmp/etc/cert.pem > /tmp/etc/server.pem
chmod 640 /tmp/etc/key.pem
tar -C / -czf /jffs/cert.tgz etc/cert.pem etc/key.pem
service restart_httpd

# 若开启了 AiCloud / WebDAV，同步更新
local aicloud_enable=$(nvram get aicloud_enable)
if [ "${aicloud_enable}" == "1" ]; then
    service restart_webdav
fi
```

---

## 📄 开源与致谢

- 感谢 [gdy666/lucky](https://github.com/gdy666/lucky) 提供的强大 Lucky 内核。
- 感谢 [KoolCenter 社区](https://www.koolcenter.com/) 提供的软件中心固件平台与生态。
- 本项目遵循 GPL-3.0 开源协议发布。
