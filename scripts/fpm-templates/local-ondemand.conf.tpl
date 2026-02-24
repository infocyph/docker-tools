[{{POOL_NAME}}]
user = {{FPM_USER}}
group = {{FPM_GROUP}}

listen = {{SOCK_PATH}}
listen.owner = {{FPM_USER}}
listen.group = {{FPM_GROUP}}
listen.mode = 0660

; Local multi-domain: keep idle cost near-zero
pm = ondemand
pm.max_children = 10
pm.process_idle_timeout = 20s
pm.max_requests = 300

; Observability / debugging
catch_workers_output = yes
; decorate_workers_output = no

; Per-domain logs (Filebeat will read as plain text)
php_admin_flag[log_errors] = on
php_admin_value[error_log] = {{ERROR_LOG}}

; Optional but useful
access.log = {{ACCESS_LOG}}
access.format = "%R - %u %t \"%m %r\" %s %f %{mili}dms %{kilo}MkB %C%%"

; Safety defaults for local
clear_env = no
security.limit_extensions = .php .phar