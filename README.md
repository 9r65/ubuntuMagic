#### 

### Ubuntu 下一键翻墙工具

----

此工具用于 **ubuntu 18.04 desktop** 系统翻墙 ，将ubuntu主机当做透明网关配合iptables进行翻墙。这套方案同样可以适用于路由器翻墙，只需将iptables中表修改即可。

此脚本使用一下工具，并在此感谢这些工具背后的开发者们：



* ***[shadowsocks-libev](https://github.com/shadowsocks/shadowsocks-libev)***

* ***[gfwlist2dnsmasq](https://github.com/cokebar/gfwlist2dnsmasq)***

* ***[pdnsd](https://github.com/SAPikachu/pdnsd)***

* ***[dnsmasq](http://www.thekelleys.org.uk/dnsmasq/)***

* ***[supervisor](http://supervisord.org/)***

#### Basic
---

使用:
```shell
sudo bash install.sh
```

涉及到的服务:
```shell
systemctl [option] shadowsocks-libev-redir.service # shadowsocks-redir
systemctl [option] dnsmasq.service # dnsmasq
systemctl [option] supervisor.service # supervisor (守护进程 守护pdnsd)
```

#### 提示
---

* **请在脚本安装完成后手动将服务器配置在 /etc/shadowsocks/config.json , 后重启dnsmasq , pdnsd , shadowsocks三个服务**

* **安装过程中会使用到 /etc/rc.local文件, 为了保险已经在处理前对先脚本进行了备份, 位置在: /etc/rc.local.bak**