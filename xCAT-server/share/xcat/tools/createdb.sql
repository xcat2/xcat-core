create db xcatdb on /var/lib/db2/data;

update dbm cfg using dft_mon_bufpool on dft_mon_lock on dft_mon_sort on dft_mon_stmt on dft_mon_table on dft_mon_uow on health_mon on;
update dbm cfg using java_heap_sz 4096 num_initagents 2 max_querydegree any intra_parallel yes;
update dbm cfg using MON_HEAP_SZ 256;
update dbm cfg using MAXAGENTS 500;
update dbm cfg using NUM_POOLAGENTS 250;
update dbm cfg using FCM_NUM_BUFFERS 4096;

connect to xcatdb;

CREATE BUFFERPOOL BP16K SIZE 2000 PAGESIZE 16K;
Create tablespace xcattbs16k pagesize 16k managed by system using('/var/lib/db2/ts16')  BUFFERPOOL BP16K;
CREATE BUFFERPOOL BP32K SIZE 2000 PAGESIZE 32K;
Create tablespace xcattbs32k pagesize 32k managed by system using('/var/lib/db2/ts32')  BUFFERPOOL BP32K;
update db cfg for xcatdb using LOCKLIST 2087;
update db cfg for xcatdb using APPGROUP_MEM_SZ 40000;
update db cfg for xcatdb using GROUPHEAP_RATIO 80;
update db cfg for xcatdb using APP_CTL_HEAP_SZ 512;
update db cfg for xcatdb using MAXLOCKS 100;
update db cfg for xcatdb using NUM_IOSERVERS 4;
update db cfg for xcatdb using SOFTMAX 120;
update db cfg for xcatdb using DBHEAP 2500;
update db cfg for xcatdb using STMTHEAP 4096;
update db cfg for xcatdb using APPLHEAPSZ 2500;
