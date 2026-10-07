# Lab #23 – Log Rotation & Compression with Bash and cron

Files in this folder:
| File | Purpose |
|---|---|
| `create_test_logs.sh` | Builds a `logs/` folder with fresh logs, old logs, a name with a space, and old/new archives |
| `rotate_logs.sh` | Gzips `.log` files older than 7 days and deletes `.gz` files older than 30 days |
| `LAB23_REPORT.md` | This document: setup, runs, cron, tests, logrotate, screenshots, report, viva |

Every line of both scripts is explained in comments inside the scripts.

---

## 1. Environment setup

### Windows (WSL Ubuntu)
```bash
# In PowerShell (admin), only if WSL is not installed yet:
wsl --install -d Ubuntu
```
Then inside Ubuntu:
```bash
sudo apt update
sudo apt install -y cron rsyslog gzip findutils   # cron daemon, syslog daemon (WSL has none by default)
sudo service rsyslog start                        # needed so cron writes to /var/log/syslog
sudo service cron start                           # WSL has no systemd by default -> use "service"
service cron status                               # expect: "cron is running"
```
WSL does not start services automatically. Option A: run `sudo service cron start` every time you open WSL. Option B (permanent), create `/etc/wsl.conf`:
```ini
[boot]
command = "service rsyslog start; service cron start"
```
then in PowerShell run `wsl --shutdown` and reopen Ubuntu.
(If your WSL has systemd enabled: `sudo systemctl enable --now cron`.)

**Work in the Linux file system, not `/mnt/c`.** Windows files have CRLF line endings and odd permissions there:
```bash
mkdir -p ~/lab23 && cd ~/lab23
cp "/mnt/c/Users/autho/LAB - fsd/lab23/"*.sh .
sed -i 's/\r$//' *.sh        # remove Windows CR characters (otherwise: "bad interpreter: /bin/bash^M")
chmod +x *.sh                # make the scripts executable
```

### Linux (Ubuntu/Debian)
`sudo apt install -y cron && sudo systemctl enable --now cron`. On RHEL/Fedora the package is `cronie` and the service is `crond`.

### macOS
cron is already installed. `touch -d` and `ls --time-style` are GNU options, so install GNU tools with `brew install coreutils findutils` and use `gtouch`, `gls`, `gfind` (or put `$(brew --prefix)/opt/coreutils/libexec/gnubin` first in your PATH). Give `/usr/sbin/cron` **Full Disk Access** under System Settings → Privacy & Security. To see cron activity, run `log show --predicate 'process == "cron"' --last 10m`.

---

## 2. create_test_logs.sh – the test data
```bash
./create_test_logs.sh            # creates ./logs
./create_test_logs.sh /tmp/x     # or any other folder
```
| File | Age | Expected after rotation |
|---|---|---|
| app.log | 0 d | kept as-is |
| error.log | 2 d | kept |
| access.log | 5 d | kept |
| app-old.log | 10 d | → app-old.log.gz |
| `payment service.log` (space) | 12 d | → `payment service.log.gz` |
| debug.log | 20 d | → debug.log.gz |
| notes.txt | 15 d | kept (not `.log`) |
| archive-recent.log.gz | 15 d | kept (< 30 d) |
| archive-ancient.log.gz | 45 d | **deleted** (> 30 d) |

Key commands: `touch -d "10 days ago" file` sets the modification time (mtime) back 10 days, and `head -c N < <(yes "...")` creates a file of exactly N bytes.

---

## 3. rotate_logs.sh – the main script

Features: `set -euo pipefail`, settings from options or env vars (`LOG_DIR`, `DAYS`, `RETENTION_DAYS`), checks that the folder exists and is writable, checks that the numbers are valid, `find -print0` with `read -d ''` so names with spaces are safe, `gzip -9`, deletion of archives older than the retention period, timestamped output, `--dry-run`, `--help`, and exit codes **0** ok / **1** usage error / **2** folder missing / **3** compression failed.

```bash
./rotate_logs.sh --help
./rotate_logs.sh -d ./logs -a 7 -r 30          # options
LOG_DIR=./logs DAYS=7 RETENTION_DAYS=30 ./rotate_logs.sh   # env vars
./rotate_logs.sh --dry-run                       # preview only
```

