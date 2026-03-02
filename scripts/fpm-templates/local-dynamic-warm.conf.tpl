[{{POOL_NAME}}]
user = {{FPM_USER}}
group = {{FPM_GROUP}}

listen = {{SOCK_PATH}}
; listen.owner = {{FPM_USER}}
; listen.group = {{FPM_GROUP}}
listen.mode = 0666

; Warmer than ondemand (lower cold-start latency)
pm = dynamic
pm.max_children = 20
pm.start_servers = 2
pm.min_spare_servers = 2
pm.max_spare_servers = 6
pm.max_requests = 300

catch_workers_output = yes

php_admin_flag[log_errors] = on
php_admin_value[error_log] = {{ERROR_LOG}}

access.log = {{ACCESS_LOG}}
access.format = "%R - %u %t \"%m %r\" %s %f %{mili}dms %{kilo}MkB %C%%"

clear_env = no
security.limit_extensions = .php .phar