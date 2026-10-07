# Lab #23 – Log Rotation with Bash & cron (DevOps)

**K Author Abhikhyath Gundi** · 24WU0101126 · B.Tech CSE (Panthers)

A Bash script that compresses app logs older than 7 days, deletes archives older than 30 days, and is scheduled with cron.

| Path | Description |
|---|---|
| `rotate_logs.sh` | Main script: `set -euo pipefail`, `-d/-a/-r` options or `LOG_DIR`/`DAYS`/`RETENTION_DAYS` env vars, `--dry-run`, `--help`, exit codes 0/1/2/3 |
| `create_test_logs.sh` | Builds the sample `logs/` folder (fresh + backdated files, a name with a space) |
| `logs/` | Sample log folder |
| `LAB23_REPORT.md` | Setup, cron, edge cases, logrotate comparison, viva answers |
| `report/` | Final report (DOCX + PDF) and screenshots |

## Usage
```bash
chmod +x *.sh
./create_test_logs.sh
ls -lh logs                 # before
./rotate_logs.sh --dry-run
./rotate_logs.sh -d ./logs -a 7 -r 30
ls -lh logs                 # after
```

## Crontab entry (daily at 02:00)
```cron
0 2 * * * /home/abhikhyath/lab23/rotate_logs.sh -d /home/abhikhyath/lab23/logs -a 7 -r 30 >> /home/abhikhyath/lab23/rotate_cron.log 2>&1
```

## Result
Folder size went from 552 KB to 180 KB. The 3 old logs (380 KB) were compressed to about 1.6 KB, and 1 expired archive was deleted.