Design decisions (useful in the viva):
1. **Delete first, then compress.** A newly made archive keeps the old log's age (`touch -r`), so this order stops the script from deleting an archive it just created.
2. **`-maxdepth 1`.** Only the given folder is processed, not subfolders.
3. **No overwrite.** If `app.log.gz` already exists, the new archive gets a timestamp: `app-20261006214746.log.gz`.
4. **Safe failure.** If gzip fails, the half-written `.gz` is removed and the original log is kept.
5. `x=$((x+1))` is used instead of `((x++))`. Under `set -e`, `((x++))` with x=0 returns status 1 and would end the script.

---

## 4. Manual run with before/after listings

```bash
cd ~/lab23
./create_test_logs.sh > /dev/null
ls -lh --time-style=long-iso logs | tee before.txt
./rotate_logs.sh --dry-run
./rotate_logs.sh -d ./logs ; echo "exit code: $?"
ls -lh --time-style=long-iso logs | tee after.txt
diff before.txt after.txt
```

**Real output from a test run (dates will match the day you run it):**

BEFORE (`total 542K`):
```
-rw-r--r-- 1 user user  80K 2026-10-01 21:47 access.log
-rw-r--r-- 1 user user 120K 2026-09-26 21:47 app-old.log
-rw-r--r-- 1 user user  50K 2026-10-06 21:47 app.log
-rw-r--r-- 1 user user  226 2026-08-22 21:47 archive-ancient.log.gz
-rw-r--r-- 1 user user  225 2026-09-21 21:47 archive-recent.log.gz
-rw-r--r-- 1 user user 200K 2026-09-16 21:47 debug.log
-rw-r--r-- 1 user user  20K 2026-10-04 21:47 error.log
-rw-r--r-- 1 user user 5.0K 2026-09-21 21:47 notes.txt
-rw-r--r-- 1 user user  60K 2026-09-24 21:47 payment service.log
```
SCRIPT OUTPUT:
```
[2026-10-06 21:47:46] START dir=./logs age>7d retention>30d dry_run=0
[2026-10-06 21:47:46] DELETE   ./logs/archive-ancient.log.gz
[2026-10-06 21:47:46] COMPRESS ./logs/app-old.log -> ./logs/app-old.log.gz
[2026-10-06 21:47:46] COMPRESS ./logs/debug.log -> ./logs/debug.log.gz
[2026-10-06 21:47:46] COMPRESS ./logs/payment service.log -> ./logs/payment service.log.gz
[2026-10-06 21:47:46] DONE compressed=3 deleted=1 failed=0
exit code: 0
```
AFTER (`total 167K`):
```
-rw-r--r-- 1 user user  80K 2026-10-01 21:47 access.log
-rw-r--r-- 1 user user  531 2026-09-26 21:47 app-old.log.gz
-rw-r--r-- 1 user user  50K 2026-10-06 21:47 app.log
-rw-r--r-- 1 user user  225 2026-09-21 21:47 archive-recent.log.gz
-rw-r--r-- 1 user user  807 2026-09-16 21:47 debug.log.gz
-rw-r--r-- 1 user user  20K 2026-10-04 21:47 error.log
-rw-r--r-- 1 user user 5.0K 2026-09-21 21:47 notes.txt
-rw-r--r-- 1 user user  330 2026-09-24 21:47 payment service.log.gz
```
The test logs repeat the same line, so they compress to under 1 KB. Real logs usually shrink by 80–95%.

Check an archive: `zcat "logs/payment service.log.gz" | head -3` and `gzip -t logs/*.gz && echo OK`.

---

## 5. Scheduling with cron

```bash
crontab -e          # opens your user crontab (choose nano if asked)
```
**Production entry (every day at 02:00):**
```cron
0 2 * * * /home/<user>/lab23/rotate_logs.sh -d /home/<user>/lab23/logs -a 7 -r 30 >> /home/<user>/lab23/rotate_cron.log 2>&1
```
**Temporary test entry (every 2 minutes):**
```cron
*/2 * * * * /home/<user>/lab23/rotate_logs.sh -d /home/<user>/lab23/logs >> /home/<user>/lab23/rotate_cron.log 2>&1
```
Rules: use **absolute paths** (cron starts in `$HOME` with a minimal PATH such as `/usr/bin:/bin`), make sure the crontab ends with a newline, and replace `<user>` with the output of `whoami`.

Install without an editor (good for screenshots):
```bash
( crontab -l 2>/dev/null; echo "*/2 * * * * $HOME/lab23/rotate_logs.sh -d $HOME/lab23/logs >> $HOME/lab23/rotate_cron.log 2>&1" ) | crontab -
```

