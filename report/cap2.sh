CAP="/mnt/c/Users/autho/LAB - fsd/lab23/report/cap"; cd ~/lab23
P='abhikhyath@lenovo-LOQ11:~/lab23$'
shot(){ local n="$1"; shift; { for c in "$@"; do echo "$P $c"; bash -c "$c" 2>&1; done; } > "$CAP/$n.txt"; }
shot 10_cronlog "date" "cat rotate_cron.log" "ls logs"
shot 11_syslog "grep CRON /var/log/syslog | grep rotate_logs | tail -4 | cut -c1-150" "journalctl -t CRON --since '20 min ago' --no-pager | grep rotate_logs | tail -3 | cut -c1-140"
crontab -l | grep -v '^\*/2' | crontab -
shot 12_final "crontab -l" "systemctl is-active cron"
