#!/usr/bin/env bash
# runs the lab inside WSL and saves each step's terminal text
SRC="/mnt/c/Users/autho/LAB - fsd/lab23"; CAP="$SRC/report/cap"
mkdir -p ~/lab23 && cd ~/lab23
cp "$SRC/create_test_logs.sh" "$SRC/rotate_logs.sh" . && sed -i 's/\r$//' *.sh && chmod +x *.sh
P="abhikhyath@lenovo-LOQ11:~/lab23\$"
shot(){ local n="$1"; shift; { for c in "$@"; do echo "$P $c"; bash -c "$c" 2>&1; echo "[exit code: $?]" | grep -v . ; done; } > "$CAP/$n.txt"; }
shot 01_env "uname -sr" "bash --version | head -1" "systemctl is-active cron" "systemctl status cron --no-pager | head -4"
shot 02_create "./create_test_logs.sh"
shot 03_before "ls -lh --time-style=long-iso logs" "du -sh logs"
ls -lh --time-style=long-iso logs > before.txt
shot 04_dryrun "./rotate_logs.sh --dry-run" "ls logs | wc -l"
shot 05_run "./rotate_logs.sh -d ./logs -a 7 -r 30; echo \"exit code: \$?\""
ls -lh --time-style=long-iso logs > after.txt
shot 06_after "ls -lh --time-style=long-iso logs" "du -sh logs" "gzip -t logs/*.gz && echo 'all archives OK'" "zcat 'logs/payment service.log.gz' | head -2"
shot 07_help "./rotate_logs.sh --help"
mkdir -p empty
shot 08_edge "./rotate_logs.sh -d nope; echo \"exit code: \$?\"" "./rotate_logs.sh -d empty; echo \"exit code: \$?\"" "./rotate_logs.sh; echo \"exit code: \$?\"   # second run" "./rotate_logs.sh -a x; echo \"exit code: \$?\""
rmdir empty
./create_test_logs.sh >/dev/null   # fresh old files for cron to rotate
rm -f rotate_cron.log
( echo "0 2 * * * $HOME/lab23/rotate_logs.sh -d $HOME/lab23/logs -a 7 -r 30 >> $HOME/lab23/rotate_cron.log 2>&1"
  echo "*/2 * * * * $HOME/lab23/rotate_logs.sh -d $HOME/lab23/logs >> $HOME/lab23/rotate_cron.log 2>&1" ) | crontab -
shot 09_crontab "crontab -l" "date"