**Prove that cron runs it:**
```bash
./create_test_logs.sh > /dev/null       # fresh old files for cron to rotate
crontab -l                              # shows the entry
date                                    # wait until the next even minute
tail -f ~/lab23/rotate_cron.log         # new START/COMPRESS/DONE lines appear (Ctrl+C to stop)
grep CRON /var/log/syslog | tail        # Ubuntu/WSL: "(user) CMD (/home/user/lab23/rotate_logs.sh ...)"
journalctl -u cron --since "10 min ago" # systemd Linux
ls -lh logs                             # old .log files are now .gz
```
Expected syslog line:
```
Oct  6 22:02:01 PC CRON[1234]: (user) CMD (/home/user/lab23/rotate_logs.sh -d /home/user/lab23/logs >> /home/user/lab23/rotate_cron.log 2>&1)
```
**Afterwards, remove the 2-minute entry** with `crontab -e` (delete the line) and leave only the 02:00 entry. Check again with `crontab -l`.

Troubleshooting: if nothing happens, run `service cron status` (WSL: is it running?) and check the script's permissions and line endings. If you see `No MTA installed, discarding output`, the `>> ... 2>&1` redirect is missing. WSL only runs cron jobs while the WSL VM is running.

---

## 6. Edge case tests

| # | Test | Command | Expected result | Exit |
|---|---|---|---|---|
| 1 | Empty folder | `mkdir empty; ./rotate_logs.sh -d empty` | START + `DONE compressed=0 deleted=0 failed=0` | 0 |
| 2 | Missing folder | `./rotate_logs.sh -d nope` | `ERROR: log directory 'nope' does not exist` | 2 |
| 3 | Spaces in name | default test data | `payment service.log` → `payment service.log.gz` | 0 |
| 4 | Running twice | `./rotate_logs.sh; ./rotate_logs.sh` | 2nd run: `compressed=0 deleted=0` (idempotent) | 0 |
| 5 | Dry run | `./rotate_logs.sh --dry-run` | `DRY-RUN:` lines, `ls` unchanged | 0 |
| 6 | Bad number | `./rotate_logs.sh -a x` | `ERROR: DAYS must be a non-negative integer` | 1 |
| 7 | Unknown option | `./rotate_logs.sh --foo` | error + usage text | 1 |
| 8 | Help | `./rotate_logs.sh -h` | usage text | 0 |
| 9 | Fresh/non-.log files | default data | app.log, error.log, access.log, notes.txt untouched | 0 |
| 10 | Read-only folder | `chmod a-w logs; ./rotate_logs.sh` | `not writable` error | 2 |

Tests 1, 2, 3, 4, 5 and 6 were run and gave exactly these results. Show the exit code with `echo $?` straight after each command.

---

## 7. Comparison with logrotate

| | `rotate_logs.sh` + cron | logrotate |
|---|---|---|
| Install | none (bash, find, gzip) | `sudo apt install logrotate` (preinstalled on most distros) |
| Trigger | your own cron entry | daily via `/etc/cron.daily/logrotate` or a systemd timer |
| Decides by | file age (mtime) | daily/weekly/size, with a state file `/var/lib/logrotate/status` |
| Active log files | not handled (only old, finished files) | `copytruncate` or `postrotate` to signal the app |
| Numbered history | no | yes (`.1`, `.2.gz` …, `rotate N`) |
| Flexibility | full control; easy to learn and change | standard and well tested, but uses its own config syntax |

Sample config `/etc/logrotate.d/myapp`:
```
/home/<user>/lab23/logs/*.log {
    daily               # check every day
    rotate 30           # keep 30 old copies
    maxage 30           # delete rotated logs older than 30 days
    compress            # gzip rotated files
    delaycompress       # leave the newest rotated file uncompressed for one cycle
    missingok           # no error if the log is missing
    notifempty          # skip empty logs
    copytruncate        # copy, then empty the original (the app keeps its file handle)
    dateext             # name like app.log-20261006
    su <user> <user>    # rotate as this user
}
```
Test it: `sudo logrotate -d /etc/logrotate.d/myapp` (debug/dry run), force it: `sudo logrotate -f /etc/logrotate.d/myapp`.
(Comments are on their own lines in a real logrotate file. Inline `#` comments are shown here only to explain each option.)

---

## 8. Screenshot list

