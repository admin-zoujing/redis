#!/bin/bash
#安装centos7.4安装redis4.0.12主从脚本
#官网地址 https://redis.io/   图形客户端下载地址：https://redisdesktop.com/download

#1、------------------------------RHEL7主服务器（master)-------------------------------
sourceinstall=/usr/local/src/redis
chmod -R 777 /usr/local/src/redis
#时间时区同步，修改主机名
ntpdate  ntp1.aliyun.com
hwclock --systohc
echo "*/30 * * * * root ntpdate -s  ntp1.aliyun.com" >> /etc/crontab

sed -i 's|SELINUX=.*|SELINUX=disabled|' /etc/selinux/config
sed -i 's|SELINUXTYPE=.*|#SELINUXTYPE=targeted|' /etc/selinux/config
sed -i 's|SELINUX=.*|SELINUX=disabled|' /etc/sysconfig/selinux 
sed -i 's|SELINUXTYPE=.*|#SELINUXTYPE=targeted|' /etc/sysconfig/selinux 
setenforce 0 && systemctl stop firewalld && systemctl disable firewalld

rm -rf /var/run/yum.pid 
rm -rf /var/run/yum.pid

#查看系统版本号
cat /etc/redhat-release 
yum -y install gcc gcc-c++ openssl-devel tcl cmake
#cd /usr/local/src/redis/rpm
#rpm -ivh /usr/local/src/redis/rpm/*.rpm --force --nodeps
#wget http://download.redis.io/releases/redis-4.0.12.tar.gz
#chmod 777 redis-4.0.12.tar.gz

groupadd redis
useradd -g redis -s /sbin/nologin redis
mkdir -pv /usr/local/redis
cd $sourceinstall
tar -zxvf redis-4.0.12.tar.gz -C /usr/local/redis
cd /usr/local/redis/redis-4.0.12
make PREFIX=/usr/local/redis install
make test
cp /usr/local/redis/redis-4.0.12/redis.conf /usr/local/redis
mkdir -pv /usr/local/redis/{logs,backup}

sed -i 's|bind 127.0.0.1|#bind 127.0.0.1|' /usr/local/redis/redis.conf
sed -i 's|protected-mode yes|protected-mode no|' /usr/local/redis/redis.conf
sed -i 's|dir ./|dir /usr/local/redis/backup|' /usr/local/redis/redis.conf
sed -i 's|daemonize no|daemonize yes|' /usr/local/redis/redis.conf
sed -i 's|pidfile /var/run/redis_6379.pid|pidfile /usr/local/redis/logs/redis_6379.pid|' /usr/local/redis/redis.conf
sed -i 's|logfile ""|logfile "/usr/local/redis/logs/redis.log"|' /usr/local/redis/redis.conf
sed -i 's|# requirepass foobared|requirepass sanxin|' /usr/local/redis/redis.conf
chown -Rf redis:redis /usr/local/redis

#二进制程序：
echo 'export PATH=/usr/local/redis/bin:$PATH' > /etc/profile.d/redis.sh 
source /etc/profile.d/redis.sh
#头文件输出给系统：
#ln -sv /usr/local/redis/include /usr/include/redis
#库文件输出
#echo '/usr/local/redis/lib' > /etc/ld.so.conf.d/redis.conf
#让系统重新生成库文件路径缓存
#ldconfig
#导出man文件：
#echo 'MANDATORY_MANPATH                       /usr/local/redis/man' >> /etc/man_db.conf
#source /etc/profile.d/redis.sh 
#sleep 5
#source /etc/profile.d/redis.sh 

#开机启动脚本
#/usr/local/redis/bin/redis-server /usr/local/redis/redis.conf
#echo '/usr/local/redis/bin/redis-server /usr/local/redis/redis.conf' >> /etc/rc.d/rc.local
#chmod +x /etc/rc.d/rc.local

cat > /usr/lib/systemd/system/redis.service <<EOF
[Unit]
Description=Redis persistent key-value database
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
User=redis
Group=redis
Type=notify
LimitNOFILE=10240
PIDFile=/usr/local/redis/logs/redis_6379.pid
ExecStart=/usr/local/redis/bin/redis-server /usr/local/redis/redis.conf --supervised systemd 
#RuntimeDirectory=redis
#RuntimeDirectoryMode=0755      
ExecReload=/bin/kill -USR2 \$MAINPID
ExecStop=/bin/kill -SIGINT \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
chmod 755 /usr/lib/systemd/system/redis.service
systemctl daemon-reload 
systemctl enable redis.service

#优化了系统参数
cat >> /etc/sysctl.conf <<EOF
fs.file-max = 100000
vm.overcommit_memory = 1
net.core.somaxconn = 1024
EOF
sysctl -p

echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' >> /etc/rc.d/rc.local
chmod +x /etc/rc.d/rc.local
echo never > /sys/kernel/mm/transparent_hugepage/enabled
systemctl restart redis.service 

