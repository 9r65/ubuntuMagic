#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

shell_path=$(pwd)
download_path="/tmp/download/"
# shadowsocks conf
shadowsocks_config_path="/etc/shadowsocks/"
shadowsocks_libev_url="https://github.com/shadowsocks/shadowsocks-libev.git"
shadowsocks_file_path="/usr/local/shadowsocks"
# pdnsd conf
pdnsd_url="https://github.com/SAPikachu/pdnsd.git"
pdnsd_file_path="/usr/local/pdnsd/"
pdnsd_supervisor_conf="/etc/supervisor/conf.d/pdnsd.conf"
pdnsd_port=5354
# gfwlist2 conf
gfwlist2dnsmasq_url="https://github.com/cokebar/gfwlist2dnsmasq.git"
gfwlist2dnsmasq_path="/usr/local/gfwshell"

echo_red() {
    echo -e "\e[0;31m$1\e[0m"
}
echo_green() {
    echo -e "\e[0;32m$1\e[0m"
}
echo_yellow() {
    echo -e "\e[0;33m$1\e[0m"
}

# check user as root
if [ $(id -u) != "0" ];then
    echo_red "[error :] You must be root to run this script !"
    exit 1
fi

init_package() {
    mkdir ${download_path}
    echo_yellow "now we need to install some tools..."
    apt-get udpate -y -q
    apt-get autoremove -y
    apt-get --no-install-recommends install -y git curl supervisor ipset net-tools wget axel dnsmasq gettext build-essential autoconf libtool libpcre3-dev asciidoc xmlto libev-dev libc-ares-dev automake libmbedtls-dev libsodium-dev
}

destruct() {
    # open supervisor
    systemctl enable supervisor.service
    # 关闭系统dns
    systemctl stop systemd-resolved.service
    systemctl disable systemd-resolved.service
    systemctl enable rc-local.service && systemctl restart rc-local.service
    # 开启dnsmasq
    systemctl start dnsmasq
    # 开启shadowsocks
    systemctl enable shadowsocks-libev-redir.service && systemctl start shadowsocks-libev-redir.service
    systemctl restart supervisor.service
    # 运行rc.local 一次
    bash /etc/rc.local
}


conf_iptables() {
    # 创建开机脚本
    if [ ! -f /etc/rc.local ];then
        touch /etc/rc.local
        echo "#!/bin/sh -e" > /etc/rc.local
    else
        cp /etc/rc.local /etc/rc.local.bak
        echo "#!/bin/sh -e" > /etc/rc.local
    fi

    echo "

ipset create gfw iphash -exist
iptables -t nat -A OUTPUT -p tcp -d 8.8.8.8 -j REDIRECT --to-ports 8989
iptables -t nat -A OUTPUT -p tcp -d 8.8.4.4 -j REDIRECT --to-ports 8989
iptables -t nat -A OUTPUT -p tcp -d 208.67.222.222 -j REDIRECT --to-ports 8989
iptables -t nat -A OUTPUT -p tcp -d 208.67.220.220 -j REDIRECT --to-ports 8989
iptables -t nat -A OUTPUT -p tcp -m set --match-set gfw dst -j REDIRECT --to-ports 8989

exit 0
" >> /etc/rc.local

    chmod +x /etc/rc.local

    if [ -f /etc/resolv.conf ];then
        rm -rf /etc/resolv.conf  
    fi

    touch /etc/resolv.conf
    echo "nameserver 127.0.0.1" > /etc/resolv.conf
    # 保护resolv文件
    chattr +i /etc/resolv.conf

    echo_green "[success :] create rc.local script success"
}

# 配置rt_tables
conf_rclocal() {
    if [ ! -f /etc/iproute2/rt_tables ];then
        echo_red "[error :] can't find rt_tables file"
        exit 1
    fi
    echo "
10  gfw" >> /etc/iproute2/rt_tables

    if [ ! -f /etc/systemd/system/rc-local.service ];then
        cp /lib/systemd/system/rc-local.service /etc/systemd/system/rc-local.service
        echo "

[Install]
WantedBy=multi-user.target" >> /etc/systemd/system/rc-local.service
    systemctl daemon-reload
    fi
}

# 安装gfwlist2dnsmasq 生成cross名单
install_gfwlist() {
    echo_yellow "beging install gfwlist2dnsmasq ..."
    cd ${download_path}
    git clone ${gfwlist2dnsmasq_url} gfw && cd gfw
    if [ ! -f gfwlist2dnsmasq.sh ];then
        echo_red "[error :] install gfwlist2dnsmasq fail ! this pack has some errors..."
        exit 1
    fi

    echo_green "[success :] install gfwlist2dnsmasq success"
    echo_yellow "create conf file to /etc/dnsmasq.d/"
    ./gfwlist2dnsmasq.sh -p ${pdnsd_port} -s gfw -o /etc/dnsmasq.d/gfw.conf
}