| # | Capture | Caption |
|---|---|---|
| 1 | `service cron status` → running | Fig 1: cron service running in WSL Ubuntu |
| 2 | `cat rotate_logs.sh` (top part + options) | Fig 2: rotate_logs.sh source with comments |
| 3 | `./create_test_logs.sh` output | Fig 3: Test logs created with backdated timestamps |
| 4 | `ls -lh --time-style=long-iso logs` (before) | Fig 4: Log folder before rotation (542K) |
| 5 | `./rotate_logs.sh --dry-run` | Fig 5: Dry run lists actions without changing files |
| 6 | `./rotate_logs.sh; echo $?` | Fig 6: Real run – 3 compressed, 1 deleted, exit 0 |
| 7 | `ls -lh` (after) | Fig 7: Log folder after rotation (167K) |
| 8 | `./rotate_logs.sh --help` | Fig 8: Usage/help message |
| 9 | Missing folder + empty folder + second run, each with `echo $?` | Fig 9: Edge case results and exit codes |
| 10 | `crontab -l` showing both entries | Fig 10: Crontab with daily 02:00 and 2-minute test entries |
| 11 | `tail rotate_cron.log` with cron-run timestamps | Fig 11: Output written by cron-triggered runs |
| 12 | `grep CRON /var/log/syslog \| tail` | Fig 12: Syslog proves cron executed the script |
| 13 | `crontab -l` after removing test entry | Fig 13: Final crontab – daily 02:00 only |

---

## 9. Report

**Title:** Automated Log Rotation and Compression using Bash and cron

**Objective:** Write a Bash script that compresses application logs older than 7 days, deletes compressed archives older than 30 days, and schedules the script with cron so it runs without manual work.

**Tools used:** Ubuntu on WSL2 (or Linux/macOS), GNU Bash 5, `find`, `gzip`, `touch`, `ls`, `cron`/`crontab`, `rsyslog`, and logrotate for comparison.

**Procedure:**
1. Installed and started cron and rsyslog (`sudo apt install cron rsyslog; sudo service cron start`).
2. Wrote `create_test_logs.sh`, which creates nine files of different ages using `touch -d "N days ago"`, including a file name with a space, a non-.log file, and two existing archives.
3. Wrote `rotate_logs.sh` with strict mode (`set -euo pipefail`), settings from options or env vars, input checks, safe file handling with `find -print0`, gzip compression, deletion of old archives, timestamped logging, dry-run and help options, and exit codes.
4. Saved the folder listing before the run, ran a dry run, ran the script, and saved the listing after the run.
5. Ran the edge case tests (empty folder, missing folder, spaces in names, second run, dry run, invalid input).
6. Added a temporary `*/2 * * * *` cron entry, checked the run with `crontab -l`, the output log and syslog, then replaced it with the daily `0 2 * * *` entry.

**Results:**
- 3 log files older than 7 days (app-old.log, debug.log, `payment service.log`) were compressed. 1 archive older than 30 days was deleted. Fresh logs, notes.txt and the 15-day-old archive were left alone.
- Folder size dropped from 542 KB to 167 KB. The 380 KB of old logs became about 1.7 KB of archives (test data repeats one line, so it compresses very well).
- The second run changed nothing, so the script is idempotent. A missing folder gave exit code 2, invalid input gave 1, and successful runs gave 0.
- cron ran the script every 2 minutes. This is confirmed by `rotate_cron.log` and the `CRON ... CMD` lines in `/var/log/syslog`.

**Observations:**
- `find -mtime +7` counts whole 24-hour periods, so a file must be at least 8 full days old to match. A file 7.5 days old is not matched.
- cron runs with a minimal environment, so absolute paths and output redirection are required.
- WSL does not start cron automatically. A `/etc/wsl.conf` boot command, or running the start command manually, is needed.
- The archive keeps the original log's modification time (`touch -r`), so retention is counted from the log's real age.
- Without `-print0` / `read -d ''`, the file `payment service.log` would be split into two names and fail.
- With `pipefail`, `yes | head` exits with code 141 (SIGPIPE). Process substitution avoids this.

**Conclusion:** A short Bash script plus one crontab line handles automatic log rotation reliably. It saves disk space, keeps logs readable, and enforces a retention policy. Strict mode, input checks, dry-run and exit codes make it safe to run unattended. On production servers, logrotate offers more features (it can handle log files that are still being written, and keeps numbered history), but the same ideas apply: rotate by age, compress, and delete after a retention period.

---

## 10. Viva preparation