#rdb备份脚本
mkdir -pv /home/redis_backup
cat > /usr/local/redis/backup/init-redisbackup.sh <<EOF
#!/bin/bash
PATH=/usr/local/redis/bin:\$PATH
redis-cli -a sanxin SAVE
time=\$(date +"%Y%m%d")
cp /usr/local/redis/backup/dump.rdb /home/redis_backup/\$time.rdb
 
echo "done!"
before=\$(date -d '2 day ago' +%Y%m%d)
rm -rf /home/redis_backup/\$before*
EOF
chmod 744 /usr/local/redis/backup/init-redisbackup.sh
echo "30 1 * * * root /usr/local/redis/backup/init-redisbackup.sh >/dev/null 2>&1" >> /etc/crontab

rm -rf /usr/local/src/redis
#sshpass -p Root123456 scp /home/redis_backup/* root@192.168.1.101:/home/redis_backup
#客户端连接测试：redis-cli (-h 192.168.8.20 -a sanxin)

#-------------------------------安装主从时修改主配置文件-------------------------------
#systemctl stop redis-server.service && netstat -lanput
#cp /usr/local/redis/redis.conf{,.backup}
#sed -i 's|bind 127.0.0.1|bind 192.168.8.20|' /usr/local/redis/redis.conf
#systemctl daemon-reload && systemctl start redis-server.service && netstat -lanput



#1、------------------------------RHEL7从服务器（slave)-------------------------------

#sed -i 's|daemonize no|daemonize yes|' /usr/local/redis/redis.conf
#sed -i 's|logfile ""|logfile "/usr/local/redis/logs/redis.log"|' /usr/local/redis/redis.conf
#sed -i 's|# requirepass foobared|requirepass sanxin|' /usr/local/redis/redis.conf

#客户端连接测试：redis-cli (-h 192.168.8.21)

#-------------------------------安装主从时修改从配置文件-------------------------------
#systemctl stop redis-server.service && netstat -lanput
#cp /usr/local/redis/redis.conf{,.backup}
#sed -i 's|bind 127.0.0.1|bind 192.168.8.21|' /usr/local/redis/redis.conf
#sed -i '/^# slaveof <masterip> <masterport>/a\slaveof 192.168.8.20 6379' /usr/local/redis/redis.conf
#sed -i '/^# masterauth <master-password> /a\masterauth sanxin' /usr/local/redis/redis.conf
#systemctl daemon-reload && systemctl start redis-server.service && netstat -lanput


########------------------------远程连接设置--------------------------------#########
#systemctl stop redis-server.service && netstat -lanput
#sed -i 's|bind 127.0.0.1|#bind 127.0.0.1|' /usr/local/redis/redis.conf
#sed -i 's|protected-mode yes|protected-mode no|' /usr/local/redis/redis.conf
#systemctl daemon-reload && systemctl start redis-server.service && netstat -lanput


#######------------------------从服务器开启AOF备份-------------------------###########
#systemctl stop redis-server.service && netstat -lanput
#sed -i 's|appendonly no|appendonly yes|' /usr/local/redis/redis.conf

#aof与dump备份不同
#aof文件备份与dump文件备份不同。dump文件的编码格式和存储格式与数据库一致，而且dump文件中备份的是数据库的当前快照，意思就是，不管数据之前什么样，只要BGSAVE了，dump文件就会刷新成当前数据库数据。
#当redis重启时，会按照以下优先级进行启动：
#    如果只配置AOF,重启时加载AOF文件恢复数据；
#    如果同时 配置了RBD和AOF,启动是只加载AOF文件恢复数据;
#    如果只配置RBD,启动时将加载dump文件恢复数据。
#注意：只要配置了aof，但是没有aof文件，这个时候启动的数据库会是空的
#在linux环境运行Redis时，如果系统的内存比较小，这个时候自动备份会有可能失败，需要修改系统的vm.overcommit_memory 参数，它有三个选值，是linux系统的内存分配策略：
#    0， 表示内核将检查是否有足够的可用内存供应用进程使用；如果有足够的可用内存，内存申请允许；否则，内存申请失败，并把错误返回给应用进程。
#    1， 表示内核允许分配所有的物理内存，而不管当前的内存状态如何。
#    2， 表示内核允许分配超过所有物理内存和交换空间总和的内存
#Redis官方的说明是，建议将vm.overcommit_memory的值修改为1，可以用下面几种方式进行修改：
#    （1）编辑/etc/sysctl.conf ，改vm.overcommit_memory=1，然后sysctl -p 使配置文件生效
#    （2）sysctl vm.overcommit_memory=1
#    （3）echo 1 > /proc/sys/vm/overcommit_memory


#1.启动redis进入redis目录
#redis-cli
#2.数据备份
#redis 127.0.0.1:6379> auth "yourpassword"  
#redis 127.0.0.1:6379> SAVE
#3.恢复数据
##获取备份目录
#redis 127.0.0.1:6379> CONFIG GET dir
#1) "dir"
#2) "/usr/local/redis/backup"　　　
#以上命令 CONFIG GET dir 输出的 redis 备份目录为 /usr/local/redis/backup。
##停止redis服务
##拷贝备份文件到 /usr/local/redis/backup目录下
##重新启动redis服务