# 安装shadowsocks
install_shadowsocks(){

    echo_green "starting: install shadowsocks-libev..."

    cd ${download_path}

    if [ ! -e ${download_path}"ss" ];then 
        echo_yellow "starting download shadowsocks..."
        git clone ${shadowsocks_libev_url} ss
        cd ss && git submodule update --init --recursive
    else
        cd ss
    fi

    if [[ ! -f configure && ! -f autogen.sh ]];then
        echo_red "[error :] Install Shadowsocks-libev error , can't find autogen.sh Or configure"
        exit 1
    fi

    if [ -f autogen.sh ];then
        ./autogen.sh
    fi

    ./configure --prefix=$shadowsocks_file_path && make && make install

    if [ $? -eq 0 ]; then
        # create shadowsocks conf
        mkdir ${shadowsocks_config_path} && touch ${shadowsocks_config_path}"config.json"

        echo_green "[success :] Install shadowsocsk-libev Success !"
        add_ss_service redir
        add_ss_service locals
        return 1
    else
        echo_red "[error :] Install shadowsocks-libev Error"
        exit 1
    fi
}


# 增加systemctl service
add_ss_service() {
    service_name=$1
    service_exec=""
    service_file="shadowsocks-libev-${service_name}.service"
    case $service_name in
        redir) 
        service_exec="${shadowsocks_file_path}/bin/ss-redir -c /etc/shadowsocks/config.json"
        ;;
        locals)
        service_exec="${shadowsocks_file_path}/bin/ss-local -c /etc/shadowsocks/config.json"
        ;;
    esac
    cat>$service_file<<EOF
[Unit]
Description=Shadowsocks-Libev-${service_name}
After=network.target rc-local.service


[Service]
Type=simple
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ExecStart=${service_exec}

[Install]
WantedBy=multi-user.target
EOF
    chown root:root shadowsocks-libev-*
    if [ -e /usr/lib/systemd/user ];then
        mv $service_file /usr/lib/systemd/user/
        ln -s /usr/lib/systemd/user/${service_file} /etc/systemd/system/
    else
        mv $service_file /etc/systemd/system/
    fi
}

# 配置dnsmasq
config_dnsmasq() {
    echo_yellow "开始配置 dnsmasq ..."
    if [ ! -e /etc/dnsmasq.d ];then 
        mkdir /etc/dnsmasq.d
    fi

    cp ${shell_path}/server.conf /etc/dnsmasq.d/

    if [ ! -f /etc/dnsmasq.conf ];then
        touch /etc/dnsmasq.conf
    fi
    echo "
#check dnssec resource record
dnssec
#this enables dnsmasq send queries to all available dns server and the fastest answer will be used
all-servers
#disable resolv file
no-resolv
# include user conf
conf-dir=/etc/dnsmasq.d" > /etc/dnsmasq.conf

    
}


# 安装pdnsd
install_pdnsd(){
    cd ${download_path}
    echo_green "starting install pdnsd..."
    git clone ${pdnsd_url} pdnsd && cd pdnsd

    if [ ! -f configure ];then
        echo_red "[error :] install pdnds error, can't find configure "
    fi
    ./configure --prefix=${pdnsd_file_path} && make && make install

    if [ $? -eq 0 ]; then
        # create shadowsocks conf
        cp ${shell_path}/pdnsd.conf /etc/pdnsd.conf && chown root:root /etc/pdnsd.conf
        # use supervisor start pdnsd process
        if [ -e /etc/supervisor/conf.d ];then
            touch ${pdnsd_supervisor_conf}
            echo "[program:pdndsd]
command=${pdnsd_file_path}sbin/pdnsd -c /etc/pdnsd.conf
user=root
autostart=true
autorestart=true" >> ${pdnsd_supervisor_conf}
        else
            echo_red "[error:] can't find supervisor normal conf file !"
            exit 1
        fi


        echo_green "[success :] install pdnsd success!"
        return 1
    else
        echo_red "[error :] Install pdnsd Error"
        exit 1
    fi
}


# 脚本开始字符
hello_world(){
    clear
    echo "#############################################################"
    echo "#                                                           "
    echo "# Ubuntu 一键翻墙                                            "
    echo "# [目前该脚本至适用于ubuntu 18.04 及以上]                       "
    echo "#                                                           "
    echo "# Author: oygza <oygza.zh@gmail.com>                        "
    echo "#                                                           "
    echo "# Update time : 2018-11-08                                  "
    echo "#                                                           "
    echo "#############################################################"
    echo
    echo "请按任意键开始...或者使用 Ctrl+C 取消"
    OLDCONFIG=`stty -g`
    stty -icanon -echo min 1 time 0
    dd count=1 2>/dev/null
    stty ${OLDCONFIG}
}




tips() {

    echo "#############################################################"
    echo "#  安装完成!                                                 "
    echo "#  以下为配置文件位置:                                         "
    echo "#  [dnsmasq]                                                "
    echo "#    /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf                "
    echo "#  [shadowsocks]                                            "
    echo "#    /etc/shadowsocks/config.json                           "
    echo "#  [pdnsd]                                                  "
    echo "#    /etc/pdnsd.conf                                        "
    echo "#                                                           "
    echo "#  !!! 提示 !!!                                              " 
    echo "#  1. 将自己的服务器配置在 /etc/shadowsocks/config.json         "
    echo "#  2. 最好重启一下系统                                         "
    echo "#  3. 如果dnsmasq等工具启动失败,请先排查SELINUX是否关闭           "
    echo "#                                                           "
    echo "#############################################################"

}

hello_world
init_package
install_shadowsocks
install_pdnsd
config_dnsmasq
install_gfwlist
conf_rclocal
conf_iptables
destruct
tips


echo
echo
echo
echo_green " Congratulations ! we done! "
echo_green " Bye ~"
exit 1
