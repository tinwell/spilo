#!/bin/bash

PATH=$PATH:/usr/lib/postgresql/${PGVERSION}/bin


function patch_governor
{
#!/bin/bash
cat << EOF |patch governor/helpers/postgresql.py
diff --git a/helpers/postgresql.py b/helpers/postgresql.py
index b6c52c1..4d3bfb1 100644
--- a/helpers/postgresql.py
+++ b/helpers/postgresql.py
@@ -146,6 +146,8 @@ class Postgresql:
         f = open("%s/pg_hba.conf" % self.data_dir, "a")
         f.write("host replication %(username)s %(network)s md5" %
                 {"username": self.replication["username"], "network": self.replication["network"]})
+        # allow TCP connections from the host's own address
+        f.write("\nhost postgres postgres %(network)s/32 trust\n" % {"network": self.host})
         f.close()
 
     def write_recovery_conf(self, leader_hash):
EOF
}

function write_postgres_yaml
{
  local_address=$(cat /etc/hosts |grep ${HOSTNAME}|cut -f1)
  cat >> postgres.yml <<__EOF__
loop_wait: 10
etcd:
  scope: $SCOPE
  ttl: 30
  host: 127.0.0.1:8080
postgresql:
  name: postgresql_${HOSTNAME}
  listen: ${local_address}:5432
  data_dir: $PGDATA/data
  replication:
    username: standby
    password: standby
    network: 0.0.0.0/0
  parameters:
    archive_mode: "on"
    wal_level: hot_standby
    archive_command: /bin/true
    max_wal_senders: 5
    wal_keep_segments: 8
    archive_timeout: 1800s
    max_replication_slots: 5
__EOF__
}

# get governor code
git clone https://github.com/compose/governor.git

patch_governor

write_postgres_yaml

# start etcd proxy
# for the -proxy on TDB the url of the etcd cluster
if [ "$DEBUG" -eq 1 ]
then
  exec /bin/bash
fi
etcd -name "proxy-$SCOPE" -proxy on -bind-addr 127.0.0.1:8080 --data-dir=data/etcd -initial-cluster $ETCD_CLUSTER &

exec governor/governor.py "/home/postgres/postgres.yml"


