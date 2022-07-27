#!/bin/bash

# 脚本使用了 ipcalc 请提前安装  ipcalc
# 对百分之多少的ip地址段进行检测
ippsent=20
# 在ping环节，最多留存多少个ip地址
ipmaxtest=40
# 测速使用的url
dHost="speed.cloudflare.com"
download='https://speed.cloudflare.com/__down?bytes=10000000'
# 最终获取的ip地址数量
ipcount=20

function ip2int(){
    A=$(echo $1 | cut -d '.' -f1)
    B=$(echo $1 | cut -d '.' -f2)
    C=$(echo $1 | cut -d '.' -f3)
    D=$(echo $1 | cut -d '.' -f4)
    result=$(($A<<24|$B<<16|$C<<8|$D))
    echo $result
}

function int2ip(){
    A=$((($1 & 0xff000000 ) >>24))
    B=$((($1 & 0x00ff0000)>>16))
    C=$((($1 & 0x0000ff00)>>8))
    D=$(($1 & 0x000000ff))
    result=$A.$B.$C.$D
    echo $result
}

if [[ ! -f iplist.txt ]]; then
    # 切分 cloudflare 公布的大ip段为小ip段，以便更好的随机选择ip地址进行测速 
    if [[ ! -f ips-v4.txt ]]; then
        echo "下载 cloudflare ip段"
        curl -s https://www.cloudflare.com/ips-v4 -o ips-v4.txt
    fi
    echo "切割为每个1022的网段"
    touch iplist.txt
    for ip in `cat ips-v4.txt` ; do
        ipmin=`ipcalc -n $ip |grep HostMin|cut -d: -f 2|cut -d " " -f4`
        ipminint=`ip2int ${ipmin}`
        ips=`ipcalc -n $ip |grep Hosts|cut -d: -f 2|cut -d " " -f2`
        echo "$ip,${ipmin},$ipminint" >> iplist.txt
        while [[ $ips -gt 1022  ]]; do
            ips=$[$ips-1022]
            ipminint=$[$ipminint+1022]
            echo "$ip,`int2ip $ipminint`,$ipminint" >> iplist.txt
        done
    done
fi

if [[ ! -f ip.txt ]]; then
    # 使用 ping 命令获取无丢包的 ip 地址，根据速度排序
    mkdir -p .tmp
    echo "找到`cat iplist.txt|wc -l`个 ip 段，开始随机 ICMP 测速"
    for ipmin in `cat iplist.txt|cut -d, -f3` ;do
        if [[ `expr $((RANDOM %100))` -ge $ippsent  ]]; then
            continue
        fi
        # 提取每个小段的最小ip，随机增加10-1010后作为检测对象
        add=`expr $((RANDOM %1000)) + 10`
        ipnew=$[$ipmin+$add]
        ip=`int2ip ${ipnew}`
        ping -c 6  -i 1 -n -q $ip > .tmp/ping.${ip}.log&
    done
    # 强行等待全部 ping 命令执行完成
    while true
    do
            p=$(ps | grep ping | grep -v "grep" | wc -l)
            if [ $p -ne 0 ]
            then
                sleep 0.2
            else
                echo ICMP 丢包率测试完成
                break
            fi
    done
    # 回收 ping 结果
    cat .tmp/*.log | grep 'statistics\|loss\|avg' | sed 'N;N;s/\n/ /g' | awk -F, '{print $1,$3}' | awk '{print $2,$9,$15}' | awk -F% '{print $1,$2}' | awk -F/ '{print $1,$2}' | awk '{print $2,$4,$1}' | sort -n | awk '{print $3}' | head -n ${ipmaxtest}|grep -v "^$" &> ip.txt
fi 


    echo "选取`cat ip.txt|wc -l`个IP开始下载测速"
    mkdir -p .tmp
    for ip in `cat ip.txt`; do
        curl --resolve ${dHost}:443:$ip -o /dev/null --connect-timeout 5 --max-time 10 ${download} &> .tmp/curl.$ip.log&
    done

    # 等待测速结果
    while true
    do
            p=$(ps | grep curl | grep -v "grep" | wc -l)
            if [ $p -ne 0 ]
            then
                sleep 0.2
            else
                echo CURL并发下载测速完成
                break
            fi
    done

    # 回收测速结果，按照速度排序，选出最快的 ipcount 个 写入 result.txt
    rm -rf speed.txt
    touch speed.txt
    for ip in `cat ip.txt`; do
        avgspeed=`cat .tmp/curl.$ip.log | tr '\r' '\n'|grep -v curl| awk '{print $NF}'| awk 'END {print}'`
         echo ${avgspeed},${ip} >> speed.txt
    done
    cat speed.txt|sort -r|head -n ${ipcount}|grep -v "^$"|cut -d, -f2 &> result.txt
    
    # 清理所有内容，下次从头开始！
    rm -rf .tmp ips-v4.txt ip.txt speed.txt
    
    echo "找到`cat result.txt|wc -l`个可用ip："
    cat result.txt
