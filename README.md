# dynv6-updater

Koolshare Merlin 380固件 dynv6 DDNS 软件中心版，支持主域名和多个子域名同时更新，IPv4/IPv6 双栈。

## 依赖

本脚本默认使用 `curl`，如果你没有安装 `curl`，请将脚本中所有 `curl --silent` 替换为 `wget -q -O -`，并将 `-H` 替换为 `--header=`，将 `-X PATCH` 替换为 `--method=PATCH`。

例如：
- `curl --silent -H "Authorization: Bearer ${arToken}"` → `wget -q -O - --header="Authorization: Bearer ${arToken}"`
- `curl --silent -X PATCH -H "Content-Type: application/json"` → `wget -q -O - --method=PATCH --header="Content-Type: application/json"`

或者通过 Entware 安装 `curl`：
```bash
opkg install curl

## 安装

将 `dynv6` 文件夹上传到 `/tmp`，然后执行：

```bash
chmod +x /tmp/dynv6/install.sh
/tmp/dynv6/install.sh
```
## 配置
安装后在 Web 界面（软件中心 → dynv6）中填写：

Token

域名

子域名列表（空格分隔，如 router home nas）

其他选项：

开机自启、启动延时、刷新时间

手动运行
```bash
/koolshare/dynv6/dynv6.sh restart
```
查看状态
Web 界面会显示运行状态。详细日志：

```bash
cat /var/log/dynv6.log
```
## 卸载
```bash
/koolshare/dynv6/uninstall.sh
```
## 许可证
MIT