### Cron expression breakdown
```
 ┌───────── minute        (0-59)   0      → at minute 0
 │ ┌─────── hour          (0-23)   2      → at 2 AM
 │ │ ┌───── day of month  (1-31)   *      → every day
 │ │ │ ┌─── month         (1-12)   *      → every month
 │ │ │ │ ┌─ day of week   (0-7, 0/7 = Sun) * → every weekday
 0 2 * * *  command
```
`0 2 * * *` means "every day at 02:00". `*/2 * * * *` means "every minute that divides by 2", so every 2 minutes. Other examples: `30 1 * * 0` (Sundays 01:30), `0 */6 * * *` (every 6 hours), `0 2 1 * *` (1st of each month), `@daily` (= `0 0 * * *`), `@reboot` (at startup).

**Q1. Explain the cron expression you used.**
`0 2 * * *` has five fields: minute 0, hour 2, and `*` (any) for day of month, month and day of week. So the job runs once a day at 2:00 AM in the system's local time. 2 AM is chosen because traffic is low, so compressing files doesn't slow the application. For testing I used `*/2 * * * *`, where `*/2` is a step value meaning every 2nd minute. The command after the fields uses absolute paths, and `>> file 2>&1` appends both normal output and errors to a log file, because cron has no terminal.

**Q2. Why rotate logs?**
1. **Disk space.** Logs keep growing, and a full disk can crash the app and the OS. Compressing text logs saves 80–95%.
2. **Performance and usability.** Small per-day files are faster to search, open and transfer than one huge file.
3. **Retention and compliance.** Policies (and laws like GDPR) say how long logs must or may be kept. Automatic deletion enforces this.
4. **Archiving and analysis.** Closed, dated archives are easy to back up or send to a log server.
5. **Automation.** No one has to clean up by hand, so nobody forgets.

**Q3. What does `set -euo pipefail` do?**
`-e` exits on the first failing command. `-u` treats unset variables as errors, which catches typos like `$LOGDIR`. `-o pipefail` makes a pipeline fail if any part fails, not only the last command. Together they stop the script from carrying on after an error, for example deleting files after a failed step.

**Q4. How does your script handle file names with spaces?**
`find ... -print0` separates names with a NUL byte, which can never appear in a file name. `while IFS= read -r -d '' f` reads up to each NUL, and `"$f"` is always quoted. `--` stops a name starting with `-` from being read as an option.

**Q5. What is the meaning of `-mtime +7`?**
It matches files whose modification time is more than 7 full 24-hour periods ago, which in practice means 8 or more days old. `-mtime 7` means exactly 7 days, and `-mtime -7` means less than 7 days. Related options: `-mmin` (minutes), `-atime` (last access), `-ctime` (last status change).

**Q6. Why does cron need absolute paths and output redirection?**
cron starts jobs with a minimal environment: PATH is `/usr/bin:/bin`, the working directory is `$HOME`, and your `.bashrc` is not loaded. Relative paths and custom commands may not be found. cron also has no terminal, so output is mailed or thrown away. `>> file 2>&1` keeps it for checking.

**Q7. What is the difference between `crontab -e`, `/etc/crontab` and `/etc/cron.d`?**
`crontab -e` edits the current user's table (stored in `/var/spool/cron/crontabs/<user>`). `/etc/crontab` and `/etc/cron.d/*` are system tables with an extra **user** field (`0 2 * * * root cmd`). `/etc/cron.daily/` and similar folders hold scripts run by run-parts. `crontab -l` lists the table and `crontab -r` removes it (careful!).

**Q8. How did you prove that cron actually ran the script?**
Three pieces of evidence: new timestamped START/DONE lines in `rotate_cron.log` at 2-minute intervals that I did not trigger, `CRON[pid]: (user) CMD (...)` lines in `/var/log/syslog` (or `journalctl -u cron`), and the folder listing showing the old `.log` files had become `.gz`.

**Q9. When would you use logrotate instead of your script?**
On production servers. logrotate handles log files the app is still writing to (`copytruncate`, or `postrotate` to reload the service), rotates by size or interval, keeps numbered history, records state, and is the standard tool on Linux. A custom script suits simple age-based cleanup, systems without logrotate, or cases that need custom logic.

**Q10. Why gzip, and how do you read a compressed log?**
gzip is fast, available everywhere, and very effective on repetitive text. You can read archives without extracting them: `zcat`, `zless`, `zgrep "ERROR" app.log.gz`. Use `gunzip` to restore. Alternatives: `xz` (smaller files, slower) and `zstd` (fast with good compression).

**Q11. What exit codes does your script return and why do they matter?**
0 success, 1 usage error, 2 folder missing or not writable, 3 compression failure. Monitoring tools, CI pipelines and wrapper scripts check `$?` to detect failures and send alerts.
