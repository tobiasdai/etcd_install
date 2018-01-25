# root用户运行

export NODE_NAME=etcd-host1 # 当前部署的机器名称(0,1,2)
export NODE_IP=172.19.39.138 # 当前部署的机器 IP
export NODE_IPS="172.19.39.139 172.19.39.138" # 集群ip
export ETCD_NODES=etcd-host0=https://172.19.39.139:2380,etcd-host1=https://172.19.39.138:2380  # etcd 集群间通信的IP和端口

# 创建 CA 证书和秘钥：使用 CloudFlare 的 PKI 工具集 cfssl 来生成 Certificate Authority (CA) 证书和秘钥文件，CA 是自签名的证书，用来签名后续创建的其它 TLS 证书。
wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
chmod +x cfssl_linux-amd64
mv cfssl_linux-amd64 /usr/local/bin/cfssl
wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
chmod +x cfssljson_linux-amd64
mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
chmod +x cfssl-certinfo_linux-amd64
mv cfssl-certinfo_linux-amd64 /usr/local/bin/cfssl-certinfo

# 创建 CA 配置文件：
cat >  ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "8760h"
      }
    }
  }
}
EOF

#创建 CA 证书签名请求
cat >  ca-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

# 生成 CA 证书和私钥：
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
ca-config.json  ca.csr  ca-csr.json  ca-key.pem  ca.pem

# 创建 etcd 证书签名请求：
cat > etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "${NODE_IP}"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

# 生成 etcd 证书和私钥：
cfssl gencert -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes etcd-csr.json | cfssljson -bare etcd
rm etcd.csr  etcd-csr.json

# 将生成好的etcd.pem和etcd-key.pem以及ca.pem三个文件拷贝到目标主机的/etc/etcd/ssl目录下
mkdir -p /etc/etcd/ssl
cp etcd-key.pem etcd.pem ca.pem /etc/etcd/ssl

# 下载etcd
wget https://github.com/coreos/etcd/releases/download/v3.2.15/etcd-v3.2.15-linux-amd64.tar.gz
tar -xvf etcd-v3.2.15-linux-amd64.tar.gz
mv etcd-v3.2.15-linux-amd64/etcd* /usr/local/bin

# 创建 etcd 的 systemd unit 文件
mkdir -p /var/lib/etcd
cat > etcd.service <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
ExecStart=/usr/local/bin/etcd \\
  --name=${NODE_NAME} \\
  --cert-file=/etc/etcd/ssl/etcd.pem \\
  --key-file=/etc/etcd/ssl/etcd-key.pem \\
  --peer-cert-file=/etc/etcd/ssl/etcd.pem \\
  --peer-key-file=/etc/etcd/ssl/etcd-key.pem \\
  --trusted-ca-file=/etc/etcd/ssl/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ssl/ca.pem \\
  --initial-advertise-peer-urls=https://${NODE_IP}:2380 \\
  --listen-peer-urls=https://${NODE_IP}:2380 \\
  --listen-client-urls=https://${NODE_IP}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://${NODE_IP}:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${ETCD_NODES} \\
  --initial-cluster-state=new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 启动 etcd 服务 
mv etcd.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable etcd
systemctl start etcd

# 查看etcd状态
# systemctl status etcd

# 验证服务
# 部署完 etcd 集群后，在任一 etcd 集群节点上执行如下命令：
# etcdctl \
#   --endpoints=https://172.16.120.151:2379  \
#   --ca-file=/etc/etcd/ssl/ca.pem \
#   --cert-file=/etc/etcd/ssl/etcd.pem \
#   --key-file=/etc/etcd/ssl/etcd-key.pem \
#   cluster-health
